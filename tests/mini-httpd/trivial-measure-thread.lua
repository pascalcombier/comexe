--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime        = require("com.runtime")
local Event          = require("com.event")
local Copas          = require("copas")
local copashttp      = require("copas.http")
local sockethttp     = require("socket.http")
local FastHttpClient = require("fast-http-client")

local runloop  = Event.runloop
local stoploop = Event.stoploop
local send     = Event.send

local format = string.format

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function RunSimpleLoop (ParentThreadId, WorkerId, FetchCount, TestUri)
  -- local data
  local SuccessCount = 0
  local FailureCount = 0
  -- Use LuaSocket http.request
  local Request = sockethttp.request
  -- Trivial loop
  for Index = 1, FetchCount do
    -- Retry loop for "address already in use"
    local Body, HttpCode, Headers, StatusLine
    local RetryCount  = 0
    local ShouldRetry = true
    while (ShouldRetry) do
      ---@diagnostic disable-next-line: unused-local
      Body, HttpCode, Headers, StatusLine = Request(TestUri)
      if (Body == nil) and (HttpCode == "address already in use") and (RetryCount < 100) then
        RetryCount = (RetryCount + 1)
        Runtime.sleepms(10)
      else
        ShouldRetry = false
      end
    end
    if (HttpCode == 200) then
      SuccessCount = (SuccessCount + 1)
    else
      local ErrorString = HttpCode
      FailureCount = (FailureCount + 1)
      local ErrorString = format("simpleloop[%6.6d] %q", Index, ErrorString)
      send(ParentThreadId, "REPORT_ERROR", WorkerId, ErrorString)
    end
  end
  -- Return value
  return SuccessCount, FailureCount
end

local function RunKeepAlive (ParentThreadId, WorkerId, FetchCount, TestUri)
  -- local data
  local SuccessCount = 0
  local FailureCount = 0
  -- Use Keep-Alive wrapper for persistent connection
  local KeepAlive = FastHttpClient.newhttpclient(30)
  for Index = 1, FetchCount do
    ---@diagnostic disable-next-line: unused-local
    local Body, HttpCode, Headers, StatusLine = KeepAlive:http(TestUri, "GET")
    if (HttpCode == 200) then
      SuccessCount = (SuccessCount + 1)
    else
      FailureCount = (FailureCount + 1)
      local ErrorString = format("keepalive[%6.6d] code=%q error=%q", Index, HttpCode, StatusLine)
      send(ParentThreadId, "REPORT_ERROR", WorkerId, ErrorString)
    end
  end
  -- FastHttpClient does not close the connection automatically
  KeepAlive:close()
  -- Return value
  return SuccessCount, FailureCount
end

local function RunCopasLoop (ParentThreadId, WorkerId, FetchCount, Concurrency, TestUri)
  -- local data
  local SuccessCount = 0
  local FailureCount = 0
  -- Use Copas wrapper of LuaSocket http.request
  local Request = copashttp.request
  -- Start the Copas loop to send multiple fetches in parallel using a worker pool
  Copas.loop(function()
    -- Wait using Copas-friendly pause
    local Index = 0
    local function Worker ()
      local Done = false
      while (not Done) do
        Index = Index + 1
        if (Index <= FetchCount) then
          -- Retry loop for "address already in use"
          local Body
          local HttpCode
          local RetryCount = 0
          local ShouldRetry = true
          while (ShouldRetry) do
            ---@diagnostic disable-next-line: unused-local
            Body, HttpCode = Request(TestUri)
            if (HttpCode == "timeout") and (RetryCount < 3) then
              RetryCount = (RetryCount + 1)
            elseif (HttpCode == "closed") and (RetryCount < 3) then
              RetryCount = (RetryCount + 1)
            elseif (HttpCode == "address already in use") and (RetryCount < 100) then
              -- Also handle address already in use in copas loop (though less likely)
              RetryCount = (RetryCount + 1)
              Copas.sleep(0.01)
            else
              ShouldRetry = false
            end
          end
          if (HttpCode == 200) then
            SuccessCount = (SuccessCount + 1)
          else
            FailureCount = (FailureCount + 1)
            local ErrorString = format("copasloop[%6.6d] code=%q", Index, HttpCode)
            send(ParentThreadId, "REPORT_ERROR", WorkerId, ErrorString)
          end
        else
          Done = true
        end
      end
    end
    -- Spawn workers
    local addthread = Copas.addthread
    for WorkerIndex = 1, Concurrency do
      addthread(Worker)
    end
  end)
  -- Return value
  return SuccessCount, FailureCount
end

--------------------------------------------------------------------------------
-- PUBLIC EVENTS                                                              --
--------------------------------------------------------------------------------

function WAIT_AND_START (ParentThreadId, WorkerId, TimeoutSeconds, FetchCount, Concurrency, TestUri, Mode)
  -- local data
  local SuccessCount = 0
  local FailureCount = 0
  -- Wait a little bit
  local TimeoutMs = (TimeoutSeconds * 1000)
  Runtime.sleepms(TimeoutMs)
  -- Handle loop
  if (Mode == "simpleloop") then
    SuccessCount, FailureCount = RunSimpleLoop(ParentThreadId, WorkerId, FetchCount, TestUri)
  elseif (Mode == "keepalive") then
    SuccessCount, FailureCount = RunKeepAlive(ParentThreadId, WorkerId, FetchCount, TestUri)
  elseif (Mode == "copasloop") then
    SuccessCount, FailureCount = RunCopasLoop(ParentThreadId, WorkerId, FetchCount, Concurrency, TestUri)
  end
  -- Send results to parent thread
  send(ParentThreadId, "WORKER_COMPLETED", WorkerId, SuccessCount, FailureCount)
end

function STOP ()
  stoploop()
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

runloop()