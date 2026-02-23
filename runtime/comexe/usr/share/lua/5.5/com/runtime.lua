--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Those functions are used internally by ComEXE project. It provide useful 
-- functions.

--------------------------------------------------------------------------------
-- MODULE IMPORTS                                                             --
--------------------------------------------------------------------------------

local RawRuntime = require("com.raw.runtime")
local uv         = require("luv")

local format          = string.format
local append          = table.insert
local remove          = table.remove
local concat          = table.concat
local new_pipe        = uv.new_pipe
local read_start      = uv.read_start
local run             = uv.run
local write           = uv.write
local shutdown        = uv.shutdown
local spawn           = uv.spawn
local fs_stat         = uv.fs_stat
local fs_scandir      = uv.fs_scandir
local fs_scandir_next = uv.fs_scandir_next
local fs_unlink       = uv.fs_unlink
local fs_mkdir        = uv.fs_mkdir
local fs_rmdir        = uv.fs_rmdir
local getparam        = RawRuntime.getparam
local newpathname     = RawRuntime.newpathname
local NATIVE_DIR_SEP  = getparam("NATIVE-DIR-SEP")

--------------------------------------------------------------------------------
-- STRINGS                                                                    --
--------------------------------------------------------------------------------

local function STRING_Contains (String, Substring)
  return (String:find(Substring, 1, true) ~= nil)
end

local function STRING_HasSuffix (String, Suffix)
  local SuffixLen = #Suffix
  local Result
  local StartPos = (#String - SuffixLen + 1)
  if (StartPos < 1) then
    Result = false
  else
    Result = (String:find(Suffix, StartPos, true) == StartPos)
  end
  return Result
end

local function STRING_RemoveSuffix (String, Suffix)
  local Result
  if (Suffix == "") then
    Result = String -- No suffix to remove
  else
    Result = String:sub(1, -#Suffix - 1) -- Remove the suffix
  end
  return Result
end

local function STRING_Trim (String, Option)
  -- Handle defaults
  local UsedOption = (Option or "both")
  local Result
  -- Trim according to Option
  if (UsedOption == "both") then
    Result = String:match("^%s*(.-)%s*$")
  elseif (UsedOption == "left") then
    Result = String:match("^%s*(.*)$")
  elseif (UsedOption == "right") then
    Result = String:match("^(.-)%s*$")
  end
  return Result
end

--------------------------------------------------------------------------------
-- FILES                                                                      --
--------------------------------------------------------------------------------

-- Usual POSIX dir mode 0755 (decimal 493) gives rwx for owner and rx for
-- group/others and is a good portable default
local RUNTIME_DIR_DEFAULT_MODE = tonumber("755", 8)

-- Note that fs_mkdir is not recursive: not equivalent to mkdir -p
local function RUNTIME_MakeDirectorySimple (Directory)
  -- Call the API
  local MkdirSuccess, MkdirErrorString = fs_mkdir(Directory, RUNTIME_DIR_DEFAULT_MODE)
  local Success
  local ErrorMessage
  if MkdirSuccess then
    Success = true
  else
    -- Avoid race condition: fs_mkdir failed because another program created
    -- the same directory
    local FsStatSuccess = fs_stat(Directory)
    if (FsStatSuccess and (FsStatSuccess.type == "directory")) then
      Success = true
    else
      Success      = false
      ErrorMessage = MkdirErrorString
    end
  end
  -- Return value
  return Success, ErrorMessage
end

-- mkdir -p
local function RUNTIME_MakeDirectoryRec (Directory)
  -- Use pathnames
  local Current    = newpathname(Directory)
  local PathStack  = {}
  local Success    = true
  local Collecting = true
  -- Collect non-existing directories in a stack
  while Collecting do
    local NativePath = Current:convert("native")
    local StatResult = fs_stat(NativePath)
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
    local NativePath   = PathToCreate:convert("native")
    Success = RUNTIME_MakeDirectorySimple(NativePath)
  end
  -- Return value
  return Success
end

-- Note that fs_mkdir is not recursive: not equivalent to mkdir -p
local function RUNTIME_MakeDirectory (Directory, Mode)
  local Success
  if (Mode == "recursive") then
    Success = RUNTIME_MakeDirectoryRec(Directory)
  else
    Success = RUNTIME_MakeDirectorySimple(Directory)
  end
  return Success
end

local function RUNTIME_DirectoryExists (Directory)
  local StatResult, ErrorMessage = fs_stat(Directory)
  local Exists = (StatResult and StatResult.type == "directory")
  return Exists
end

local function RUNTIME_FileExists (Filename)
  local StatResult, ErrorMessage = fs_stat(Filename)
  local Exists = (StatResult and StatResult.type == "file")
  return Exists
end

local function RUNTIME_DeleteFile (Filename)
  local Success, ErrorMessage = fs_unlink(Filename)
  return Success, ErrorMessage
end

local function RUNTIME_DeleteDirectory (Directory)
  local Success, ErrorMessage = fs_rmdir(Directory)
  return Success, ErrorMessage
end

-- Will call the Callback on all the found files
-- Callback(Path, FileType)
-- The Path will be relative to the requested Directory
local function RUNTIME_ListFiles (Directory, Callback)
  -- Call file system
  local StatResult, ErrorMessage = fs_stat(Directory)
  -- Error handling
  assert(StatResult, format("ERROR: Cannot access directory '%s': %q", Directory, ErrorMessage))
  assert(StatResult.type == "directory", format("ERROR: '%s' is not a directory", Directory))
  -- Local recursive function
  local function FindRecursive (CurrentDir)
    local Request, ErrorMessage2 = fs_scandir(CurrentDir)
    assert(Request, format("ERROR: Cannot scan directory '%s': %s", CurrentDir, ErrorMessage2))
    -- Iterate
    local Filename, Filetype = fs_scandir_next(Request)
    while Filename do
      local FullPath = format([[%s%s%s]], CurrentDir, NATIVE_DIR_SEP, Filename)
      Callback(FullPath, Filetype)
      if (Filetype == "directory") then
        FindRecursive(FullPath)
      end
      Filename, Filetype = fs_scandir_next(Request)
    end
  end
  -- Start the recursive search
  FindRecursive(Directory)
end

--------------------------------------------------------------------------------
-- LUV-BASED ExecuteCommand                                                   --
--------------------------------------------------------------------------------

-- Define which characters can be escaped
local RUNTIME_EscapableCharacters = {
  [" "] =  true,
  ["'"]  = true,
  ['"']  = true,
  ["\\"] = true,
}

-- split a command-line string into args, handling quotes and backslashes
-- Done for uv.spawn which need to split EXE and arguments
-- So that [["My Program.exe arg1  arg2 etc"]] can be use as:
-- "My Program.exe", { "arg1", "arg2", "etc" }
local function RUNTIME_SplitCommandLine (CommandLine)
  -- Local data
  local Arguments     = {}
  local Buffer        = {}
  local Length        = #CommandLine
  local InSingle      = false
  local InDouble      = false
  local EscapePending = false
  -- Iterate over all the characters
  for Index = 1, Length do
    local Character = CommandLine:sub(Index, Index)
    local IsOutside = ((not InSingle) and (not InDouble))
    -- Handle escaping like [\ ] [\"] [\'] [\\] and store the character verbatim
    -- \t or \n etc are not special here
    -- Example: [my\ program.exe] will give [my program.exe]
    if EscapePending then
      if RUNTIME_EscapableCharacters[Character] then
        append(Buffer, Character)
      else
        append(Buffer, [[\]])
        append(Buffer, Character)
      end
      EscapePending = false
    -- Only escape when we are not in single quote (ie: escape without quotes or inside double)
    elseif (Character == [[\]]) and (not InSingle) then
      EscapePending = true
    -- Toggle double-quote state
    elseif (Character == [["]]) and (not InSingle) then
      InDouble = (not InDouble)
    -- Toggle single-quote state
    elseif (Character == [[']]) and (not InDouble) then
      InSingle = (not InSingle)
    -- Whitespace will commit the current argument
    elseif Character:match("%s") and IsOutside then
      if (#Buffer > 0) then
        local NewArgument = concat(Buffer)
        append(Arguments, NewArgument)
        Buffer = {}
      end
    -- Default: append the character to the current buffer
    else
      append(Buffer, Character)
    end
  end
  -- Add pending last argument if exists
  if (#Buffer > 0) then
    local LastArgument = concat(Buffer)
    append(Arguments, LastArgument)
  end
  -- Error reporting
  local Result
  local ErrorMessage
  if InSingle then
    ErrorMessage = "unmatched single quote"
  elseif InDouble then
    ErrorMessage = "unmatched double quote"
  elseif EscapePending then
    ErrorMessage = "unfinished escape sequence"
  else
    Result = Arguments
  end
  -- Return values
  return Result, ErrorMessage
end

local function RUNTIME_ExecuteCommand (CommandLine, StdinString, OutputType, UserOptions)
  -- Split EXE and PARAMS for livuv.spawn
  local Args, ErrorString = RUNTIME_SplitCommandLine(CommandLine)
  local Executable        = remove(Args, 1)
  -- Local data
  local StdoutChunks = {}
  local StderrChunks = {}
  local stdout       = new_pipe()
  local stderr       = new_pipe()
  local stdin
  local ExitCode
  local ExitReason
  -- Only provide stdin if we have a string
  if StdinString then
    stdin = new_pipe()
  end
  local StandardInputOutput
  if StdinString then
    StandardInputOutput = { stdin, stdout, stderr }
  else
    StandardInputOutput = {   nil, stdout, stderr }
  end
  local Options = {
    args     = Args,
    verbatim = false,
    stdio    = StandardInputOutput,
    detached = false,
  }
  if UserOptions then
    for Key, Value in pairs(UserOptions) do
      Options[Key] = Value
    end
  end
  -- local callbacks
  local function OnProcessExit (Code, Signal)
    ExitCode   = Code
    ExitReason = Signal
  end
  local function ReadStdoutCallback (Error, DataChunk)
    assert(not Error, Error)
    if DataChunk then
      append(StdoutChunks, DataChunk)
    end
  end
  local function ReadStderrCallback (Error, DataChunk)
    assert(not Error, Error)
    if DataChunk then
      append(StderrChunks, DataChunk)
    end
  end
  -- Enqueue request to spawn process
  local Handle, PID = spawn(Executable, Options, OnProcessExit)
  read_start(stdout, ReadStdoutCallback)
  read_start(stderr, ReadStderrCallback)
  -- Enqueue write stdin
  if StdinString then
    write(stdin, StdinString)
    shutdown(stdin)
  end
  -- Run event loop
  run()
  -- local data
  local ResultStdout
  local ResultStderr
  if (OutputType == nil) or (OutputType == "string") then
    ResultStdout = concat(StdoutChunks)
    ResultStderr = concat(StderrChunks)
  elseif (OutputType == "lines") then
    -- Unefficient transform into lines
    local StdoutString = concat(StdoutChunks)
    local ErrorString  = concat(StderrChunks)
    local StdoutLines  = {}
    local StderrLines  = {}
    for Line in StdoutString:gmatch("[^\r\n]+") do
      append(StdoutLines, Line)
    end
    for Line in ErrorString:gmatch("[^\r\n]+") do
      append(StderrLines, Line)
    end
    ResultStdout = StdoutLines
    ResultStderr = StderrLines
  end
  -- Return values
  return ExitCode, ExitReason, ResultStdout, ResultStderr
end

--------------------------------------------------------------------------------
-- ID PROVIDER                                                                --
--------------------------------------------------------------------------------

local function RUNTIME_NewIdProvider ()
  -- Local data
  local NextId  = 1
  local FreeIds = {}
  -- Methods
  local function GetNewId (Provider)
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
  local function ReleaseId (Provider, Id)
    append(FreeIds, Id)
  end
  -- New object
  local NewProvider = {
    new     = GetNewId,
    release = ReleaseId
  }
  -- Return value
  return NewProvider
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  -- Strings
  contains     = STRING_Contains,
  hassuffix    = STRING_HasSuffix,
  removesuffix = STRING_RemoveSuffix,
  stringtrim   = STRING_Trim,
  -- Files & directories
  makedirectory   = RUNTIME_MakeDirectory,
  directoryexists = RUNTIME_DirectoryExists,
  fileexists      = RUNTIME_FileExists,
  listfiles       = RUNTIME_ListFiles,
  deletefile      = RUNTIME_DeleteFile,
  deletedirectory = RUNTIME_DeleteDirectory,
  -- Miscellaneous
  splitcommandline = RUNTIME_SplitCommandLine,
  executecommand   = RUNTIME_ExecuteCommand,
  newidprovider    = RUNTIME_NewIdProvider,
  sleepms          = uv.sleep,
}

-- Inherits everything from RawRuntime
for Key, Value in pairs(RawRuntime) do
  assert((PUBLIC_API[Key] == nil), format("Key '%s' already exists in PUBLIC_API", Key))
  PUBLIC_API[Key] = Value
end

return PUBLIC_API