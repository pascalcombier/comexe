--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime      = require("com.runtime")
local MiniHttpd    = require("com.mini-httpd")
local HelloHttpd   = require("hello-httpd")
local Thread       = require("com.thread")
local Event        = require("com.event")
local TrivialTimer = require("trivial-timer")

local format   = string.format
local NewTimer = TrivialTimer.NewTimer

--------------------------------------------------------------------------------
-- RESOURCES                                                                  --
--------------------------------------------------------------------------------

local CertKeyFile = Runtime.getrelativepath("127.0.0.1+1-certkey.pem")
local Cert        = Runtime.loadresource("127.0.0.1+1.pem")
local Key         = Runtime.loadresource("127.0.0.1+1-key.pem")

assert(Cert,        "Missing CERT file")
assert(Key,         "Missing  KEY file")
assert(CertKeyFile, "Missing file")

--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- This is a micro-benchmark to compare performances of HTTP and HTTPS within
-- mini-http, and also check performance regressions between versions. It
-- represent the max req/secs (hellow-world) of mini-http on a SINGLE
-- THREAD. The spawned threads are just to simulate "heavy" workload.
--
-- With plain HTTP, we are able to output something close to 4000 request/sec.
--
-- HTTPS performance of HTTPS is terrible. We could potentially serve something
-- like 50% the performances of plain HTTP. Plain HTTP gives something like 4000
-- request/sec, so we should have something close to 2000 request/sec with
-- HTTPS. But we only have 50 request/sec, which means that our implementation
-- serve HTTPS 100 times slower than plain HTTP.
-- 
-- The mbedtls multithreading does not help much due to a kind of global locking
-- in the API (MBEDTLS_THREADING_ALT), implemented in main.c.
--
-- This is mitigated with HTTP keep connection alive implementation.
--
-- In general, the recommended way to use that mini-httpd would be behind a
-- proxy like nginx, Caddy or HAProxy.
--
-- But if this project got some traction, it will eventually lead to a port of a
-- C lightweight server that would be compiled with the embeded libtcc or maybe
-- a good use of luv. If this ever happen, mini-httpd will eventually be
-- dropped.

--------------------------------------------------------------------------------
-- PERFORMANCE TEST STATE                                                     --
--------------------------------------------------------------------------------

local Timer = NewTimer()

local GLOBAL_MainHttpServer
local GLOBAL_App
local GLOBAL_PerformanceConfig
local GLOBAL_TestUri

local GLOBAL_CurrentActiveWorkers
local GLOBAL_SuccessCount
local GLOBAL_ErrorCount
local GLOBAL_ThreadIds
local GLOBAL_ResultsReceived

--------------------------------------------------------------------------------
-- ERROR REPORTING                                                            --
--------------------------------------------------------------------------------

-- Multithreaded print statements bring some display issues. Here we simply
-- centralized the print statements in a single thread.

function REPORT_ERROR (WorkerId, ErrorMessage)
  print(format("  ERROR Worker=%02d: %s", WorkerId, ErrorMessage))
end

--------------------------------------------------------------------------------
-- WORKER_COMPLETED                                                           --
--------------------------------------------------------------------------------

function WORKER_COMPLETED (WorkerId, SuccessCount, FailureCount)
  -- For simpliciy we just use global variable
  local PerformanceConfig = GLOBAL_PerformanceConfig
  local ThreadCount       = PerformanceConfig.ThreadCount
  -- Update counters
  GLOBAL_SuccessCount    = (GLOBAL_SuccessCount + SuccessCount)
  GLOBAL_ErrorCount      = (GLOBAL_ErrorCount + FailureCount)
  GLOBAL_ResultsReceived = (GLOBAL_ResultsReceived + 1)
  -- Report results
  if (GLOBAL_ResultsReceived == ThreadCount) then
    local ElapsedTimeSeconds   = (Timer:GetElapsedSeconds() - PerformanceConfig.InitDelaySeconds)
    local TotalRequests        = (GLOBAL_SuccessCount + GLOBAL_ErrorCount)
    local RequestsPerSecondInt = (TotalRequests // ElapsedTimeSeconds)
    local ResultString         = format("%5d/%5d", GLOBAL_SuccessCount, TotalRequests)
    -- Print results
    print(format("%-10s Thread=%02d Concu=%02d Resu=%s Dur=%05.2fs Req/s=%06d %s",
                 PerformanceConfig.mode,
                 PerformanceConfig.ThreadCount,
                 PerformanceConfig.InThreadConcurrency,
                 ResultString,
                 ElapsedTimeSeconds,
                 RequestsPerSecondInt,
                 GLOBAL_TestUri))
    -- Stop the server
    GLOBAL_MainHttpServer:stop(GLOBAL_App)
    -- Send STOP event to all worker threads
    for Index = 1, ThreadCount do
      local WorkerThreadId = GLOBAL_ThreadIds[Index]
      Event.send(WorkerThreadId, "STOP")
    end
  end
end

--------------------------------------------------------------------------------
-- THREAD EXIT EVENT                                                          --
--------------------------------------------------------------------------------

function THREAD_WorkerExited (ThreadId)
  GLOBAL_CurrentActiveWorkers = (GLOBAL_CurrentActiveWorkers - 1)
  -- Release the thread ID
  Thread.join(ThreadId)
end

--------------------------------------------------------------------------------
-- RunPerformances: Spawn N worker threads and run the performance test
--------------------------------------------------------------------------------

local function RunPerformancesTest (Config, SslConfig)
  -- Retrieve data
  local ThreadCount         = Config.ThreadCount
  local ThisThreadId        = Thread.getid()
  local RequestsPerThread   = (Config.Requests // ThreadCount)
  local RequestsFirstThread = RequestsPerThread + (Config.Requests % ThreadCount)
  -- Init global variables
  GLOBAL_CurrentActiveWorkers = ThreadCount
  GLOBAL_SuccessCount         = 0
  GLOBAL_ErrorCount           = 0
  GLOBAL_ResultsReceived      = 0
  GLOBAL_ThreadIds            = {}
  -- Full URI used by worker threads to request test variables
  local TestGetVariablesUri
  if (SslConfig.cert or SslConfig.certkeyfile) then
    TestGetVariablesUri = format("https://%s:%d/test-get-variables?var1=123&var2=hello&var3=world", SslConfig.host,
      SslConfig.port)
  else
    TestGetVariablesUri = format("http://%s:%d/test-get-variables?var1=123&var2=hello&var3=world", SslConfig.host,
      SslConfig.port)
  end
  GLOBAL_TestUri = TestGetVariablesUri
  -- Spawn threads
  for WorkerId = 1, ThreadCount do
    local WorkerThread = Thread.create("trivial-measure-thread", "THREAD_WorkerExited")
    GLOBAL_ThreadIds[WorkerId] = WorkerThread
    -- Evaluate request counts
    local RequestCount
    if (WorkerId == 1) then
      RequestCount = RequestsFirstThread
    else
      RequestCount = RequestsPerThread
    end
    Event.send(WorkerThread, "WAIT_AND_START",
      ThisThreadId,
      WorkerId,
      Config.InitDelaySeconds,
      RequestCount,
      Config.InThreadConcurrency,
      TestGetVariablesUri,
      Config.mode)
  end
end
--------------------------------------------------------------------------------
-- TEST                                                                       --
--------------------------------------------------------------------------------

local function TEST_Configuration (SslConfiguration, TestConfiguration)
  -- Use global variables for simplicity
  GLOBAL_PerformanceConfig = TestConfiguration
  -- Create a new server
  GLOBAL_MainHttpServer = MiniHttpd.newserver()
  GLOBAL_App            = HelloHttpd.newserverapp(GLOBAL_MainHttpServer, "WAIT")
  GLOBAL_MainHttpServer:bind(SslConfiguration, GLOBAL_App)
  -- Bind and listen
  local Success, ErrorMessage = GLOBAL_MainHttpServer:listen(GLOBAL_App)
  assert(Success, format("test-plain failed: %s", ErrorMessage))
  -- Run the test (will send WAIT_AND_START)
  RunPerformancesTest(TestConfiguration, SslConfiguration)
  -- Start the blocking server loop
  Timer:Reset()
  GLOBAL_MainHttpServer:runloop()
  -- Wait for all workers to exit
  while (GLOBAL_CurrentActiveWorkers > 0) do
    Event.runonce()
  end
end

--------------------------------------------------------------------------------
-- TESTS                                                                      --
--------------------------------------------------------------------------------

-- mode:
-- "simpleloop"
-- "copasloop"
-- "keepalive"

local ConfigurationPlain = {
  host = "127.0.0.1",
  port = 8801,
}

local ConfigurationSslFile = {
  host        = "127.0.0.1",
  port        = 8802,
  certkeyfile = CertKeyFile,
}

local ConfigurationSslMemory = {
  host = "127.0.0.1",
  port = 8803,
  cert = Cert,
  key  = Key,
}

local INIT_DELAY = 2
local REQUEST_COUNT

local function TEST_ConfigurationSsl (Ssl, LoopMode, ThreadCount, RequestCount, Concurrency)
  local Config
  if (Ssl == "plain") then
    Config = ConfigurationPlain
  elseif (Ssl == "file") then
    Config = ConfigurationSslFile
  elseif (Ssl == "mem") then
    Config = ConfigurationSslMemory
  else
    error(format("Invalid Ssl: %s (must be 'plain', 'file' or 'mem')", Ssl))
  end
  TEST_Configuration(Config, {
    mode                = LoopMode,
    ThreadCount         = ThreadCount,
    Requests            = RequestCount,
    InThreadConcurrency = Concurrency,
    InitDelaySeconds    = INIT_DELAY,
  })
end

function TEST_PLAIN ()
  TEST_ConfigurationSsl("plain", "simpleloop", 1, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("plain", "simpleloop", 2, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("plain", "simpleloop", 3, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("plain", "simpleloop", 4, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("plain", "simpleloop", 5, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("plain", "simpleloop", 6, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("plain", "simpleloop", 7, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("plain", "simpleloop", 8, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("plain", "copasloop",  1, REQUEST_COUNT, 1)
  TEST_ConfigurationSsl("plain", "copasloop",  1, REQUEST_COUNT, 2)
  TEST_ConfigurationSsl("plain", "copasloop",  1, REQUEST_COUNT, 3)
  TEST_ConfigurationSsl("plain", "copasloop",  1, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("plain", "copasloop",  1, REQUEST_COUNT, 5)
  TEST_ConfigurationSsl("plain", "copasloop",  1, REQUEST_COUNT, 6)
  TEST_ConfigurationSsl("plain", "copasloop",  1, REQUEST_COUNT, 7)
  TEST_ConfigurationSsl("plain", "copasloop",  1, REQUEST_COUNT, 8)
  TEST_ConfigurationSsl("plain", "copasloop",  2, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("plain", "copasloop",  3, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("plain", "copasloop",  4, REQUEST_COUNT, 4)
end

function TEST_Ssl1Close ()
  TEST_ConfigurationSsl("file", "simpleloop", 1, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "simpleloop", 2, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "simpleloop", 3, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "simpleloop", 4, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "simpleloop", 5, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "simpleloop", 6, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "simpleloop", 7, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "simpleloop", 8, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "copasloop",  1, REQUEST_COUNT, 1)
  TEST_ConfigurationSsl("file", "copasloop",  1, REQUEST_COUNT, 2)
  TEST_ConfigurationSsl("file", "copasloop",  1, REQUEST_COUNT, 3)
  TEST_ConfigurationSsl("file", "copasloop",  1, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("file", "copasloop",  1, REQUEST_COUNT, 5)
  TEST_ConfigurationSsl("file", "copasloop",  1, REQUEST_COUNT, 6)
  TEST_ConfigurationSsl("file", "copasloop",  1, REQUEST_COUNT, 7)
  TEST_ConfigurationSsl("file", "copasloop",  1, REQUEST_COUNT, 8)
  TEST_ConfigurationSsl("file", "copasloop",  2, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("file", "copasloop",  3, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("file", "copasloop",  4, REQUEST_COUNT, 4)
end

function TEST_Ssl2Close ()
  TEST_ConfigurationSsl("mem", "simpleloop", 1, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "simpleloop", 2, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "simpleloop", 3, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "simpleloop", 4, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "simpleloop", 5, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "simpleloop", 6, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "simpleloop", 7, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "simpleloop", 8, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "copasloop",  1, REQUEST_COUNT, 1)
  TEST_ConfigurationSsl("mem", "copasloop",  1, REQUEST_COUNT, 2)
  TEST_ConfigurationSsl("mem", "copasloop",  1, REQUEST_COUNT, 3)
  TEST_ConfigurationSsl("mem", "copasloop",  1, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("mem", "copasloop",  1, REQUEST_COUNT, 5)
  TEST_ConfigurationSsl("mem", "copasloop",  1, REQUEST_COUNT, 6)
  TEST_ConfigurationSsl("mem", "copasloop",  1, REQUEST_COUNT, 7)
  TEST_ConfigurationSsl("mem", "copasloop",  1, REQUEST_COUNT, 8)
  TEST_ConfigurationSsl("mem", "copasloop",  2, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("mem", "copasloop",  3, REQUEST_COUNT, 4)
  TEST_ConfigurationSsl("mem", "copasloop",  4, REQUEST_COUNT, 4)
end

function TEST_Ssl1Keep ()
  TEST_ConfigurationSsl("file", "keepalive", 1, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "keepalive", 2, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "keepalive", 3, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "keepalive", 4, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "keepalive", 5, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "keepalive", 6, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "keepalive", 7, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("file", "keepalive", 8, REQUEST_COUNT, 0)
end

function TEST_Ssl2Keep ()
  TEST_ConfigurationSsl("mem", "keepalive", 1, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "keepalive", 2, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "keepalive", 3, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "keepalive", 4, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "keepalive", 5, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "keepalive", 6, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "keepalive", 7, REQUEST_COUNT, 0)
  TEST_ConfigurationSsl("mem", "keepalive", 8, REQUEST_COUNT, 0)
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

print("============= PLAIN ========================")
REQUEST_COUNT = 1000
TEST_PLAIN()
print("============= SSL 1 CLOSE ========================")
REQUEST_COUNT = 200
TEST_Ssl1Close()
print("============= SSL 2 CLOSE ========================")
REQUEST_COUNT = 200
TEST_Ssl2Close()
print("============= SSL 1 KEEP ========================")
REQUEST_COUNT = 10000
TEST_Ssl1Keep()
print("============= SSL 2 KEEP ========================")
REQUEST_COUNT = 10000
TEST_Ssl2Keep()

print("Performance test finished")
