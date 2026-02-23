--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- main.lua only contains commands documented in the Lua manual.
-- We want to extend the commands while keeping compatibility.
-- The added commands are implemented in this file.

-- zip-l zip-c and find a probably not necessary
-- But could be useful to understand step by step if something goes wrong
--
-- For example in the case one use a third-party ZIP program, but the resulting
-- runtime ZIP file is not working well with minizip

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime     = require("com.runtime")
local Minizip     = require("lib-minizip")
local Http        = require("socket.http")
local MiniHttpLib = require("com.mini-httpd-lib")
local Url         = require("socket.url")
local Fennel      = require("fennel")

local format           = string.format
local open             = io.open
local append           = Runtime.append
local contains         = Runtime.contains
local getparam         = Runtime.getparam
local slice            = Runtime.slice
local readfile         = Runtime.readfile
local writefile        = Runtime.writefile
local LoadResource     = Runtime.loadresource
local hasprefix        = Runtime.hasprefix
local removeprefix     = Runtime.removeprefix
local hassuffix        = Runtime.hassuffix
local removesuffix     = Runtime.removesuffix
local fileexists       = Runtime.fileexists
local directoryexists  = Runtime.directoryexists
local listfiles        = Runtime.listfiles
local deletefile       = Runtime.deletefile
local newpathname      = Runtime.newpathname
local request          = Http.request
local parseheadervalue = MiniHttpLib.parseheadervalue
local parseurl         = Url.parse

local IterateRead            = Minizip.IterateRead
local NewMerger              = Minizip.NewMerger
local Z_BEST_COMPRESSION     = Minizip.Z_BEST_COMPRESSION

local COMEXE_EXE            = getparam("LUA-EXE")
local COMEXE_ZIP_INIT_ENTRY = "comexe/init.lua"

--------------------------------------------------------------------------------
-- COMMAND LONG ALIASES                                                       --
--------------------------------------------------------------------------------

local COMMAND_LONG_ALIASES = {
  h = "help",
  c = "compile",
  m = "make",
}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function CreateTempFilename (Prefix, Suffix)
  -- Format date and time
  local Date       = os.date("*t")
  local DateString = format("%04d-%02d-%02d", Date.year, Date.month, Date.day)
  local TimeString = format("%02d%02d%02d",   Date.hour, Date.min, Date.sec)
  -- Get the decimal part of os.clock()
  local ClockValue                = os.clock()
  local IntegralPart, DecimalPart = math.modf(ClockValue)
  -- os.clock provide numbers with milliseconds precision
  local DecimalString = format("%.3f", DecimalPart):sub(3) -- sub(3) removes the leading "0." in "0.123"
  -- Full string
  local FullString = format("%s%s_%s-%s%s", Prefix, DateString, TimeString, DecimalString, Suffix)
  -- Return value
  return FullString
end

local function ConcatFiles (OutputFilename, FileList)
  local OutputFile = open(OutputFilename, "wb")
  if OutputFile then
    for Index, Filename in ipairs(FileList) do
      local Content = readfile(Filename, "string")
      if Content then
        OutputFile:write(Content)
      else
        error(format("Failed to read input file: %s", Filename))
      end
    end
    OutputFile:close()
  else
    error(format("Failed to open output file: %s", OutputFilename))
  end
end

-- Returns a list of all available target names (without .exe extension)
local function GetAvailableTargets ()
  -- local data
  local Targets = {}
  -- local callback
  local function AddTarget (EntryName)
    local TargetPrefix = [[comexe/usr/bin/comexe-targets/]]
    if hasprefix(EntryName, TargetPrefix) then
      local Name1 = removeprefix(EntryName, TargetPrefix)
      local Name2
      if hassuffix(Name1, ".exe") then
        Name2 = removesuffix(Name1, ".exe")
      else
        Name2 = Name1
      end
      append(Targets, Name2)
    end
  end
  -- Start file iteration
  local Success, ErrorMessage = IterateRead(COMEXE_EXE, AddTarget)
  if (not Success) then
    error(format("ERROR listing targets: %s", ErrorMessage))
  end
  -- Return value
  return Targets
end

-- Returns the default target name
local function GetMakeDefaultTarget ()
  -- local data
  local ARCH = getparam("ARCH")
  local OS   = getparam("OS")
  local Type = "con" -- console by default, could be "gui" or "dbg"
  -- Default variant is "-con" for all platforms
  local Target = format("%s-%s-%s", ARCH, OS, Type)
  -- Return value
  return Target
end

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS: MAKE EXE                                                --
--------------------------------------------------------------------------------

local function MAKE_DoNothing (...)
  -- Don't print anything
end

local function MAKE_VerboseLog (...)
  local String = format(...)
  print(String)
end

local MAKE_Log = MAKE_DoNothing

local function EXT_CreateInitLua (ApplicationEntryPoint)
  local InitLuaContents   = LoadResource(COMEXE_ZIP_INIT_ENTRY, "ZIP")
  local FirstLineFormat   = [[local INIT_AppEntryPoint = "%s"]]
  local FirstLineContents = format(FirstLineFormat, ApplicationEntryPoint)
  local NewInitLua        = format("%s\n%s", FirstLineContents, InitLuaContents)
  return NewInitLua
end

local function EXT_AddRuntimeSource (Merger, TargetEntryName)
  -- Create a new source for runtime
  local Source = Merger:AddSource(COMEXE_EXE, "zip")
  -- Both Windows and Linux
  Merger:AddRule(Source, "^comexe/init%.lua$",                 "SKIP")
  Merger:AddRule(Source, "^comexe/usr/bin/comexe%-targets/.*", "SKIP")
  -- Windows specific
  if hassuffix(TargetEntryName, ".exe") then
    Merger:AddRule(Source, "^comexe/usr/include/x86_64%-linux%-musl/.*",      "SKIP")
    Merger:AddRule(Source, "^comexe/usr/lib/tcc%-x86%-64%-linux%-runtime/.*", "SKIP")
    Merger:AddRule(Source, "^comexe/usr/lib/x86_64%-linux%-musl/.*",          "SKIP")
  else
    Merger:AddRule(Source, "^comexe/usr/lib/tcc%-x86%-64%-windows%-runtime/.*", "SKIP")
    Merger:AddRule(Source, "^comexe/usr/share/lua/5%.5/com/win32.*",            "SKIP")
  end
  -- Both Windows and Linux
  Merger:AddRule(Source, ".*%.gitkeep$", "SKIP")
  Merger:AddRule(Source, "^comexe/.*",   "COPY")
  Merger:AddRule(Source, ".*",           "SKIP")
end

local function EXT_MakeExe (OutputFilename, TargetName, DataInputs, ApplicationEntryPoint, NeedStdlib, VerboseFlag)
  -- Validate inputs
  assert(TargetName, "make requires a target name")
  assert(DataInputs and (#DataInputs > 0), "make requires at least one data input (directory or ZIP file)")
  -- Extract target EXE file
  local TargetEntryName
  if contains(TargetName, "windows") then
    TargetEntryName = format("comexe/usr/bin/comexe-targets/%s.exe", TargetName)
  else
    TargetEntryName = format("comexe/usr/bin/comexe-targets/%s", TargetName)
  end
  -- Extract target EXECUTABLE to temporary file
  local TargetContent = LoadResource(TargetEntryName, "ZIP")
  assert(TargetContent, format("Target [%s] not found", TargetName))
  -- Write the content to a temporary file using CreateTempFilename
  local TempExeFilename = CreateTempFilename("make-exe-base-", ".exe")
  local TempZipFilename = CreateTempFilename("make-exe-data-", ".zip")
  MAKE_Log("OPENING [%s]", TempExeFilename)
  assert(writefile(TempExeFilename, TargetContent))
  MAKE_Log("OPENING [%s]", TempZipFilename)
  -- Use NewMerger to build the ZIP
  local MergerOptions
  if VerboseFlag then
    MergerOptions = "VERBOSE"
  end
  local Merger = NewMerger(TempZipFilename, Z_BEST_COMPRESSION, MergerOptions)
  -- runtime/init.lua
  local NewInitLua = EXT_CreateInitLua(ApplicationEntryPoint)
  Merger:AddEntry(COMEXE_ZIP_INIT_ENTRY, NewInitLua)
  -- Add runtime source if needed (COMEXE_EXE treated as ZIP source)
  if NeedStdlib then
    EXT_AddRuntimeSource(Merger, TargetEntryName)
  end
  -- User inputs
  for Index, Input in ipairs(DataInputs) do
    if hassuffix(Input, ".zip") and fileexists(Input) then
      local Source = Merger:AddSource(Input, "zip")
      Merger:AddRule(Source, ".*", "COPY")
    elseif directoryexists(Input) then
      local Source = Merger:AddSource(Input, "dir")
      Merger:AddRule(Source, ".*", "COPY")
    else
      print(format("WARNING: Input not found or invalid: %s", Input))
    end
  end
  -- Write ZIP
  Merger:WriteZip()
  -- Concatenate the extracted EXE and the new ZIP
  local FileList = { TempExeFilename, TempZipFilename }
  ConcatFiles(OutputFilename, FileList)
  MAKE_Log("%s created", OutputFilename)
  -- Clean up temporary files
  deletefile(TempExeFilename)
  deletefile(TempZipFilename)
  MAKE_Log("DEL %s", TempExeFilename)
  MAKE_Log("DEL %s", TempZipFilename)
end

--------------------------------------------------------------------------------
-- PRIVATE COMMANDS                                                           --
--------------------------------------------------------------------------------

local function HandleHelp ()
  print("Extended Commands:")
  print("  --help, -h                        Show this help message")
  print("  --list-targets                    List available targets for make command")
  print("  --make, -m DIR/OR/ZIP/my-prog.lua [-v] [--nostdlib] [-t target] [-o output]")
  print("  --zip-l <file.zip>                List contents of a zip file")
  print("  --zip-c <file.zip> <dir|zip> ...  Create/overwrite a zip file")
  print("  --find <directory>                Find files in a directory")
  print("  --compile, -c <file.lua|file.fnl> Compile Lua or Fennel source")
  print("  --wget <url>                      Download file via HTTP")
end

local function HandleListTargets (Filename)
  -- Local data
  local TargetPrefix = [[comexe/usr/bin/comexe-targets/]]
  -- Local callback
  local function PrintEntryName(EntryName)
    if hasprefix(EntryName, TargetPrefix) then
      -- Create a temporary pathname object for convenience
      local Pathname = newpathname(EntryName)
      -- Extract and print basename
      local Name, Basename, Ext = Pathname:getname()
      print(Basename)
    end
  end
  -- Start the file iterator
  local Success, ErrorMessage = IterateRead(Filename, PrintEntryName)
  if (not Success) then
    print("ERROR", ErrorMessage)
  end
end

local function HandleZipList (Filename)
  -- Local callback
  local function PrintEntryName (EntryName)
    print(EntryName)
  end
  -- Start the file iterator
  local Success, ErrorMessage = IterateRead(Filename, PrintEntryName)
  if (not Success) then
    print("ERROR", ErrorMessage)
  end
end

local function HandleZipCreate (OutputZip, Inputs)
  -- Validate we have at least one input
  assert(#Inputs >= 1, "zip-c requires at least one input (directory or ZIP file)")
  -- Check for verbose flag
  local VerboseFlag    = false
  local FilteredInputs = {}
  for Index, Input in ipairs(Inputs) do
    if (Input == "-v") then
      VerboseFlag = true
    else
      append(FilteredInputs, Input)
    end
  end
  -- Merge verbose options
  local MergerOptions
  if VerboseFlag then
    print(format("Creating ZIP: %s", OutputZip))
    MergerOptions = "VERBOSE"
    MAKE_Log      = MAKE_VerboseLog
  end
  -- Create Merger
  local Merger = NewMerger(OutputZip, Z_BEST_COMPRESSION, MergerOptions)
  -- Process inputs
  for Index, Input in ipairs(FilteredInputs) do
    if fileexists(Input) and hassuffix(Input, ".zip") then
      local Source = Merger:AddSource(Input, "zip")
      Merger:AddRule(Source, ".*", "COPY")
      MAKE_Log("Processing ZIP file: %s", Input)
    elseif directoryexists(Input) then
      local Source = Merger:AddSource(Input, "dir")
      Merger:AddRule(Source, ".*", "COPY")
      MAKE_Log("Processing directory: %s", Input)
    else
      print(format("WARNING: Input not found or invalid: %s", Input))
    end
  end
  -- Write the ZIP file
  Merger:WriteZip()
  MAKE_Log("ZIP written %s", OutputZip)
end

local function HandleFind (Directory)
  -- Local function
  local function PrintFunction (Filename, Filetype)
    if (Filetype == "file") then
      print(Filename)
    end
  end
  -- Start the file iterator
  listfiles(Directory, PrintFunction)
end

local function ExtractMakeFlags (Arguments)
  -- Parse flags and source argument
  local Verbose    = false
  local NeedStdlib = true
  local SourceList = {}
  local TargetSpec
  local OutputFile
  -- Parse arguments
  local Index = 1
  while (Index <= #Arguments) do
    local Arg = Arguments[Index]
    if (Arg == "-v") then
      Verbose = true
    elseif (Arg == "--nostdlib") then
      NeedStdlib = false
    elseif (Arg == "-t") then
      Index = (Index + 1)
      if (Index <= #Arguments) then
        TargetSpec = Arguments[Index]
      else
        error("Flag -t requires a target name")
      end
    elseif (Arg == "-o") then
      Index = (Index + 1)
      if (Index <= #Arguments) then
        OutputFile = Arguments[Index]
      else
        error("Flag -o requires an output filename")
      end
    else
      -- This should be the source file/directory argument
      append(SourceList, Arg)
    end
    Index = (Index + 1)
  end
  -- Validate source argument is present
  if (#SourceList == 0) then
    error("make requires a source file or directory argument")
  end
  -- Return the parsed flags as multiple values
  return Verbose, TargetSpec, OutputFile, SourceList, NeedStdlib
end

local function MAKE_FilterSources (SourceList)
  -- local data
  local NewSourceList = {}
  local FoundLuaFile  = false
  local FirstLuaModuleName
  local FirstDirectoryName
  ---@diagnostic disable-next-line: unused-local
  for Index, Source in ipairs(SourceList) do
    if fileexists(Source) then
      if hassuffix(Source, ".lua") then
        assert((not FoundLuaFile), format("Multiple Lua files specified"))
        FoundLuaFile = true
        -- Extract module name
        local Path                = newpathname(Source)
        local Name, Basename, Ext = Path:getname()
        FirstLuaModuleName = Basename
        -- Use Lua file parent directory as source
        Path:parent()
        local ParentDirectory = Path:convert("native")
        append(NewSourceList, ParentDirectory)
      elseif hassuffix(Source, ".zip") then
        append(NewSourceList, Source)
      else
        error(format("Unsupported input file: %s (expected .lua, .zip or directory)", Source))
      end
    elseif directoryexists(Source) then
      append(NewSourceList, Source)
      if (FirstDirectoryName == nil) then
        local Path                = newpathname(Source)
        local Name, Basename, Ext = Path:getname()
        FirstDirectoryName = Basename
      end
    else
      error(format("Input not found: %s", Source))
    end
  end
  -- Return value
  return NewSourceList, FirstLuaModuleName, FirstDirectoryName
end

local function MAKE_DetermineOutputFilename (UserOutputFile, UserMainModule, FirstDirectoryName, TargetName, SuffixFlag)
  -- Add platform-specific extension
  local TargetWindows = contains(TargetName, "windows")
  local Filename
  if UserOutputFile then
    Filename = removesuffix(UserOutputFile, ".exe")
  elseif UserMainModule then
    Filename = UserMainModule
  elseif FirstDirectoryName then
    Filename = FirstDirectoryName
  else
    error("Cannot determine output filename")
  end
  if SuffixFlag then
    Filename = format("%s-%s", Filename, TargetName)
  end
  if TargetWindows then
    Filename = format("%s.exe", Filename)
  end
  -- Return value
  return Filename
end

local function HandleMake (Arguments)
  -- Extract flags
  local Verbose, Target, UserOutputFile, SourceList, NeedStdlib = ExtractMakeFlags(Arguments)
  if Verbose then
    MAKE_Log = MAKE_VerboseLog
  end
  -- Process inputs
  local NewSourceList, FirstLuaModuleName, FirstDirectoryName = MAKE_FilterSources(SourceList)
  -- Determine which targets to build
  local TargetList
  local AppendSuffix
  if (Target == nil) then
    TargetList   = { GetMakeDefaultTarget() }
    AppendSuffix = false
  elseif (Target == "all") then
    TargetList   = GetAvailableTargets()
    AppendSuffix = true
  else
    TargetList   = { Target }
    AppendSuffix = false
  end
  -- Determine the entry point
  local ApplicationEntryPoint
  if FirstLuaModuleName then
    ApplicationEntryPoint = FirstLuaModuleName
  else
    ApplicationEntryPoint = "main"
  end
  -- Build for each target
  local SuccessCount = 0
  for Index, TargetName in ipairs(TargetList) do
    local OutputFilename = MAKE_DetermineOutputFilename(UserOutputFile, FirstLuaModuleName, FirstDirectoryName, TargetName, AppendSuffix)
    MAKE_Log("Building target '%s' -> %s", TargetName, OutputFilename)
    EXT_MakeExe(OutputFilename, TargetName, NewSourceList, ApplicationEntryPoint, NeedStdlib, Verbose)
    SuccessCount = (SuccessCount + 1)
    MAKE_Log("Successfully built: %s", OutputFilename)
  end
  -- Summary
  MAKE_Log("Build %d/%d success", SuccessCount, #TargetList)
end

local function HandleCompileLua (LuaFilename)
  -- Validate input
  assert(fileexists(LuaFilename), format("Input file not found: %s", LuaFilename))
  -- Compute output filename
  local ARCH           = getparam("ARCH")
  local OS             = getparam("OS")
  local NewSuffix      = format("-%s-%s.bin", ARCH, OS)
  local Basename       = removesuffix(LuaFilename, ".lua")
  local OutputFilename = format("%s%s", Basename, NewSuffix)
  -- Read source and compile to binary
  local ChunkName = format("@%s", LuaFilename)
  local Source    = readfile(LuaFilename, "string")
  assert(Source, format("cannot open %s: No such file or directory", LuaFilename))
  local Chunk, ErrorString = load(Source, ChunkName)
  assert(Chunk, ErrorString)
  local Binary = string.dump(Chunk, true)
  -- Write binary chunk
  writefile(OutputFilename, Binary)
  print(format("%s -> %s", LuaFilename, OutputFilename))
end

local function HandleCompileFennel (FennelFilename)
  -- Validate input
  assert(fileexists(FennelFilename), format("Input file not found: %s", FennelFilename))
  local FennelCode = readfile(FennelFilename, "string")
  -- Compile Lua
  local Options   = {}
  local LuaString = Fennel.compileString(FennelCode, Options)
  -- Write output
  local Basename    = removesuffix(FennelFilename, ".fnl")
  local LuaFilename = format("%s.lua", Basename)
  -- Write binary chunk
  writefile(LuaFilename, LuaString)
  print(format("%s -> %s", FennelFilename, LuaFilename))
end

local function HandleCompile (Filename)
  assert(Filename, "compile requires an input .lua or .fnl file")
  if hassuffix(Filename, ".lua") then
    HandleCompileLua(Filename)
  elseif hassuffix(Filename, ".fnl") then
    HandleCompileFennel(Filename)
  else
    error(format("Unsupported file extension: %s (expected .lua or .fnl)", Filename))
  end
end

local function GetFilenameFromUri (Uri)
  -- Use luasocket.url to parse the URI
  local ParsedUri = parseurl(Uri)
  local Result
  if ParsedUri then
    local Path     = (ParsedUri.path or "")
    local Filename = Path:match("([^/]+)$")
    if Filename then
      Result = Filename
    end
  end
  if (not Result) then
    Result = "index.html"
  end
  return Result
end

-- Take a lot of precautions because the file is coming from the internet
local function SanitizeFilename (Filename)
  -- Replace invalid characters with underscore
  Filename = Filename:gsub('[\\\\/:%*%?"<>|]', "_")
  -- Truncate filename
  local MaximumLength = 255
  if (#Filename > MaximumLength) then
    Filename = Filename:sub(1, MaximumLength)
  end
  -- If all the characters were invalid, give a default name
  if (Filename:gsub("_", "") == "") then
    Filename = "file.bin"
  end
  -- Return value
  return Filename
end

local function HandleWget (Uri)
  -- Make HTTP GET request
  local Body, StatusCode, Headers, StatusLine = request(Uri)
  -- Check status
  if Body and (StatusCode >= 200) and (StatusCode < 300) then
    local ContentDisposition = Headers["content-disposition"]
    local Filename
    local Parameters
    if ContentDisposition then
      Value, Parameters = parseheadervalue(ContentDisposition)
    end
    if Parameters then
      Filename = Parameters["filename"]
    end
    if (not Filename) then
      Filename = GetFilenameFromUri(Uri)
    end
    -- Write file
    Filename = SanitizeFilename(Filename)
    writefile(Filename, Body)
  else
    print(format("Error: %s", StatusLine))
  end
end

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function EXT_Command (RawArguments)
  local Option    = RawArguments[1]
  local Arguments = slice(RawArguments, 2, #RawArguments)
  local Command
  if (not Option) then
    Command = "help"
  else
    if hasprefix(Option, "--") then
      Command = removeprefix(Option, "--")
    elseif hasprefix(Option, "-") then
      local ShortCommand = removeprefix(Option, "-")
      -- Resolve short aliases
      local LongCommand = COMMAND_LONG_ALIASES[ShortCommand]
      if LongCommand then
        Command = LongCommand
      else
        Command = ShortCommand
      end
    else
      error(format("Extended commands must be prefixed with '-' or '--' (got %s)", Option))
    end
  end
  if (Command == nil) or (Command == "help") then
    HandleHelp()
  elseif (Command == "list-targets") then
    HandleListTargets(COMEXE_EXE)
  elseif (Command == "make") then
    HandleMake(Arguments)
  elseif (Command == "zip-l") then
    local Filename = Arguments[1]
    HandleZipList(Filename)
  elseif (Command == "zip-c") then
    local OutputZip = Arguments[1]
    local Inputs    = slice(Arguments, 2, #Arguments)
    HandleZipCreate(OutputZip, Inputs)
  elseif (Command == "find") then
    local Directory = (Arguments[1] or ".")
    HandleFind(Directory)
  elseif (Command == "compile") then
    local InputLua = Arguments[1]
    HandleCompile(InputLua)
  elseif (Command == "wget") then
    local Uri = Arguments[1]
    HandleWget(Uri)
  else
    error(format("Command could not be found: '%s'", Command))
  end
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  Command = EXT_Command
}

return PUBLIC_API
