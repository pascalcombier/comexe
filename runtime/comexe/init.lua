--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- NOTE
--
-- This file is the first Lua file loaded by the C engine for each thread. It
-- basically setup the searchers/loaders function. That's why it cannot
-- require() other files from the embeded ZIP. This is why the buffer NewBuffer
-- is not implemented in its own buffer.lua but here.

-- STANDARD LUA REQUIRE BEHAVIOUR
--
-- require() need package.path
--
-- By default, package.path behaviour is platform depdendant, defined in:
-- third-party\src\lua\src\loadlib.c
--
-- On Linux, it's trivial, absolute paths are defined at build-time LUA_ROOT
-- defaulted as "/usr/local/" in third-party\src\lua\src\luaconf.h This can be
-- overriden at runtime with environment variables LUA_PATH or LUA_CPATH
--
-- On Windows, the function setprogdir is implemented and use
-- GetModuleFileNameA() to determine the directory where is located
-- lua54.exe. That directory is used as a dynamically-build LUA_ROOT.
--
-- Printing package.path at runtime should look like:
-- (LUA54.EXE)DIR\lua\?.lua;
-- (LUA54.EXE)DIR\lua\?\init.lua;
-- (LUA54.EXE)DIR\?.lua;
-- (LUA54.EXE)DIR\?\init.lua;
-- (LUA54.EXE)DIR\..\share\lua\5.5\?.lua;
-- (LUA54.EXE)DIR\..\share\lua\5.5\?\init.lua;
-- .\?.lua;     << this is relative to the current directory (%CD%) NOTE-3
-- .\?\init.lua << this is relative to the current directory (%CD%) NOTE-3
--
-- NOTE-1 the use of GetModuleFileNameA() probably brings issues with files
-- named using UTF characters.
--
-- NOTE-2 the Lua-defined dependancy directory (share\lua\5.5\?.lua) will be
-- relative to the executable directory, which could make sense, for example you
-- install Lua in C:\Program Files\Lua and manually manage your dependancies
-- from here.
-- 
-- But the point of ComEXE is to build self-contained executables. And in the
-- same time we want to have a fast edit/run iterations without re-generating
-- executable files. So we want lua54.exe package.path to be relative to the
-- main lua script location:
--
-- my-app\main.lua
-- my-app\share\lua\5.5\<DEPS>.lua
--
-- And in the same time we want to keep compatibility with original
-- lua54.exe. So we want to support both.
--
-- NOTE-3 this behaviour is also not what we want. It make the loading of the
-- files relative to current directory instead of relative to main script file
-- location, it does not work well in that case: > lua54 my-app\main.lua which
-- would require my-app\lib.lua
--
-- CONCLUSION: in the default behaviour of "require" with default package.path,
-- no entry from package.path is satisfactory.
--
--
-- LUA STANDARD package.searchers
--
-- 1) looks for a loader in the package.preload table
-- 2) looks for a loader as a Lua library, using the path stored at package.path.
-- 3) looks for a loader as a C library, using the path given by the variable package.cpath. (.so, .dll)
-- 4) Similar to 3
--
-- For the time being, we only focus on 1) and 2) because while we could include
-- a DLL inside the ZIP, it would be hard to load that one dynamically.
--
--
-- ComEXE REQUIRE BEHAVIOUR
--
-- The loader behaviour must be configurable at runtime. Because we want to
-- provide lua54ce.exe with behaviour as close as possible as lua54.exe. That
-- lua54ce.exe is an application build with ComEXE framework, it embbeds a
-- main.lua file.
--
-- So we need to be careful when loading ZIP-ROOT/main.lua or LUA-APP/main.lua.
--
--
-- 
-- 
--
--
-- FILE ORGANIZATION
--
-- This project comes with some batteries. One example is LuaSocket. LuaSocket
-- comes with both C files and Lua files. We already had to store tcc files in a
-- dedicated "comexe" directory in the root of the ZIP archive.
--
-- ZIP-ROOT/comexe/init.lua
-- ZIP-ROOT/comexe/usr/include
-- ZIP-ROOT/comexe/usr/lib
-- ZIP-ROOT/comexe/usr/share
--
-- Naturally, we added:
-- ZIP-ROOT/comexe/usr/share/lua/5.5
--
-- We want to be close to Lua default behavior
-- ZIP-ROOT\lua\?.lua
-- ZIP-ROOT\lua\?\init.lua
-- ZIP-ROOT\?.lua;
-- ZIP-ROOT\?\init.lua;
-- ZIP-ROOT\..\share\lua\5.5\?.lua;
-- ZIP-ROOT\..\share\lua\5.5\?\init.lua
-- ZIP-ROOT\.\?.lua
-- ZIP-ROOT\.\?\init.lua
--
--
-- IMPLEMENTATION
--
-- LoaderConfiguration is a global setting from ComEXE application. It return a
-- string representing an ordered list of Lua "Searchers".
--
-- One letter correspond to one Searcher:
-- Z: ZIP Searcher, try to locate a module inside the embedded ZIP archive
-- F: File system, try to locate a module inside the file system
--
-- TCC third-party\src\tcc-vio\src\config.h defines the following:
-- #define CONFIG_TCCDIR "COMEXE-RUNTIME-V2/"
-- If a TCC event is refereing to "COMEXE-RUNTIME-V2/XXX" we want to find TCC files
-- from runtime files in ZIP.
--

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime   = require("com.raw.runtime")
local RawBuffer = require("com.raw.buffer")
local MiniZip   = require("com.raw.minizip")
local libffi    = require("com.raw.libffi")
local uv        = require("luv")

local format             = string.format
local append             = table.insert
local remove             = table.remove
local concat             = table.concat
local min                = math.min
local max                = math.max
local searchpath         = package.searchpath
local getloaderconfig    = Runtime.getloaderconfiguration
local setloaderconfig    = Runtime.setloaderconfiguration
local seteventhandler    = Runtime.seteventhandler
local setwarningfunction = Runtime.setwarningfunction
local UvCurrentDirectory = uv.cwd
local fs_open            = uv.fs_open
local fs_fstat           = uv.fs_fstat
local fs_read            = uv.fs_read
local fs_write           = uv.fs_write
local fs_lseek           = uv.fs_lseek
local fs_close           = uv.fs_close
local fs_dup             = uv.fs_dup

-- MiniZip
local unzip_open                  = MiniZip.unzip_open
local unzip_goto_first_file       = MiniZip.unzip_goto_first_file
local unzip_goto_next_file        = MiniZip.unzip_goto_next_file
local unzip_get_current_file_info = MiniZip.unzip_get_current_file_info
local unzip_open_current_file     = MiniZip.unzip_open_current_file
local unzip_read_current_file     = MiniZip.unzip_read_current_file
local unzip_close_current_file    = MiniZip.unzip_close_current_file
local unzip_close                 = MiniZip.unzip_close
local UNZ_OK                      = MiniZip.UNZ_OK
local UNZ_END_OF_LIST_OF_FILE     = MiniZip.UNZ_END_OF_LIST_OF_FILE

-- Standard errno constants for error handling
local ENOENT =  2 -- No such file or directory
local EIO    =  5 -- I/O error
local EBADF  =  9 -- Bad file descriptor
local EACCES = 13 -- Permission denied
local ESPIPE = 29 -- Illegal seek

-- Error number to name lookup table
local STDIO_ERROR_NAMES = {
  [ENOENT] = "ENOENT",
  [EIO]    = "EIO",
  [EBADF]  = "EBADF",
  [EACCES] = "EACCES",
  [ESPIPE] = "ESPIPE"
}

-- Prefix must match the prefix defined in libtcc at build time
local COMEXE_RUNTIME_PREFIX = "COMRAD-RUNTIME-V2/"

-- We need to keep a reference to original arg for INIT_GetArgs. This file will
-- override global arg to make command line parsing compatible between
-- MODE-STANDALONE and MODE-INTERPRETER: we adopt Lua "Standalone Mode" rules.
local INIT_Arg = arg

-- Owner: read/write, group/other: nothing
local INIT_DEFAULT_MODE = tonumber("600", 8)

--------------------------------------------------------------------------------
-- RUNTIME FUNCTIONS                                                          --
--------------------------------------------------------------------------------

-- Those functions should typically be implemented in com.runtime but since the
-- functions are also used here in init.lua we implement them early.

local function STRING_HasPrefix (String, Prefix)
  return (String:find(Prefix, 1, true) == 1)
end

local function STRING_RemovePrefix (String, Prefix)
  return String:sub(#Prefix + 1)
end

local function INIT_ArraySlice (Array, IndexStart, IndexEnd)
  local NewArray = {}
  for Index = IndexStart, IndexEnd do
    append(NewArray, Array[Index])
  end
  return NewArray
end

-- Unlike os.open, INIT_ReadFile supports UTF-8 named files on Windows
local function INIT_ReadFile (Filename, OutputType)
  -- local data
  local FileContents
  local ErrorMessage
  -- libuv is always binary mode
  local fd = fs_open(Filename, "r", 0)
  if fd then
    local StatInfo, ErrorMessageStat = fs_fstat(fd)
    if StatInfo then
      local SizeInBytes = StatInfo.size
      local Offset      = 0
      FileContents, ErrorMessage = fs_read(fd, SizeInBytes, Offset)
    else
      ErrorMessage = ErrorMessageStat
    end
    fs_close(fd)
  else
    ErrorMessage = format("Failed to open file for reading: %s", Filename)
  end
  -- Convenient but slow post processing
  local Result
  if (OutputType == nil) or (OutputType == "string") then
    Result = FileContents
  elseif (OutputType == "lines") then
    local Lines = {}
    for Line in FileContents:gmatch("([^\r\n]*)\r?\n?") do
      append(Lines, Line)
    end
    Result = Lines
  end
  -- Return value
  return Result, ErrorMessage
end

-- Unlike os.open, INIT_WriteFile supports UTF-8 named files on Windows
local function INIT_WriteFile (Filename, Data)
  -- local data
  local Success
  local ErrorMessage
  local fd
  -- libuv is always binary mode. create if not exists, overwrite contents if exists
  fd = fs_open(Filename, "w", INIT_DEFAULT_MODE)
  if fd then
    local Offset = 0
    Success, ErrorMessage = fs_write(fd, Data, Offset)
    fs_close(fd)
  else
    ErrorMessage = format("Failed to open file for writing: %s", Filename)
  end
  -- Handle success
  Success = (ErrorMessage == nil)
  -- Return value
  return Success, ErrorMessage
end

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function FormatStdioErrorResult (Result)
  local ErrorMessage
  if (Result < 0) then
    local ErrorCode = -Result
    local ErrorName = STDIO_ERROR_NAMES[ErrorCode]
    if ErrorName then
      ErrorMessage = format("%d (-%s)", Result, ErrorName)
    else
      ErrorMessage = format("%d (error)", Result)
    end
  else
    ErrorMessage = format("%d (fd)", Result)
  end
  return ErrorMessage
end

--------------------------------------------------------------------------------
-- PATHNAME COMPATIBILITY COMPONENT                                           --
--------------------------------------------------------------------------------

-- This was initially implementated in com/pathname.lua but we actually need
-- part of the implementation in init.lua, so we moved it here.

local PATH_NativeSeparator   = package.config:sub(1, 1)
local PATH_InternalSeparator = "/"

local INIT_ARCH = "x86_64" -- Only support that for now
local INIT_OS
local PATH_InternalPathname
local PATH_NativePathname

if (PATH_NativeSeparator == "/") then
  local function IdentityFunction (Pathname)
    return Pathname
  end
  INIT_OS               = "linux"
  PATH_InternalPathname = IdentityFunction
  PATH_NativePathname   = IdentityFunction
else
  INIT_OS               = "windows"
  PATH_InternalPathname = function (Pathname)
    return Pathname:gsub(PATH_NativeSeparator, PATH_InternalSeparator)
  end
  PATH_NativePathname = function (Pathname)
    return Pathname:gsub(PATH_InternalSeparator, PATH_NativeSeparator)
  end
end

local INIT_BinarySuffix = format("-%s-%s.bin", INIT_ARCH, INIT_OS)

local PATH_ROOT = { "ROOT" }

-- Windows DRIVE C: D: E: etc
local function PATH_MakeDrive (DriveLetter)
  local Result = { "DRIVE", DriveLetter }
  return Result
end

-- Windows UNC
local function PATH_MakeUNC (Server, Share)
  local Result = { "UNC", Server, Share }
  return Result
end

-- Either PATH_ROOT or {"DRIVE", Letter} or {"UNC", Server, Share}
local function PATH_IsSpecial (Element)
  local Result = (type(Element) == "table")
  return Result
end

-- Based on pathnames created by internalpathname
-- Split path into parts and detect root/drive
local function PATH_SplitPathString (Pathname)
  -- local data
  local Elements     = {}
  local InternalPath = Pathname
  local IsAbsolute   = false
  local DriveLetter  = InternalPath:match("^([A-Za-z]):")
  -- Parse
  if DriveLetter then
    -- Perform 2 things after Windows drive letter is found:
    -- remove the "C:"
    -- Remove all the slashes immediatly after C://///////directory
    InternalPath = InternalPath:gsub("^%a:/*", "")
    -- Save the drive
    append(Elements, PATH_MakeDrive(DriveLetter))
    IsAbsolute = true
  elseif (INIT_OS == "windows") and STRING_HasPrefix(InternalPath, "//") then
    -- Windows UNC
    local Server, Share, Remaining = InternalPath:match("^//+([^/]+)/+([^/]+)(.*)")
    if (Server and Share) then
      append(Elements, PATH_MakeUNC(Server, Share))
      InternalPath = Remaining:gsub("^/*", "")
      IsAbsolute   = true
    else
      -- Fallback if malformed UNC
      if STRING_HasPrefix(InternalPath, "/") then
        -- Remove multiple leading slashes like ///////directory
        InternalPath = InternalPath:gsub("^/+", "")
        -- Save the root
        append(Elements, PATH_ROOT)
        IsAbsolute = true
      end
    end
  else
    -- No drive letter: check for a Linux absolute path "/"
    if STRING_HasPrefix(InternalPath, "/") then
      -- Remove multiple leading slashes like ///////directory
      InternalPath = InternalPath:gsub("^/+", "")
      -- Save the root
      append(Elements, PATH_ROOT)
      IsAbsolute = true
    end
  end
  -- At this point, InternalPath has no drive and no leading slash
  for Part in InternalPath:gmatch("[^/]+") do
    if (Part ~= ".") then
      append(Elements, Part)
    end
  end
  -- Return values
  return Elements, IsAbsolute
end

-- Simpify elements by processing ".."
local function PATH_ResolveElements (Elements, IsAbsolute)
  -- local data
  local Relative = (not IsAbsolute)
  local Resolved = {}
  -- Process elements
  for Index = 1, #Elements do
    local Element = Elements[Index]
    if (Element == "..") then
      local LastIndex   = #Resolved
      local LastElement = Resolved[LastIndex]
      -- Avoid case { "..", "..", "DIR" }
      local HasRoot      = (type(LastElement) == "table")
      local HasRemovable = (LastElement and (not HasRoot) and (LastElement ~= ".."))
      if HasRemovable then
        remove(Resolved, LastIndex)
      else
        if Relative then
          append(Resolved, "..")
        -- else we are in the case where
        -- Absolute + not removable: just ignore ".."
        end
      end
    else
      append(Resolved, Element)
    end
  end
  -- Return value
  return Resolved
end

local function PATH_BuildStringFromElements (Elements, StartIndex, EndIndex, Separator)
  -- local data
  local Parts        = {}
  local FirstElement = Elements[1]
  -- Handle ROOT
  local ActualStartIndex
  if (StartIndex == 1) and PATH_IsSpecial(FirstElement) then
    if (FirstElement[1] == "ROOT") then
      -- Tricky: concat will see { "", "dir" } and will join with "/"
      -- producing "/dir" (and not "//dir" if we used { "/", "dir" })
      append(Parts, "")
    elseif (FirstElement[1] == "UNC") then
      -- UNC: //Server/Share
      append(Parts, "") -- Same trick as above for ROOT: add a /
      append(Parts, "") -- Same trick as above for ROOT: add a /
      append(Parts, FirstElement[2])
      append(Parts, FirstElement[3])
    else
      local DriveLetter = FirstElement[2]
      append(Parts, format("%s:", DriveLetter))
    end
    -- Skip the first element as already handled
    ActualStartIndex = 2
  else
    ActualStartIndex = StartIndex
  end
  -- Collect the remaining parts
  for Index = ActualStartIndex, EndIndex do
    local Element = Elements[Index]
    append(Parts, Element)
  end
  -- Join parts
  local Result
  if (#Parts == 1) then
    if (StartIndex == 1) and PATH_IsSpecial(FirstElement) then
      if (FirstElement[1] == "ROOT") then
        Result = Separator
      else
        -- Special case to make "C:" become "C:/"
        Result = format("%s%s", Parts[1], Separator)
      end
    else
      Result = Parts[1]
    end
  else
    Result = concat(Parts, Separator)
  end
  -- Return result
  return Result
end

--------------------------------------------------------------------------------
-- PATHNAME METHODS                                                           --
--------------------------------------------------------------------------------

-- Pre-declaration
local PATH_Metatable

local function PATH_MethodConvert (Pathname, OptionalMode)
  -- Handle defaults
  local Mode = (OptionalMode or "native")
  -- Retrieve data
  local Elements   = Pathname
  local StartIndex = 1
  local EndIndex   = #Elements
  -- Determine separator
  local Separator
  if (Mode == "native") then
    Separator = PATH_NativeSeparator
  else
    Separator = PATH_InternalSeparator
  end
  -- Build result
  local Result = PATH_BuildStringFromElements(Elements, StartIndex, EndIndex, Separator)
  return Result
end

local function PATH_MethodGetDirectory (Pathname, OptionalMode)
  -- Handle defaults
  local Mode = (OptionalMode or "native")
  -- Retrieve data
  local Elements   = Pathname
  local StartIndex = 1
  local EndIndex   = (#Elements - 1)
  -- Determine separator
  local Separator
  if (Mode == "native") then
    Separator = PATH_NativeSeparator
  else
    Separator = PATH_InternalSeparator
  end
  -- Build result
  local Result = PATH_BuildStringFromElements(Elements, StartIndex, EndIndex, Separator)
  return Result
end

-- parent() and child() return pathname to allow chaining
local function PATH_MethodParent (Pathname)
  -- Retrieve data
  local Elements     = Pathname
  local LastIndex    = #Elements
  local LastElement  = Elements[LastIndex]
  local FirstElement = Elements[1]
  -- Determine if path is relative or absolute
  local IsAbsolute = PATH_IsSpecial(FirstElement)
  -- Process
  if IsAbsolute then
    -- Absolute: can't go above root/drive
    -- Because if we put ".." it means relative, which is dangerous
    if (LastIndex >= 1) and (type(LastElement) == "string") then
      remove(Elements, LastIndex)
    end
  else
    -- Relative: empty path or already at ".." means we append another ".."
    if (LastIndex == 0) or (LastElement == "..") then
      append(Elements, "..")
    else
      -- Something like "dir/file" becomes "dir"
      remove(Elements, LastIndex)
    end
  end
  -- Return value and allow chaining
  return Pathname
end

-- parent() and child() return pathname to allow chaining
local function PATH_MethodChild (Pathname, Name)
  -- Retrieve data
  local Elements = Pathname
  -- Append
  append(Elements, Name)
  -- Return value and allow chaining
  return Pathname
end

-- setname() replaces the last element, return pathname to allow chaining
local function PATH_MethodSetName (Pathname, Name)
  -- local data
  local Elements    = Pathname
  local LastIndex   = #Elements
  -- Replace the last element
  if (LastIndex >= 1) then
    Elements[LastIndex] = Name
  else
    -- Empty path: equivalent to "." so we add the name
    append(Elements, Name)
  end
  -- Return value and allow chaining
  return Pathname
end

local function PATH_MethodRemoveElement (Pathname, Index)
  -- Remove element at the given index
  remove(Pathname, Index)
  -- Return value and allow chaining
  return Pathname
end

local function PATH_MethodGetName (Pathname)
  -- Retrieve data
  local Elements    = Pathname
  local LastIndex   = #Elements
  local LastElement = Elements[LastIndex]
  local Name
  -- Handle root
  if PATH_IsSpecial(LastElement) then
    if (LastElement[1] == "UNC") then
      Name = format("%s/%s", LastElement[2], LastElement[3])
    else
      Name = LastElement[2] -- drive letter or nil for Linux's root
    end
  else
    Name = LastElement
  end
  -- Extract basename and extension
  local Basename
  local Extension
  if Name then
    Basename  = (Name:match("^(.+)%.[^%.]+$") or Name)
    Extension = Name:match("^.+(%.[^%.]+)$")
    if Extension then
      Extension = Extension:sub(2) -- drop the "." of ".txt"
    end
  end
  -- Return value
  return Name, Basename, Extension
end

local function PATH_MethodClone (Pathname)
  local NewPathname = {}
  for Index = 1, #Pathname do
    append(NewPathname, Pathname[Index])
  end
  setmetatable(NewPathname, PATH_Metatable)
  -- Return value and allow chaining
  return NewPathname
end

local function PATH_MethodIsAbsolute (Pathname)
  local FirstElement = Pathname[1]
  local Result       = PATH_IsSpecial(FirstElement)
  return Result
end

local function PATH_MethodIsRelative (Pathname)
  local Result = (not PATH_MethodIsAbsolute(Pathname))
  return Result
end

local function PATH_MethodDepth (Pathname)
  return #Pathname
end

local function PATH_MethodToString (Pathname)
  local Result = Pathname:convert("native")
  return Result
end

local function PATH_MethodConcat (LeftPath, RightPath)
  -- local data
  local LeftMetatable  = getmetatable(LeftPath)
  local RightMetatable = getmetatable(RightPath)
  -- Validate inputs
  assert((LeftMetatable  == PATH_Metatable), format("Wrong type: got %s expected pathname", type(LeftMetatable)))
  assert((RightMetatable == PATH_Metatable), format("Wrong type: got %s expected pathname", type(RightMetatable)))
  -- Merge elements
  local MergedElements = {}
  local LeftElements   = LeftPath
  local RightElements  = RightPath
  for Index = 1, #LeftElements do
    append(MergedElements, LeftElements[Index])
  end
  for Index = 1, #RightElements do
    append(MergedElements, RightElements[Index])
  end
  -- Attach metatable
  setmetatable(MergedElements, PATH_Metatable)
  -- Return value
  return MergedElements
end

local PATH_MetatableImpl = {
  -- Generic methods
  __tostring = PATH_MethodToString,
  __concat   = PATH_MethodConcat,
  -- Specific methods
  __index = {
    convert      = PATH_MethodConvert,
    parent       = PATH_MethodParent,
    child        = PATH_MethodChild,
    setname      = PATH_MethodSetName,
    remove       = PATH_MethodRemoveElement,
    getdirectory = PATH_MethodGetDirectory,
    getname      = PATH_MethodGetName,
    clone        = PATH_MethodClone,
    isabsolute   = PATH_MethodIsAbsolute,
    isrelative   = PATH_MethodIsRelative,
    depth        = PATH_MethodDepth,
  }
}
PATH_Metatable = PATH_MetatableImpl

local function PATH_NewPathname (Pathname)
  -- Normalize path: use Linux forward slashes not Windows backslashes
  local NormalizedPath = PATH_InternalPathname(Pathname)
  -- Parse pathname
  local Elements, Absolute = PATH_SplitPathString(NormalizedPath)
  local ResolvedElements   = PATH_ResolveElements(Elements, Absolute)
  -- Attach metatable
  setmetatable(ResolvedElements, PATH_Metatable)
  -- Return value
  return ResolvedElements
end

--------------------------------------------------------------------------------
-- HIGH LEVEL BUFFER IMPLEMENTATION                                           --
--------------------------------------------------------------------------------

-- This buffer is hard to implement in its own file "buffer.lua" because ZIP
-- extraction needs NewBuffer and at this stage PACKAGE.SEARCHERS function is
-- not yet available.

local GetPageSize       = libffi.getpagesize
local RawNewBuffer      = RawBuffer.newbuffer
local RawGetCapacity    = RawBuffer.getcapacity
local RawEnsureCapacity = RawBuffer.ensurecapacity
local RawFreeBuffer     = RawBuffer.freebuffer
local RawGetBufferData  = RawBuffer.getbufferdata
local RawReadBuffer     = RawBuffer.read
local RawWriteBuffer    = RawBuffer.write

local function BUFFER_MethodGarbage (Buffer)
  -- Retrieve data
  local RawBuffer = Buffer.RawBuffer
  -- Call C API
  RawFreeBuffer(RawBuffer)
end

-- It's important to provide a GetCapacity so that the API users could double
-- the size of the underlying buffer
local function BUFFER_GetCapacity (Buffer)
  -- Retrieve data
  local RawBuffer = Buffer.RawBuffer
  -- Call C API
  local BufferCapacity = RawGetCapacity(RawBuffer)
  -- Return value
  return BufferCapacity
end

local function BUFFER_MethodEnsureCapacity (Buffer, SizeInBytes)
  -- Retrieve data
  local RawBuffer = Buffer.RawBuffer
  -- Call C API
  local NewRawBuffer = RawEnsureCapacity(RawBuffer, SizeInBytes)
  -- Update pointer
  Buffer.RawBuffer = NewRawBuffer
end

local function BUFFER_GetData (Buffer, Offset)
  -- Retrieve data
  local RawBuffer  = Buffer.RawBuffer
  local NewPointer = RawGetBufferData(RawBuffer, Offset)
  -- Return value
  return NewPointer
end

local function BUFFER_MethodRead (BufferObject, IndexStart, IndexEnd)
  -- Call raw C binding
  local RawBuf = BufferObject.RawBuffer
  local Result = RawReadBuffer(RawBuf, IndexStart, IndexEnd)
  return Result
end

local function BUFFER_MethodWrite (BufferObject, Data, Index)
  -- Handle default values
  local RealIndex = (Index or 1)
  -- Write the buffer
  local RawBuf = BufferObject.RawBuffer
  local Result = RawWriteBuffer(RawBuf, Data, RealIndex)
  -- Return value
  return Result
end

local BUFFER_Metatable = {
  -- Generic methods
  __gc = BUFFER_MethodGarbage,
  -- Custom methods
  __index = {
    getcapacity    = BUFFER_GetCapacity,
    ensurecapacity = BUFFER_MethodEnsureCapacity,
    getpointer     = BUFFER_GetData,
    read           = BUFFER_MethodRead,
    write          = BUFFER_MethodWrite,
  }
}

-- Buffer is lightuserdata, allowing to be shared accross threads if needed
-- Cons: need manual memory management
local function NewBuffer (Capacity)
  -- Create the buffer on the C side
  local BufferPointer = RawNewBuffer(Capacity)
  -- Create a new Lua object
  local NewBufferObject = {
    RawBuffer = BufferPointer
  }
  -- Attach methods
  setmetatable(NewBufferObject, BUFFER_Metatable)
  -- Return value
  return NewBufferObject
end

--------------------------------------------------------------------------------
-- MINIZIP HANDLING                                                           --
--------------------------------------------------------------------------------

-- For simplicity we store ZIP_File as a global variable

-- Reuse buffer for reading ZIP file contents
local ZIP_Filename = INIT_Arg[1] -- the executable always embed a ZIP file
local PAGE_SIZE    = GetPageSize()
local ZIP_Buffer   = NewBuffer(PAGE_SIZE)
local ZIP_File     = unzip_open(ZIP_Filename)

assert(ZIP_File, format("Failed to open ZIP file: %s", ZIP_Filename))

local function ZIP_ExtractFile (FileInfo)
  -- local data
  local Result = unzip_open_current_file(ZIP_File)
  local FileContent
  -- Extract file content
  if (Result == UNZ_OK) then
    local SizeInBytes = FileInfo.uncompressed_size
    -- Read the entire file content
    if (SizeInBytes > 0) then
      -- Ensure our buffer has enough capacity for the entire file
      ZIP_Buffer:ensurecapacity(SizeInBytes)
      -- The buffer might have moved in memory
      local BufferData = ZIP_Buffer:getpointer()
      -- Read the entire file in one operation
      local Data, ErrorMessage = unzip_read_current_file(ZIP_File, SizeInBytes, BufferData, SizeInBytes)
      if Data and (#Data > 0) then
        FileContent = Data
      end
    elseif (SizeInBytes == 0) then
      FileContent = ""
    end
    -- Close entry
    unzip_close_current_file(ZIP_File)
  end
  -- Return value
  return FileContent
end

local function INIT_ZipLoadFile (ZipEntryName)
  -- local data
  local FileContent = nil
  local Result      = unzip_goto_first_file(ZIP_File)
  local Continue    = (Result == UNZ_OK)
  local FileFound   = false
  -- Process files while we have more files and haven't found our target
  while Continue and (not FileFound) do
    -- Get current file information
    local FileInfo, ErrorMessage = unzip_get_current_file_info(ZIP_File)
    -- Check entry
    if FileInfo and (FileInfo.filename == ZipEntryName) then
      FileContent = ZIP_ExtractFile(FileInfo)
      FileFound   = true
    else
      -- Move to next file
      Result = unzip_goto_next_file(ZIP_File)
      -- Error handling
      if (Result == UNZ_END_OF_LIST_OF_FILE) then
        Continue = false -- Normal end of file list
      elseif (Result ~= UNZ_OK) then
        Continue = false -- Error occurred
      end
    end
  end
  -- Return the file content
  return FileContent
end

--------------------------------------------------------------------------------
-- PROVIDE ID (1,2,3,..) AND REUSE THEM FOR TCC VIRTUAL FILE DESCRIPTORS      --
--------------------------------------------------------------------------------

local NextId  = 1
local FreeIds = {}

local function GetNewId ()
  local NewId
  if (#FreeIds > 0) then
    -- Reuse the last id
    NewId = remove(FreeIds)
  else
    NewId  = NextId
    NextId = (NextId + 1)
  end
  return NewId
end

local function ReleaseId (Id)
  append(FreeIds, Id)
end

--------------------------------------------------------------------------------
-- TCC EVENTS                                                                 --
--------------------------------------------------------------------------------

-- Global table to store file information for TCC virtual I/O
local TccFiles = {}

-- File open flags constants
local O_RDONLY = 0
local O_WRONLY = 1
local O_RDWR   = 2
local O_APPEND = 8
local O_CREAT  = 64
local O_TRUNC  = 512   -- Needed by tcc_write_elf_file
local O_BINARY = 32768 -- Needed by tcc_write_elf_file

local function TCC_MakeOpenFlagsString (Flags)
  -- Accumulate flag strings
  local FlagStrings = {}
  -- O_RDONLY is 0 so so classic bit check does not work 
  if ((Flags & O_WRONLY) == 0) and ((Flags & O_RDWR) == 0) then
    append(FlagStrings, "O_RDONLY")
  end
  -- The bits below are not 0
  if ((Flags & O_WRONLY) ~= 0) then
    append(FlagStrings, "O_WRONLY")
  end
  if ((Flags & O_RDWR) ~= 0) then
    append(FlagStrings, "O_RDWR")
  end
  if ((Flags & O_APPEND) ~= 0) then
    append(FlagStrings, "O_APPEND")
  end
  if ((Flags & O_CREAT) ~= 0) then
    append(FlagStrings, "O_CREAT")
  end
  if ((Flags & O_TRUNC) ~= 0) then
    append(FlagStrings, "O_TRUNC")
  end
  -- Return value
  return concat(FlagStrings, "|")
end

local function HandleTccEventOpen (Filename, Flags, Mode)
  -- local variables
  local Result
  local FileContent
  -- Handle defaults
  local FileMode
  if (Mode == nil) or (Mode == 0) then
    FileMode = INIT_DEFAULT_MODE
  else
    FileMode = Mode
  end
  -- Check if writing
  local CanWrite = (((Flags & O_WRONLY) ~= 0) or ((Flags & O_RDWR) ~= 0))
  -- Detect if the request is for TCC files (VIO4_ virtual IO layer)
  local HasRuntimePrefix = STRING_HasPrefix(Filename, COMEXE_RUNTIME_PREFIX)
  -- ZIP: readonly
  if HasRuntimePrefix and (not CanWrite) then
    -- Map the filesystem path to ZIP entry path
    -- COMEXE-RUNTIME/include/... -> comexe/include/...
    -- COMEXE-RUNTIME/lib/...     -> comexe/lib/...
    -- The filenames coming from TCC typically use / even on Windows
    local WantedFilename = STRING_RemovePrefix(Filename, COMEXE_RUNTIME_PREFIX)
    local ZipEntryName   = format("comexe/%s", WantedFilename)
    -- Try to load the file from the ZIP archive
    FileContent = INIT_ZipLoadFile(ZipEntryName)
    if FileContent then
      -- File found in ZIP, create file descriptor
      local NewFd = GetNewId()
      TccFiles[NewFd] = {
        FileType = "ZIP",     -- Mark as ZIP file (read-only)
        Filename = Filename,  -- Keep original filename with prefix
        Contents = FileContent,
        Position = 1,
        Flags    = Flags
      }
      Result = NewFd
    end
  end
  -- If not found, try filesystem
  if (Result == nil) then
    local fd = fs_open(Filename, Flags, FileMode)
    if fd then
      -- Native file descriptor
      local NewFd = GetNewId()
      TccFiles[NewFd] = {
        FileType  = "FILESYSTEM",
        Filename  = Filename,
        RealFd    = fd,
        Flags     = Flags
      }
      Result = NewFd
    else
      Result = -ENOENT -- No such file or directory
    end
  end
  -- Return value
  return Result
end

local function HandleTccEventRead (fd, SizeInBytes)
  local File = TccFiles[fd]
  local Result
  if File then
    -- ZIP
    local FileType = File.FileType
    if (FileType == "ZIP") then
      if (SizeInBytes == 0) then
        Result = ""
      else
        local FileContents   = File.Contents
        local Position       = File.Position
        local RemainingBytes = ((#FileContents - Position) + 1)
        if (RemainingBytes <= 0) then
          Result = ""
        else
          local ActualReadCount = min(SizeInBytes, RemainingBytes)
          local IndexStart      = Position
          local IndexEnd        = (IndexStart + ActualReadCount - 1)
          local ReadData        = FileContents:sub(IndexStart, IndexEnd)
          -- Update position
          File.Position = (Position + ActualReadCount)
          -- Result
          Result = ReadData
        end
      end
    -- Filesystem
    elseif (FileType == "FILESYSTEM") then
      local FsFileDescriptor   = File.RealFd
      local Data, ErrorMessage = fs_read(FsFileDescriptor, SizeInBytes, -1)
      if Data then
        Result = Data
      else
        Result = -EIO -- ERROR INPUT/OUTPUT
      end
    else
      Result = -EBADF -- Should not happen
    end
  else
    Result = -EBADF -- Bad file descriptor
  end
  -- Return value
  return Result
end

local function HandleTccEventWrite (fd, Data)
  local File = TccFiles[fd]
  local Result
  if File then
    -- ZIP
    local FileType = File.FileType
    if (FileType == "ZIP") then
      Result = -EACCES -- Permission denied: ZIP files are read-only
    elseif (FileType == "FILESYSTEM") then
      -- Filesystem
      local FsFileDescriptor           = File.RealFd
      local BytesWritten, ErrorMessage = fs_write(FsFileDescriptor, Data, -1)
      if BytesWritten then
        Result = BytesWritten
      else
        Result = -EIO -- ERROR INPUT/OUTPUT
      end
    else
      Result = -EBADF -- Should not happen
    end
  else
    Result = -EBADF -- Bad file descriptor
  end
  -- Return value
  return Result
end

local function HandleTccEventSeek (fd, offset, whence)
  local File = TccFiles[fd]
  local Result
  if File then
    local FileType = File.FileType
    -- ZIP
    if (FileType == "ZIP") then
      local OldPosition = File.Position
      local NewPosition
      if (whence == 0) then -- SEEK_SET
        NewPosition = (offset + 1)
      elseif (whence == 1) then -- SEEK_CUR
        NewPosition = (OldPosition + offset)
      elseif (whence == 2) then -- SEEK_END
        NewPosition = (#File.Contents + offset + 1)
      else
        Result = -ESPIPE -- Illegal seek (invalid whence)
      end
      if (Result ~= -ESPIPE) then
        -- Set new position to valid range [1:FileSize]
        File.Position = max(1, min(NewPosition, (#File.Contents + 1)))
        Result = (File.Position - 1)
      end
    -- Filesystem
    elseif (FileType == "FILESYSTEM") then
      local FsFileDescriptor          = File.RealFd
      local NewPosition, ErrorMessage = fs_lseek(FsFileDescriptor, offset, whence)
      if NewPosition then
        Result = NewPosition
      else
        Result = -ESPIPE -- Illegal seek (invalid whence)
      end
    else
      Result = -EBADF -- Bad file descriptor
    end
  else
    Result = -EBADF -- Bad file descriptor
  end
  -- Return value
  return Result
end

local function HandleTccEventClose (fd)
  local Result
  local File = TccFiles[fd]
  if File then
    -- Filesystem
    if (File.FileType == "FILESYSTEM") then
      local FsFileDescriptor = File.RealFd
      local Success          = fs_close(FsFileDescriptor)
      if Success then
        Result = 0
      else
        Result = -EBADF -- Bad file descriptor
      end
      -- Handle ZIP FD
    else
      Result = 0
    end
    -- Clean up
    TccFiles[fd] = nil
    ReleaseId(fd)
  else
    Result = -EBADF -- Bad file descriptor
  end
  -- Return value
  return Result
end

local function HandleTccEventDup (fd)
  local File = TccFiles[fd]
  local Result
  if File then
    -- New file
    local NewFile = {
      Contents = File.Contents, -- Share the same content (if ZIP)
      Position = File.Position, -- Copy current position
      Flags    = File.Flags,    -- Copy flags
      Filename = File.Filename, -- Copy filename for reference
      FileType = File.FileType  -- Copy file type
    }
    -- Duplicate OS file descriptor if present
    local Success  = true
    local FileType = File.FileType
    if (FileType == "FILESYSTEM") then
      local FsFileDescriptor = File.RealFd
      local DupFd            = fs_dup(FsFileDescriptor)
      if DupFd then
        NewFile.RealFd = DupFd
      else
        Success = false
      end
    end
    if Success then
      -- Duplicate the file entry
      local NewFd = GetNewId()
      TccFiles[NewFd] = NewFile
      Result = NewFd
    else
      Result = -EBADF -- Bad file descriptor
    end
  else
    Result = -EBADF -- Bad file descriptor
  end
  -- Return value
  return Result
end

--------------------------------------------------------------------------------
-- UNIFIED EVENT HANDLER                                                      --
--------------------------------------------------------------------------------

-- TCC events
local function INIT_EventHandler (EventName, ...)
  local Result
  if (EventName == "Open") then
    local Filename, Flags, Mode = ...
    Result = HandleTccEventOpen(Filename, Flags, Mode)
    print("OPEN", Filename, "FLAGS", TCC_MakeOpenFlagsString(Flags), "MODE", Mode, FormatStdioErrorResult(Result))
  elseif (EventName == "Read") then
    local fd, SizeInBytes = ...
    Result = HandleTccEventRead(fd, SizeInBytes)
    -- Print debug
    local ReadBytes
    if (type(Result) == "string") then
      ReadBytes = #Result
    else
      ReadBytes = Result
    end
    print("READ", fd, SizeInBytes, ReadBytes)
  elseif (EventName == "Write") then
    local fd, Data = ...
    Result = HandleTccEventWrite(fd, Data)
    print("WRITE", fd, #Data, Result)
  elseif (EventName == "Seek") then
    local fd, Offset, Whence = ...
    Result = HandleTccEventSeek(fd, Offset, Whence)
    print("SEEK", fd, Offset, Whence, Result)
  elseif (EventName == "Close") then
    local fd = ...
    Result = HandleTccEventClose(fd)
    print("CLOSE", fd, Result)
  elseif (EventName == "Dup") then
    local fd = ...
    Result = HandleTccEventDup(fd)
    print("DUP", fd, Result)
  else
    Result = -EIO -- I/O error for unknown event
  end
  return Result
end

--------------------------------------------------------------------------------
-- LUA-STANDALONE COMPATIBLE ARGUMENT PARSING                                 --
--------------------------------------------------------------------------------

-- Lua standalone:
--     -e stat: execute string stat;
--     -i: enter interactive mode after running script;
--     -l mod: "require" mod and assign the result to global mod;
--     -l g=mod: "require" mod and assign the result to global g;
--     -v: print version information;
--     -E: ignore environment variables;
--     -W: turn warnings on;
--     --: stop handling options;
--     -: execute stdin as a file and stop handling options.
-- 
-- (The form -l g=mod was introduced in release 5.4.4.)

local INIT_ParserEatRules = {
  ["-e"] =  2,
  ["-i"] =  1,
  ["-l"] =  2,
  ["-v"] =  1,
  ["-E"] =  1,
  ["-W"] =  1,
  ["--"] = -1,
  ["-"]  = -1,
}

-- Following LuaStandalone, when the script name is missing, the OPTIONS part
-- will be empty, and everything will be considered as ARGUMENT. At that stage
-- (lua54ce) will need to parse those arguments following the same
-- INIT_ParserEatCount rules. To avoid double-implementation, we provide that
-- function.
local function INIT_ParseOptions (Arguments, EatRules)
  -- Initialize all return values
  local Success      = true
  local ErrorOption  = nil
  local NewOptions   = {}
  local ScriptIndex  = nil
  -- Build a easy to iterate structure to avoiding parsing 2 times
  local OptionValues = {}
  -- Iterate data
  local ArgCount = #Arguments
  local Index    = 2
  local Continue = true
  -- Main iteration
  while Continue and (Index <= ArgCount) do
    local Argument = Arguments[Index]
    local EatCount = EatRules[Argument]
    if (EatCount == nil) then
      if STRING_HasPrefix(Argument, "-") then
        -- Unrecognized option that looks like an option
        Success     = false
        ErrorOption = Argument
        Continue    = false
      else
        -- Not an option, treat as script
        Continue    = false
        ScriptIndex = Index
      end
    elseif (EatCount == -1) then
      append(NewOptions, Argument)
      append(OptionValues, { Argument })
      -- When '--' or '-' , next argument is script
      if (Argument == "--") or (Argument == "-") then
        local PotentialScriptIndex = (Index + 1)
        if (PotentialScriptIndex <= ArgCount) then
          ScriptIndex = PotentialScriptIndex
        end
      end
      Continue = false
      Index    = (Index + 1)
    else
      append(NewOptions, Argument)
      local OptionIndex     = Index
      local LastValueIndex  = (Index + (EatCount - 1))
      local FirstValueIndex = (OptionIndex + 1)
      local OptionEntry     = { Argument }
      if (FirstValueIndex == LastValueIndex) then
        -- Single value
        append(OptionEntry, Arguments[FirstValueIndex])
        append(NewOptions, Arguments[FirstValueIndex])
      elseif (FirstValueIndex < LastValueIndex) then
        -- Multiple values
        for ValueIndex = FirstValueIndex, LastValueIndex do
          append(OptionEntry, Arguments[ValueIndex])
          append(NewOptions, Arguments[ValueIndex])
        end
      end
      append(OptionValues, OptionEntry)
      Index = (LastValueIndex + 1)
    end
  end
  -- Return all values in a single statement
  return Success, ErrorOption, NewOptions, ScriptIndex, OptionValues
end

local function INIT_ParseArguments (Arguments)
  -- Parse the options part
  local Success, ErrorOption, NewOptions, ScriptIndex, OptionValues = INIT_ParseOptions(Arguments, INIT_ParserEatRules)
  -- Collect arguments after script
  local ArgCount     = #Arguments
  local ExeFilename  = Arguments[1]
  local NewArguments = {}
  local Script
  if Success and ScriptIndex then
    Script       = Arguments[ScriptIndex]
    NewArguments = INIT_ArraySlice(Arguments, (ScriptIndex + 1), ArgCount)
  else
    NewOptions   = {}
    NewArguments = INIT_ArraySlice(Arguments, 2, ArgCount)
  end
  -- Return values
  return ExeFilename, NewOptions, Script, NewArguments, OptionValues
end

local ExeFilename, NewOptions, NewScript, NewArguments, NewOptionValues = INIT_ParseArguments(arg)

-- We had to ParseArguments() to determine if we have a script or not. The
-- behaviour of LuaStandalone varies: without script, LuaStandalone all the
-- options are positive index, while with a script, there are negative index for
-- OPTIONS.
--
-- > lua54-static -i -v dist\bin\print-arg.lua
-- Lua 5.4.7  Copyright (C) 1994-2024 Lua.org, PUC-Rio
-- -1      -v
-- -3      lua54-static
-- -2      -i
-- 0       dist\bin\print-arg.lua
-- > for Key, Value in pairs(arg) do print(Key, Value) end
-- -1      -v
-- -3      lua54-static
-- -2      -i
-- 0       dist\bin\print-arg.lua
-- > #arg
-- 0
--
-- > lua54-static -i -v
-- Lua 5.4.7  Copyright (C) 1994-2024 Lua.org, PUC-Rio
-- > for Key, Value in pairs(arg) do print(Key, Value) end
-- 1       -i
-- 2       -v
-- 0       lua54-static
-- > #arg
-- 2
--
-- The role of INIT_BuildLuaArguments is to bring back that negativity.
--
local function INIT_BuildLuaArguments (ExeFilename, NewOptions, Script, NewArguments)
  local LuaArguments = {}
  if Script then
    local Executable  = ExeFilename
    local Options     = NewOptions
    local Args        = NewArguments
    local OptionCount = #Options
    local ArgCount    = #Args
    local ExeIndex    = (0 - OptionCount - 1) -- most-left
    LuaArguments[ExeIndex] = Executable
    for OptionIndex = 1, OptionCount do
      local NegativeIndex = (ExeIndex + OptionIndex)
      LuaArguments[NegativeIndex] = Options[OptionIndex]
    end
    LuaArguments[0] = Script
    for ArgIndex = 1, ArgCount do
      LuaArguments[ArgIndex] = Args[ArgIndex]
    end
  else
    -- The EXE is at arg[0]
    for ArgIndex = 1, #INIT_Arg do
      local Offset = (ArgIndex - 1)
      LuaArguments[Offset] = INIT_Arg[ArgIndex]
    end
  end
  return LuaArguments
end

--------------------------------------------------------------------------------
-- CONVENIENT RESOURCE MANAGEMENT: ZIP VS FILE-SYSTEM                         --
--------------------------------------------------------------------------------

-- This useful resource management function depends on ScriptName which depends
-- on command-line parsing.
--
-- From ScriptName we determine the RootDir, from the RootDir we can load the
-- files in InterpreterMode.

local function INIT_DetermineRunMode ()
  local RunMode
  if INIT_AppEntryPoint then
    RunMode = "EMBEDDED"
  else
    RunMode = "INTERPRETER"
  end
  return RunMode
end

-- loadresource(Filename): load either from ZIP either from FILE-SYSTEM
--
-- At this stage, we already have "arg" setup by lua-application.c
-- There are 2 modes: RUN_FROM_INTERPRETER or EMBEDDED-EXE
--
-- RUN_FROM_INTERPRETER command-line example:
-- arg[-1] = lua54ce.exe
-- arg[ 0] = main
-- arg[ 1] = printer-service\main.lua
-- arg[ 2] = --console
--
-- Here we assume that the arguments are following Lua Standalone
-- specifications. We want to search for the Lua filename to determine the ROOT
-- directory. Here ROOT will be CurrentDir\printer-service\
--
-- Unfortunately, we duplicate some behaviour present in lua54ce source code.
--
-- EMBEDDED-EXE
-- We don't care about command-line, the ROOT is simply CurrentDirectory
--
-- Never provide final SEPARATOR
local function INIT_DetermineRootDirectory (RunMode, Script)
  local CurrentDirectory = UvCurrentDirectory()
  local RootDir
  -- Assume we are using "LuaStandalone" arguments
  if (RunMode == "INTERPRETER") then
    -- In some cases, script is not provided:
    -- > lua54ce.exe -e "print('Hello World')"
    -- > lua54ce.exe -i
    -- > lua54ce.exe -v
    -- > lua54ce.exe -x EXTENDED-COMMAND
    if Script then
      local ScriptPath = PATH_NewPathname(Script)
      if ScriptPath:isabsolute() then
        RootDir = ScriptPath:getdirectory("native")
      else
        local ScriptDir = ScriptPath:getdirectory("internal")
        if (ScriptDir ~= "") then
          local Directory = format("%s%s%s", CurrentDirectory, PATH_InternalSeparator, ScriptDir)
          RootDir = PATH_NativePathname(Directory)
        end
      end
    end
  end
  -- Default: ROOT is CurrentDirectory
  if (RootDir == nil) then
    RootDir = CurrentDirectory
  end
  -- Return value
  return RootDir
end

-- Global variable for simplicity, used by INIT_LoadResource
local INIT_RunMode = INIT_DetermineRunMode()
local INIT_RootDir = INIT_DetermineRootDirectory(INIT_RunMode, NewScript)

-- Methods:
-- AUTO  find resource in either ZIP or FILE-SYSTEM depending on the RunMode
-- AUTO+ same as AUTO, but fallback to the other source if not found
-- FS    only search in FILE-SYSTEM
-- ZIP   only search in ZIP archive
local function INIT_LoadResource (Filename, Method)
  -- Default: AUTO
  Method = Method or "AUTO"
  -- Variables
  local Content
  local SearchOrder
  -- Determine search order
  if (Method == "ZIP") then
    SearchOrder = { "ZIP" }
  elseif (Method == "FS") then
    SearchOrder = { "FS" }
  elseif (INIT_RunMode == "INTERPRETER") then
    if (Method == "AUTO+") then
      SearchOrder = { "FS", "ZIP" }
    elseif (Method == "AUTO") then
      SearchOrder = { "FS" }
    end
  elseif (INIT_RunMode == "EMBEDDED") then
    if (Method == "AUTO+") then
      SearchOrder = { "ZIP", "FS" }
    elseif (Method == "AUTO") then
      SearchOrder = { "ZIP" }
    end
  end
  -- Search for resource
  local MethodCount = #SearchOrder
  local Index       = 1
  while (Content == nil) and (Index <= MethodCount) do
    local Source = SearchOrder[Index]
    if (Source == "FS") then
      local Fullname = format("%s%s%s", INIT_RootDir, PATH_NativeSeparator, Filename)
      Content = INIT_ReadFile(Fullname)
    elseif (Source == "ZIP") then
      Content = INIT_ZipLoadFile(Filename)
    end
    Index = (Index + 1)
  end
  -- Return value
  return Content
end

local function INIT_GetRelativePath (RelativePath)
  local RootDirectory = INIT_RootDir
  local AbsolutePath  = format("%s%s%s", RootDirectory, PATH_InternalSeparator, RelativePath)
  local NativePath    = PATH_NativePathname(AbsolutePath)
  return NativePath
end

--------------------------------------------------------------------------------
-- LUA PACKAGE.SEARCHERS                                                      --
--------------------------------------------------------------------------------

local COMEXE_FS_PATH_Table = {
  format([[%s/lua/?%s]],                  INIT_RootDir, INIT_BinarySuffix),
  format([[%s/lua/?.lua]],                INIT_RootDir),
  format([[%s/lua/?/init%s]],             INIT_RootDir, INIT_BinarySuffix),
  format([[%s/lua/?/init.lua]],           INIT_RootDir),
  format([[%s/?%s]],                      INIT_RootDir, INIT_BinarySuffix),
  format([[%s/?.lua]],                    INIT_RootDir),
  format([[%s/?/init%s]],                 INIT_RootDir, INIT_BinarySuffix),
  format([[%s/?/init.lua]],               INIT_RootDir),
  format([[%s/share/lua/5.5/?%s]],        INIT_RootDir, INIT_BinarySuffix),
  format([[%s/share/lua/5.5/?.lua]],      INIT_RootDir), -- slightly different from Lua Standard
  format([[%s/share/lua/5.5/?/init%s]],   INIT_RootDir, INIT_BinarySuffix),
  format([[%s/share/lua/5.5/?/init.lua]], INIT_RootDir), -- slightly different from Lua Standard
}

local COMEXE_FS_PATH_Internal = concat(COMEXE_FS_PATH_Table, ";")
local COMEXE_FS_PATH_String   = PATH_NativePathname(COMEXE_FS_PATH_Internal)

-- ComEXE runtime
local COMEXE_ZIP_PATH_RUNTIME = {
  format([[comexe/usr/share/lua/5.5/?%s]],      INIT_BinarySuffix),
  [[comexe/usr/share/lua/5.5/?.lua]],
  format([[comexe/usr/share/lua/5.5/?/init%s]], INIT_BinarySuffix),
  [[comexe/usr/share/lua/5.5/?/init.lua]],
}

local COMEXE_ZIP_PATH = {
  format([[lua/?%s]],                INIT_BinarySuffix),
  [[lua/?.lua]],                -- Close to Lua defaults
  format([[lua/?/init%s]],           INIT_BinarySuffix),
  [[lua/?/init.lua]],           -- Close to Lua defaults
  format([[?%s]],                    INIT_BinarySuffix),
  [[?.lua]],                    -- Close to Lua defaults
  format([[?/init%s]],               INIT_BinarySuffix),
  [[?/init.lua]],               -- Close to Lua defaults
  format([[share/lua/5.5/?%s]],      INIT_BinarySuffix),
  [[share/lua/5.5/?.lua]],      -- Different from Lua Standard
  format([[share/lua/5.5/?/init%s]], INIT_BinarySuffix),
  [[share/lua/5.5/?/init.lua]], -- Different from Lua Standard
}

local function ZIP_SearchLuaModule (PathList, ModuleName)
  local RealModuleName = ModuleName:gsub("%.", "/")
  local Index          = 1
  local Content
  -- Iterate
  while (Content == nil) and (Index <= #PathList) do
    local Path     = PathList[Index]
    local ZipEntry = Path:gsub("%?", RealModuleName)
    Content = INIT_ZipLoadFile(ZipEntry)
    Index  = (Index + 1)
  end
  -- Return value
  return Content
end

--------------------------------------------------------------------------------
-- COMEXE SEARCHER                                                            --
--------------------------------------------------------------------------------

local function INIT_LoadChunk (FileContent, ChunkName, ErrorContext)
  -- Load the FileContent into a chunk
  local AtChunkName = format("@%s", ChunkName)
  local Chunk, ErrorMessage = load(FileContent, AtChunkName)
  if Chunk then
    return Chunk
  else
    -- Syntax error, stop immediately
    print(format("ComEXE Loader [%s] (%s) from ZIP", AtChunkName, ErrorContext))
    print(ErrorMessage)
    os.exit(1)
  end
end

local function INIT_SearcherZipRuntime (ModuleName)
  local FileContent = ZIP_SearchLuaModule(COMEXE_ZIP_PATH_RUNTIME, ModuleName)
  if FileContent then
    return INIT_LoadChunk(FileContent, ModuleName, "ZIP")
  end
  -- Return no error: continue to next searcher
end

local function INIT_SearcherZip (ModuleName)
  local FileContent = ZIP_SearchLuaModule(COMEXE_ZIP_PATH, ModuleName)
  if FileContent then
    return INIT_LoadChunk(FileContent, ModuleName, "ZIP")
  end
  -- Return no error: continue to next searcher
end

local function INIT_SearcherFileSystem (ModuleName)
  local Filename = searchpath(ModuleName, COMEXE_FS_PATH_String)
  if Filename then
    local FileContent = INIT_ReadFile(Filename)
    if FileContent then
      return INIT_LoadChunk(FileContent, ModuleName, "FS")
    end
  end
  -- Return no error: continue to next searcher
end

--------------------------------------------------------------------------------
-- SEARCHERS API                                                              --
--------------------------------------------------------------------------------

-- Save initial Lua searchers
local LUA_SEARCHER_1_PRELOAD = package.searchers[1]
local LUA_SEARCHER_2_SRC     = package.searchers[2]
local LUA_SEARCHER_3_BIN_A   = package.searchers[3]
local LUA_SEARCHER_4_BIN_B   = package.searchers[4]

local function INIT_GetSearcher (Name)
  local Searcher
  if (Name == "1") then
    Searcher = LUA_SEARCHER_1_PRELOAD
  elseif (Name == "2") then
    Searcher = LUA_SEARCHER_2_SRC
  elseif (Name == "3") then
    Searcher = LUA_SEARCHER_3_BIN_A
  elseif (Name == "4") then
    Searcher = LUA_SEARCHER_4_BIN_B
  elseif (Name == "R") then
    Searcher = INIT_SearcherZipRuntime
  elseif (Name == "Z") then
     Searcher = INIT_SearcherZip
  elseif (Name == "F") then
    Searcher = INIT_SearcherFileSystem
  end
  return Searcher
end

local function INIT_SetSearcher (ConfigurationString)
  local NewSearcher = {}
  for SearcherName in ConfigurationString:gmatch(".") do
    local SearcherFunction = INIT_GetSearcher(SearcherName)
    if SearcherFunction then
      append(NewSearcher, SearcherFunction)
    else
      error(format("Invalid searcher name: %s", SearcherName))
    end
  end
  -- Update LOCAL searchers *AND* GLOBAL configuration
  -- Following NewThread() will be impacted
  -- Existing other threads will not be impacted
  setloaderconfig(ConfigurationString)
  package.searchers = NewSearcher
end

--------------------------------------------------------------------------------
-- ENVIRONMENT                                                                --
--------------------------------------------------------------------------------

local GLOBAL_Environment = {
  ["INTERNAL-DIR-SEP"]  = PATH_InternalSeparator,
  ["NATIVE-DIR-SEP"]    = PATH_NativeSeparator,
  ["ARCH"]              = INIT_ARCH,
  ["OS"]                = INIT_OS,
  ["RUN-MODE"]          = INIT_RunMode,
  ["ROOT-DIR"]          = INIT_RootDir,
  ["ARG-RAW"]           = INIT_Arg,
  ["LUA-EXE"]           = ExeFilename,
  ["LUA-SCRIPT"]        = NewScript,
  ["LUA-OPTION-VALUES"] = NewOptionValues,
}

if NewScript then
  GLOBAL_Environment["LUA-ARG"]     = NewArguments
  GLOBAL_Environment["LUA-OPTIONS"] = NewOptions
else
  GLOBAL_Environment["LUA-ARG"]     = INIT_Arg
  GLOBAL_Environment["LUA-OPTIONS"] = {}
end

local function INIT_GetParameter (Key)
  local Result
  if STRING_HasPrefix(Key, "SEARCHER_") then
    local SearcherName = STRING_RemovePrefix(Key, "SEARCHER_")
    Result = INIT_GetSearcher(SearcherName)
  else
    Result = GLOBAL_Environment[Key]
  end
  return Result
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local function INIT_DoNothing (...)
end

-- Note that searchers are local to one Lua instance, it's hard to share between
-- instances. The current "loader-configuration" is more like a "default" value
-- for current thread and future threads.

-- Complete Runtime with Lua-implemented functions
Runtime.append          = append
Runtime.newpathname     = PATH_NewPathname
Runtime.newbuffer       = NewBuffer
Runtime.slice           = INIT_ArraySlice
Runtime.hasprefix       = STRING_HasPrefix
Runtime.removeprefix    = STRING_RemovePrefix
Runtime.readfile        = INIT_ReadFile
Runtime.writefile       = INIT_WriteFile
Runtime.setsearcher     = INIT_SetSearcher
Runtime.loadresource    = INIT_LoadResource
Runtime.getrelativepath = INIT_GetRelativePath
Runtime.parseoptions    = INIT_ParseOptions
Runtime.getparam        = INIT_GetParameter

-- Register the functions
seteventhandler(INIT_EventHandler)
setwarningfunction(INIT_DoNothing)

-- Hide seteventhandler: will not be part of PUBLIC API
Runtime.seteventhandler = nil

-- Default: take the default configuration from lua-application.c
local LoaderConfiguration = getloaderconfig()
INIT_SetSearcher(LoaderConfiguration)

-- Update the "arg" to follow "Lua Standalone" rules and "Lua Standalone" actual
-- behaviour. We keep provide INIT_GetArgs API because it's much easier to
-- process.

arg = INIT_BuildLuaArguments(ExeFilename, NewOptions, NewScript, NewArguments)

-- Start gc as it was stopped by C side while building state
collectgarbage("restart")

--------------------------------------------------------------------------------
-- RUN THREAD MAIN CODE                                                       --
--------------------------------------------------------------------------------

local Thread   = require("com.thread")
local ThreadId = Thread.getid()

-- When loading a new/thread instance, lua-application.c set the module name in
-- the variable thread.getname(). If the user thread.create("test") then
-- thread.getname() will return "test".
--
-- For the very first thread/instance, lua-application.c provide "main" as
-- Thread.getname(). Here, we could simply require(Thread.getname()). It would
-- work properly but it will restrict the name of the APPLICATION ENTRY POINT to
-- "main" (main.lua).
--
-- To allow user to name the ENTRY POINT, we added "INIT_AppEntryPoint" (it is
-- prepend to init.lua at compile time in extended-commands.lua).
--
-- We still have a special case: lua55ce, in that case, we just use the plain
-- unmodified init.lua without "INIT_AppEntryPoint", so we need to specify
-- "main" manually.
--
local ModuleToLoad
if (ThreadId == 1) then
  ModuleToLoad = (INIT_AppEntryPoint or "main")
else
  local ModuleName = Thread.getname()
  ModuleToLoad = ModuleName
end

require(ModuleToLoad)

if ZIP_File then
  unzip_close(ZIP_File)
  ZIP_File = nil
end
