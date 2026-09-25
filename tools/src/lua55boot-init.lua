--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- NOTE
--
-- This file is a subset of init.lua made for lua55boot-init
-- + some functions from runtime.lua

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local uv = require("luv")

local format             = string.format
local append             = table.insert
local remove             = table.remove
local concat             = table.concat
local min                = math.min
local max                = math.max
local searchpath         = package.searchpath
local UvCurrentDirectory = uv.cwd
local fs_open            = uv.fs_open
local fs_fstat           = uv.fs_fstat
local fs_read            = uv.fs_read
local fs_write           = uv.fs_write
local fs_lseek           = uv.fs_lseek
local fs_close           = uv.fs_close
local fs_dup             = uv.fs_dup

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
  local ErrorString
  -- libuv is always binary mode
  local fd = fs_open(Filename, "r", 0)
  if fd then
    local StatInfo, ErrorStringStat = fs_fstat(fd)
    if StatInfo then
      local SizeInBytes = StatInfo.size
      local Offset      = 0
      FileContents, ErrorString = fs_read(fd, SizeInBytes, Offset)
    else
      ErrorString = ErrorStringStat
    end
    fs_close(fd)
  else
    ErrorString = format("Failed to open file for reading: %s", Filename)
  end
  -- Convenient but slow post processing
  local Result
  if (OutputType == nil) or (OutputType == "string") then
    Result = FileContents
  elseif FileContents and (OutputType == "lines") then
    local Lines = {}
    for Line in FileContents:gmatch("([^\r\n]*)\r?\n?") do
      append(Lines, Line)
    end
    Result = Lines
  end
  -- Return value
  return Result, ErrorString
end

-- Unlike os.open, INIT_WriteFile supports UTF-8 named files on Windows
local function INIT_WriteFile (Filename, Data)
  -- local data
  local Success
  local ErrorString
  -- libuv is always binary mode. create if not exists, overwrite contents if exists
  local fd = fs_open(Filename, "w", INIT_DEFAULT_MODE)
  if fd then
    local Offset = 0
    Success, ErrorString = fs_write(fd, Data, Offset)
    fs_close(fd)
  else
    ErrorString = format("Failed to open file for writing: %s", Filename)
    Success     = false
  end
  -- Return value
  return Success, ErrorString
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

-- Note: cross-platform UNC support (e.g. //server/share)
-- This might be an issue on Linux, "//home/user/file" will not reolve to
-- "/home/user/file" but to "//home/user/file"
--
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
  elseif STRING_HasPrefix(InternalPath, "//") then
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

--------------------------------------------------------------------------------
-- PATH HELPERS                                                                --
--------------------------------------------------------------------------------

local function PATH_AppendSpecialElements (Parts, Element)
  if (Element[1] == "ROOT") then
    -- Tricky: by adding "", concat will see { "", "dir" } and will insert a "/"
    -- between "" and "dir", making it "/dir" (and not "//dir" if we used { "/",
    -- "dir" })
    append(Parts, "")
  elseif (Element[1] == "UNC") then
    -- UNC: //Server/Share
    append(Parts, "") -- Same trick as above for ROOT: add a /
    append(Parts, "") -- Same trick as above for ROOT: add a /
    append(Parts, Element[2])
    append(Parts, Element[3])
  else
    local DriveLetter = Element[2]
    append(Parts, format("%s:", DriveLetter))
  end
end

local function PATH_BuildStringFromElements (Elements, StartIndex, EndIndex, Separator)
  -- local data
  local Parts        = {}
  local FirstElement = Elements[1]
  -- Handle ROOT
  local ActualStartIndex
  if (StartIndex == 1) and PATH_IsSpecial(FirstElement) then
    PATH_AppendSpecialElements(Parts, FirstElement)
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
  -- Build result
  local Result
  if (EndIndex == 0) then
    Result = "."
  else
    local Separator
    if (Mode == "native") then
      Separator = PATH_NativeSeparator
    else
      Separator = PATH_InternalSeparator
    end
    Result = PATH_BuildStringFromElements(Elements, StartIndex, EndIndex, Separator)
  end
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

local function PATH_MethodRemoveElement (Pathname, StartIndex, EndIndex)
  -- Remove one or multiple elements
  local LastIndex = (EndIndex or StartIndex)
  local Index     = StartIndex
  while (Index <= LastIndex) do
    remove(Pathname, StartIndex)
    Index = (Index + 1)
  end
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

local function PATH_MethodToNative (Pathname)
  local Result = PATH_MethodConvert(Pathname, "native")
  return Result
end

local function PATH_MethodToInternal (Pathname)
  local Result = PATH_MethodConvert(Pathname, "internal")
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
  -- METATABLE_LuaDefinedMethods
  __tostring = PATH_MethodToNative,
  __concat   = PATH_MethodConcat,
  -- METATABLE_UserDefinedMethods
  __index = {
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
    tonative     = PATH_MethodToNative,
    tointernal   = PATH_MethodToInternal
  }
}
PATH_Metatable = PATH_MetatableImpl

-- Simple constructor: create pathname from string
-- Don't support multiple strings/pathnames
local function PATH_NewPathnameObject (Pathname)
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

-- Versatile constructor: can create pathname from string
-- Or from list of strings/pathname that would be appened together
-- Note that it does not care about multiple ROOT
local function PATH_NewPathname (...)
  -- local data
  local Count = select("#", ...)
  local Parts = {}
  -- Iterate over arguments
  for Index = 1, Count do
    local Argument = select(Index, ...)
    local Type     = type(Argument)
    if (Type == "string") then
      append(Parts, Argument)
    elseif (Type == "table") then
      local Metatable = getmetatable(Argument)
      if (Metatable == PATH_Metatable) then
        -- Append all elements from the existing pathname
        for ElementIndex = 1, #Argument do
          local Element = Argument[ElementIndex]
          if PATH_IsSpecial(Element) then
            PATH_AppendSpecialElements(Parts, Element)
          else
            append(Parts, Element)
          end
        end
      end
    end
  end
  -- Join parts
  local FullPath = concat(Parts, PATH_InternalSeparator)
  -- Create pathname object
  local Result = PATH_NewPathnameObject(FullPath)
  -- Return value
  return Result
end

--------------------------------------------------------------------------------
-- ADAPTER                                                                    --
--------------------------------------------------------------------------------

local GLOBAL_Environment = {
  ["INTERNAL-DIR-SEP"]  = PATH_InternalSeparator,
  ["NATIVE-DIR-SEP"]    = PATH_NativeSeparator,
  ["ARCH"]              = INIT_ARCH,
  ["OS"]                = INIT_OS,
}

local function INIT_GetParameter (Key)
  local Result = GLOBAL_Environment[Key]
  return Result
end

--------------------------------------------------------------------------------
-- RUNTIME                                                                    --
--------------------------------------------------------------------------------

-- Usual POSIX dir mode 0755 is good portable default
local RUNTIME_DIR_DEFAULT_MODE = tonumber("755", 8)

-- behavior like mkdir -p
local function RUNTIME_MakeDirectory (Directory)
  -- Use pathnames
  local Current    = PATH_NewPathnameObject(Directory)
  local PathStack  = {}
  local Success    = true
  local Collecting = true
  local ErrorString
  -- Collect non-existing directories in a stack
  while Collecting do
    local NativePath = tostring(Current)
    local StatResult = uv.fs_stat(NativePath)
    if StatResult then
      -- Fails if by lack of luck we have a file with the same name
      Collecting = false
      Success    = (StatResult.type == "directory")
    else
      -- Try to create this directory later
      append(PathStack, Current:clone())
      -- Move to parent
      Current = Current:parent()
      -- Calculate depth
      local Depth = Current:depth()
      -- Check if ROOT we can't move upwards anymore
      Collecting = (Depth > 0)
    end
  end
  -- Create missing directories step by step
  while Success and (#PathStack > 0) do
    local PathToCreate = remove(PathStack)
    local NativePath   = tostring(PathToCreate)
    -- Create directory
    local MkdirSuccess, MkdirErrorString = uv.fs_mkdir(NativePath, RUNTIME_DIR_DEFAULT_MODE)
    if MkdirSuccess then
      Success = true
    else
      local FsStatSuccess = uv.fs_stat(NativePath)
      -- Maybe the directory created in the meantime
      if (FsStatSuccess and (FsStatSuccess.type == "directory")) then
        Success = true
      else
        Success     = false
        ErrorString = MkdirErrorString
      end
    end
  end
  -- Return value
  return Success, ErrorString
end

local function RUNTIME_DirectoryExists (Directory)
  local StatResult, ErrorMessage = fs_stat(Directory)
  local Exists = (StatResult and StatResult.type == "directory")
  return Exists
end

local function RUNTIME_FileExists (Filename)
  local StatResult, ErrorMessage = uv.fs_stat(Filename)
  local Exists = (StatResult and StatResult.type == "file")
  return Exists
end

local function RUNTIME_DeleteFile (Filename)
  local Success, ErrorMessage = uv.fs_unlink(Filename)
  return Success, ErrorMessage
end

local PUBLIC_API = {
  -- main functions
  getparam        = INIT_GetParameter,
  newpathname     = PATH_NewPathname,
  -- Files and directories
  makedirectory   = RUNTIME_MakeDirectory,
  directoryexists = RUNTIME_DirectoryExists,
  fileexists      = RUNTIME_FileExists,
  deletefile      = RUNTIME_DeleteFile,
  readfile        = INIT_ReadFile,
  writefile       = INIT_WriteFile,
  -- Helpers the ComEXE runtime also injects
  append          = append,
  slice           = INIT_ArraySlice,
  hasprefix       = STRING_HasPrefix,
  removeprefix    = STRING_RemovePrefix,
}

-- Install as com.runtime
package.preload["com.runtime"] = function () return PUBLIC_API end

return PUBLIC_API
