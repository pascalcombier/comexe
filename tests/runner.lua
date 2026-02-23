--------------------------------------------------------------------------------
-- INFO                                                                       --
--------------------------------------------------------------------------------

-- Test cases are just Lua files with the name prefixed by "test-"
-- Test cases will be run with lua55ce
-- The process return code 0 means success
--
-- Those test below are tests against regressions
--
-- os.execute and io.open does not work with UTF-8
-- So we use com.runtime
-- 

--------------------------------------------------------------------------------
-- TESTS BOILERPLATE FOR PACKAGE.PATH                                         --
--------------------------------------------------------------------------------

-- This kind of code should not appear in the real use of ComEXE
--
-- Initialize package.path to include ..\lib\xxx because test libraries are in
-- this directory

local function TEST_UpdatePackagePath (RelativeDirectory)
  -- Retrieve package confiuration (file loadlib.c, function luaopen_package)
  local Configuration = package.config
  local LUA_DIRSEP    = Configuration:sub(1, 1)
  local LUA_PATH_SEP  = Configuration:sub(3, 3)
  local LUA_PATH_MARK = Configuration:sub(5, 5)
  -- Load required modules
  local Runtime   = require("com.runtime")
  local Directory = Runtime.getrelativepath(RelativeDirectory) -- relative to arg[0] directory
  -- Prepend path in a Linux/Windows compatible way
  package.path = string.format("%s%s%s.lua%s%s", Directory, LUA_DIRSEP, LUA_PATH_MARK, LUA_PATH_SEP, package.path)
end

TEST_UpdatePackagePath("lib")

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")
local Timer   = require("trivial-timer")
local uv      = require("luv")

local format           = string.format
local append           = Runtime.append
local getparam         = Runtime.getparam
local contains         = Runtime.contains
local hasprefix        = Runtime.hasprefix
local splitcommandline = Runtime.splitcommandline
local listfiles        = Runtime.listfiles
local newpathname      = Runtime.newpathname

local OS     = getparam("OS")
local LuaExe = getparam("LUA-EXE")

--------------------------------------------------------------------------------
-- REWORKED FROM RUNTIME_ExecuteCommand                                       --
--------------------------------------------------------------------------------

local new_pipe   = uv.new_pipe
local read_start = uv.read_start
local run        = uv.run
local spawn      = uv.spawn

-- Evolved from runtime\comexe\usr\share\lua\5.5\com\runtime.lua
-- Differences:
-- output to stdout/stderr instead of collecting the output into table
-- No stdin support
local function ExecuteCommandVariant (Executable, CommandLine, UserOptions)
  -- Split EXE and PARAMS for livuv.spawn
  local Arguments, ErrorString = splitcommandline(CommandLine)
  assert(Arguments, ErrorString)
  -- Local data
  local stdout = new_pipe()
  local stderr = new_pipe()
  local ExitCode
  local ExitReason
  local StandardInputOutput = {  nil, stdout, stderr }
  local Options = {
    args     = Arguments,
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
    if DataChunk then
      io.stdout:write(DataChunk)
      io.stdout:flush()
    end
  end
  local function ReadStderrCallback (Error, DataChunk)
    if DataChunk then
      io.stderr:write(DataChunk)
      io.stderr:flush()
    end
  end
  -- Enqueue request to spawn process
  local Handle, PID = spawn(Executable, Options, OnProcessExit)
  read_start(stdout, ReadStdoutCallback)
  read_start(stderr, ReadStderrCallback)
  -- Run event loop
  run()
  -- Return values
  return ExitCode, ExitReason
end

--------------------------------------------------------------------------------
-- TEST RUNNER                                                                --
--------------------------------------------------------------------------------

local function ProcessTest (Filename)
  local Path     = newpathname(Filename)
  local DirName  = Path:getdirectory()
  local TestName = Path:getname()
  local Command  = format([[%s]], TestName)
  local Options  = { cwd = DirName }
  local ExitCode, ExitReason = ExecuteCommandVariant(LuaExe, Command, Options)
  -- Return value
  return (ExitCode == 0), Command
end

local function ShouldSkipTest (Pathname)
  local Skip
  if (OS == "linux") then
    Skip = contains(Pathname, "win32")
  else
    Skip = false
  end
  return Skip
end

local function FindAndExecuteTestFiles ()
  -- local data
  local TestResults = {}
  local TestTimer   = Timer.NewTimer()
  -- Find callback
  local function FindAndExecute (FullPath, Filetype)
    if (Filetype == "file") then
      local Path = newpathname(FullPath)
      local Name, Basename, Extension = Path:getname()
      -- Check if file is a test
      if hasprefix(Name, "test-") and (Extension == "lua")
        and (not ShouldSkipTest(FullPath))
      then
        print("PROCESS", FullPath)
        TestTimer:Start()
        local Success, Command = ProcessTest(FullPath)
        TestTimer:Stop()
        local ElapsedTime = TestTimer:GetElapsedSeconds()
        TestTimer:Reset()
        -- Result
        local NewTestResult = {
          Passed      = Success,
          Line        = FullPath,
          Command     = Command,
          ElapsedTime = ElapsedTime,
        }
        append(TestResults, NewTestResult)
        if Success then
          print("PASSED", FullPath)
        else
          print("FAILED", FullPath)
        end
      end
    end
  end
  -- Start the find command
  local TestDirectory = getparam("ROOT-DIR")
  listfiles(TestDirectory, FindAndExecute)
  -- Return result
  return TestResults
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local Results        = FindAndExecuteTestFiles()
local Success        = 0
local Count          = 0
local ElapsedTimeSec = 0

print("== NON-REGRESSION SUMMARY ==")
for Index, Result in ipairs(Results) do
  ElapsedTimeSec = (ElapsedTimeSec + Result.ElapsedTime)
  if Result.Passed then
    print(format("PASSED %8.4fs %s", Result.ElapsedTime, Result.Line))
    Success = (Success + 1)
  else
    print(format("FAILED %8.4fs %s", Result.ElapsedTime, Result.Command))
  end
  Count = (Count + 1)
end

print(format("%d/%d PASS (%8.4f seconds)", Success, Count, ElapsedTimeSec))
