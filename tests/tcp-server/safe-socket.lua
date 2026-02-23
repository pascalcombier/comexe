--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- Safer socket in the sense that there is a recovery mecanism to avoid issues
-- with SOCKET_REUSEADDR when binding the server socket.
--
-- Same for socket connection refused
--
-- The purpose is to improve the test reliability on Windows and Linux.
-- So that lua55ce tests/runner.lua does not fail in the middle

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime   = require("com.runtime")
local LuaSocket = require("socket")
local luv       = require("luv")

local format  = string.format
local sleepms = Runtime.sleepms

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local INITIAL_SLEEP_TIME_MS = 5000
local DEFAULT_MAX_ATTEMPTS  = 6

--------------------------------------------------------------------------------
-- SAFE CALL: CALL WITH RETRY MECANISM (FOR BIND SOCKET_REUSEADDR HANDLING)   --
--------------------------------------------------------------------------------

local function SocketSafeCall (Name, Callback, ...)
  -- local data
  local FailureCount    = 0
  local MaxFailureCount = DEFAULT_MAX_ATTEMPTS
  local SleepTimeMs     = INITIAL_SLEEP_TIME_MS
  local Result
  local LastErrorString
  -- Main loop
  while (Result == nil) and (FailureCount < MaxFailureCount) do
    local CallSuccess, CallResult, CallErrorString = Callback(...)
    if CallSuccess then
      Result = CallResult
    else
      FailureCount    = (FailureCount + 1)
      LastErrorString = CallErrorString
      if (FailureCount < MaxFailureCount) then
        local SleepTimeSeconds = (SleepTimeMs // 1000)
        print(format("Failed to %s (Attempt %d/%d): %s. Retrying in %d seconds...", Name, FailureCount, MaxFailureCount, CallErrorString, SleepTimeSeconds))
        sleepms(SleepTimeMs)
        SleepTimeMs = (SleepTimeMs * 2)
      end
    end
  end
  -- Evaluate success
  local Success = (Result ~= nil)
  -- Return value
  return Success, Result, FailureCount, LastErrorString
end

--------------------------------------------------------------------------------
-- LUA SOCKET                                                                 --
--------------------------------------------------------------------------------

local function LUASOCKET_TryBind (Host, Port)
  -- local data
  local Result
  local ErrorString
  -- Create socket
  local NewSocket, TcpErrorString = LuaSocket.tcp()
  if NewSocket then
    NewSocket:setoption("reuseaddr", false)
    local PcallSuccess, BindResult, BindErrorMessage = pcall(NewSocket.bind, NewSocket, Host, Port)
    if PcallSuccess and (BindResult == 1) then
      Result = NewSocket
    else
      ErrorString = (BindErrorMessage or "Bind failed")
      NewSocket:close()
    end
  else
    ErrorString = TcpErrorString
  end
  -- Evaluate success
  local Success = (Result ~= nil)
  -- Return value
  return Success, Result, ErrorString
end

local function LUASOCKET_TryBindAndListen (Host, Port, Backlog)
  -- local data
  local Success, Socket, Error = LUASOCKET_TryBind(Host, Port)
  local Result
  local ErrorString
  -- Evaluate
  if Success then
    -- Listen
    local ListenResult, ListenErrorMessage = Socket:listen(Backlog)
    if (ListenResult == 1) then
      Result = Socket
    else
      ErrorString = (ListenErrorMessage or "Listen failed")
      Socket:close()
    end
  else
    ErrorString = Error
  end
  -- Evaluate success
  local Success = (Result ~= nil)
  -- Return value
  return Success, Result, ErrorString
end

local function LUASOCKET_TryConnect (Host, Port)
  -- local data
  local Result
  local ErrorString
  -- Create socket
  local NewSocket, TcpErrorString = LuaSocket.tcp()
  if NewSocket then
    local PcallSuccess, ConnectResult, ConnectErrorMessage = pcall(NewSocket.connect, NewSocket, Host, Port)
    if PcallSuccess and (ConnectResult == 1) then
      Result = NewSocket
    else
      ErrorString = (ConnectErrorMessage or "Connect failed")
      NewSocket:close()
    end
  else
    ErrorString = TcpErrorString
  end
  -- Evaluate success
  local Success = (Result ~= nil)
  -- Return value
  return Success, Result, ErrorString
end

--------------------------------------------------------------------------------
-- LUV SOCKET                                                                 --
--------------------------------------------------------------------------------

local function LUV_DoConnect (Tcp, Host, Port)
  -- local data
  local ConnectDone  = false
  local ConnectError
  -- local callback
  local function ConnectCallback (Error)
    ConnectDone  = true
    ConnectError = Error
  end
  -- Run loop until connection attempt is done
  local Success, ErrorMessage = Tcp:connect(Host, Port, ConnectCallback)
  if Success then
    while (not ConnectDone) do
      luv.run("once")
    end
  else
    ConnectError = (ErrorMessage or "Connect start failed")
  end
  return ConnectError
end

local function LUV_TryBindAndListen (Host, Port, Backlog, OnListen)
  -- local data
  local Result
  local ErrorString
  -- Create socket
  local NewSocket = luv.new_tcp()
  if NewSocket then
    local SocketOptions = {
      reuseaddr = false
    }
    local BindResult, BindErrorMessage = NewSocket:bind(Host, Port, SocketOptions)
    if (BindResult == 1) or (BindResult == 0) then
      -- Start listening
      local ListenResult, ListenErrorMessage = NewSocket:listen(Backlog, OnListen)
      if (ListenResult == 0) then
        Result = NewSocket
      else
        ErrorString = (ListenErrorMessage or "Listen failed")
        NewSocket:close()
        luv.run("nowait")
      end
    else
      ErrorString = (BindErrorMessage or "Bind failed")
      NewSocket:close()
      luv.run("nowait")
    end
  else
    ErrorString = "Failed to create LUV TCP socket"
  end
  -- Evaluate success
  local Success = (Result ~= nil)
  -- Return value
  return Success, Result, ErrorString
end

local function LUV_TryConnect (Host, Port)
  -- local data
  local Result
  local ErrorString
  -- Create socket
  local NewSocket = luv.new_tcp()
  if NewSocket then
    local ConnectErrorString = LUV_DoConnect(NewSocket, Host, Port)
    if (not ConnectErrorString) then
      Result = NewSocket
    else
      ErrorString = (ConnectErrorString or "Connect failed")
      NewSocket:close()
    end
  else
    ErrorString = "Failed to create LUV TCP socket"
  end
  -- Evaluate success
  local Success = (Result ~= nil)
  -- Return value
  return Success, Result, ErrorString
end

--------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS                                                           --
--------------------------------------------------------------------------------

local function SAFE_CreateAndListenTcpSocket (Backend, Host, Port, Backlog, OnListen)
  -- local data
  local Success
  local ReturnSocket
  local Attempts
  -- Handle Socket creation
  if (Backend == "LuaSocket") then
    local LogString = format("bind/listen (%s) to %s:%d", Backend, Host, Port)
    Success, ReturnSocket, Attempts = SocketSafeCall(LogString, LUASOCKET_TryBindAndListen, Host, Port, Backlog)
  elseif (Backend == "LUV") then
    local LogString = format("bind/listen (%s) to %s:%d", Backend, Host, Port)
    Success, ReturnSocket, Attempts = SocketSafeCall(LogString, LUV_TryBindAndListen, Host, Port, Backlog, OnListen)
  else
    error(format("Unsupported backend: %s", Backend))
  end
  -- Error handling
  assert(Success, format("Failed to bind/listen (%s) to %s:%d after %d attempts", Backend, Host, Port, Attempts))
  -- Return value
  return ReturnSocket
end

local function SAFE_ConnectTcpSocket (Backend, Host, Port)
  -- local data
  local Success
  local ReturnSocket
  local Attempts
  -- Handle Socket connection
  if (Backend == "LuaSocket") then
    local ActionName = format("connect (%s) to %s:%d", Backend, Host, Port)
    Success, ReturnSocket, Attempts = SocketSafeCall(ActionName, LUASOCKET_TryConnect, Host, Port)
  elseif (Backend == "LUV") then
    local ActionName = format("connect (%s) to %s:%d", Backend, Host, Port)
    Success, ReturnSocket, Attempts = SocketSafeCall(ActionName, LUV_TryConnect, Host, Port)
  else
    error(format("Unsupported backend: %s", tostring(Backend)))
  end
  -- Error handling
  assert(Success, format("Failed to connect (%s) to %s:%d after %d attempts", Backend, Host, Port, Attempts))
  -- Return value
  return ReturnSocket
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  createsafesocketandlisten = SAFE_CreateAndListenTcpSocket,
  connectsafesocket         = SAFE_ConnectTcpSocket,
}

return PUBLIC_API
