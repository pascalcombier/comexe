--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")
local uv      = require("luv")

local format = string.format
local insert = table.insert
local remove = table.remove
local concat = table.concat

local hasprefix = Runtime.hasprefix
local contains  = Runtime.contains

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local DEFAULT_PORT = 12345

--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS                                                            --
--------------------------------------------------------------------------------

local function LuvSpawn (CommandLine, StdoutStartPattern)
  -- Parse command line
  local Arguments  = Runtime.splitcommandline(CommandLine)
  local Executable = remove(Arguments, 1)
  -- local data
  local stdout      = uv.new_pipe()
  local ServerReady = false
  local ExitCode
  local ProcessHandle
  local ProcessPid
  -- Spawn callback
  local function SpawnCallback (Code)
    ExitCode = Code
    if (not uv.is_closing(stdout)) then
      uv.close(stdout)
    end
    -- Close handle when process exits to avoid resource leaks
    if ProcessHandle and (not uv.is_closing(ProcessHandle)) then
      uv.close(ProcessHandle)
    end
  end
  -- Spawn options
  local SpawnOptions = {
    args  = Arguments,
    stdio = { nil, stdout, 2 }, -- Capture stdout, inherit stderr
    cwd   = Runtime.getparam("ROOT-DIR"),
  }
  -- Initiate spawn
  ProcessHandle, ProcessPid = uv.spawn(Executable, SpawnOptions, SpawnCallback)
  if (not ProcessHandle) then
    uv.close(stdout)
    return nil, ProcessPid
  end
  -- Start reading from the pipe
  uv.read_start(stdout, function (Error, Data)
    if Data then
      -- Write on the stdout
      io.write(Data)
      io.flush()
      -- Detect server start
      if (not ServerReady) then
        ServerReady = (Data:find(StdoutStartPattern) ~= nil)
      end
    else
      if (not uv.is_closing(stdout)) then
        uv.close(stdout)
      end
    end
  end)
  -- Wait for the stdout pattern
  while (not ServerReady) and (ExitCode == nil) do
    uv.run("once")
  end
  -- Allow the child process to run independently
  uv.unref(ProcessHandle)
  uv.unref(stdout)
  -- Process methods
  local function ProcessMethodClose (Process)
    -- Wait for process exit if still running
    local Handle = Process.handle
    if (ExitCode == nil) then
      uv.ref(Handle)
      while (ExitCode == nil) do
        uv.run("once")
      end
    end
    if (not uv.is_closing(Handle)) then
      uv.close(Handle)
    end
  end
  -- Create a new interface for the spawned process
  local NewProcessObject = {
    -- data
    handle = ProcessHandle,
    -- methods
    close = ProcessMethodClose,
  }
  -- return object
  return NewProcessObject
end

local function LuvExecute (CommandLine)
  -- local data
  local Arguments  = Runtime.splitcommandline(CommandLine)
  local Executable = remove(Arguments, 1)
  local stdout     = uv.new_pipe()
  local stderr     = uv.new_pipe()
  local chunks     = {}
  -- Spawn options
  local SpawnOptions = {
    args     = Arguments,
    stdio    = { nil, stdout, stderr },
    cwd      = Runtime.getparam("ROOT-DIR"),
    detached = false,
  }
  -- Spawn callbacks
  local ExitCode
  local ProcessHandle
  local ProcessId
  local function SpawnCallback (code)
    ExitCode = code
    if ProcessHandle and (not uv.is_closing(ProcessHandle)) then
      uv.close(ProcessHandle)
    end
  end
  local function ReadStdout (Error, Data)
    if Data then
      insert(chunks, Data)
    else
      uv.close(stdout)
    end
  end
  local function ReadStderr (Error, Data)
    if Data then
      insert(chunks, Data)
    else
      uv.close(stderr)
    end
  end
  -- Initiate
  ProcessHandle, ProcessId = uv.spawn(Executable, SpawnOptions, SpawnCallback)
  if (not ProcessHandle) then
    return nil, ProcessId
  end
  uv.read_start(stdout, ReadStdout)
  uv.read_start(stderr, ReadStderr)
  uv.run()
  -- Format result
  local StringOutput = concat(chunks)
  -- Return result
  return StringOutput, ExitCode
end

--------------------------------------------------------------------------------
-- MAIN TEST                                                                  --
--------------------------------------------------------------------------------

-- The full path of the current executable is used to spawn other processes
local lua55ce = uv.exepath()

local IsLua55ce = contains(lua55ce, "lua55ce")
assert(IsLua55ce, "The current executable must be lua55ce.exe or lua55ced.exe")

local function RunTests (ServerScript, ClientScript, Option)
  local UseSsl   = (Option == "ssl")
  local SslFlag  = UseSsl and " -S" or ""
  local Mode     = UseSsl and "SSL" or "PLAIN TCP"
  local TestName = format("%s server | %s client | %s", ServerScript, ClientScript, Mode)

  print("==============================")
  print(format("Test: %s", TestName))
  print("==============================")

  -- Start the server using LuvSpawn (long-running processes)
  local ServerCommand = format([["%s" %s -p %d%s]], lua55ce, ServerScript, DEFAULT_PORT, SslFlag)
  print(format("Starting server: %s", ServerCommand))

  -- Spawn and wait for "Server created on port 12345 (plain TCP)"
  local ServerHandle = LuvSpawn(ServerCommand, "Server created")
  assert(ServerHandle, "Failed to start server process")

  -- We spawn 9 clients and 1 more test for server exit code "CloseExitCode"
  local TEST_CLIENT_COUNT = 9
  local TEST_TotalCount   = (TEST_CLIENT_COUNT + 1)
  local TEST_SuccessCount = 0

  for Index = 1, TEST_CLIENT_COUNT do
    -- Create client command
    local Message       = format("TEST_%d", Index)
    local ClientCommand = format([["%s" %s -p %d%s %s]], lua55ce, ClientScript, DEFAULT_PORT, SslFlag, Message)
    print(format("CLIENT: %s", ClientCommand))
    -- Execute client and capture output
    local Response, ExitCode = LuvExecute(ClientCommand)
    assert(Response, format("Failed to create client process for message '%s'", Message))
    -- Read the response from the client
    if Response then
      Response = Response:match("([^\r\n]*)")
    end
    print(format("%s", Response))
    -- Check if response starts with "UNKNOWN"
    if Response and hasprefix(Response, "UNKNOWN") then
      TEST_SuccessCount = (TEST_SuccessCount + 1)
    end
    assert((ExitCode == 0), format("Client exited with error code %d for message '%s'", ExitCode, Message))
  end

  local CloseCommand = format([["%s" %s -p %d%s CLOSE-SERVER]], lua55ce, ClientScript, DEFAULT_PORT, SslFlag)
  print(CloseCommand)

  local CloseResponse, CloseCode = LuvExecute(CloseCommand)
  assert(CloseResponse, "Failed to create close client process")
  if CloseResponse then
    CloseResponse = CloseResponse:match("([^\r\n]*)")
  end
  print(CloseResponse)
  local CloseExitCode = (CloseCode == 0)

  if CloseExitCode then
    TEST_SuccessCount = TEST_SuccessCount + 1
  end

  if ServerHandle then
    ServerHandle:close()
  end

  print(format("Summary: %d/%d success", TEST_SuccessCount, TEST_TotalCount))

  return TEST_SuccessCount, TEST_TotalCount
end

--------------------------------------------------------------------------------
-- MAIN SCRIPT                                                                --
--------------------------------------------------------------------------------

local Scenarios = {
  { "luasocket-tcp-server.lua", "luasocket-tcp-client.lua", "plain" },
  { "luasocket-tcp-server.lua", "luasocket-tcp-client.lua", "ssl"   },
  { "luv-tcp-server.lua",       "luv-tcp-client.lua",       "plain" },
  { "luv-tcp-server.lua",       "luv-tcp-client.lua",       "ssl"   },
  { "luasocket-tcp-server.lua", "luv-tcp-client.lua",       "plain" },
  { "luv-tcp-server.lua",       "luasocket-tcp-client.lua", "plain" },
  { "luasocket-tcp-server.lua", "luv-tcp-client.lua",       "ssl"   },
  { "luv-tcp-server.lua",       "luasocket-tcp-client.lua", "ssl"   },
}

local PassedCount    = 0
local TotalTestCount = 0

for Index, Test in ipairs(Scenarios) do
  local Passed, Total = RunTests(Test[1], Test[2], Test[3])
  -- Update counters
  PassedCount    = (PassedCount    + Passed)
  TotalTestCount = (TotalTestCount + Total)
end

print(format("%d/%d tests PASSED", PassedCount, TotalTestCount))

if (PassedCount == TotalTestCount) then
  os.exit(0)
else
  os.exit(1)
end
