--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- SSL Server Adapter for mini-httpd (Copas)
--
-- The function "wrap" is designed to be called from mini-httpd. It is needed
-- because mini-httpd is run within Copas loop. This wrapper will call
-- Copas.pause() to yield when waiting during mbedtls SSL handshake.

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Copas       = require("copas")
local mbedtls     = require("mbedtls")
local Ssl         = require("mbedtls.ssl")
local chunkbuffer = require("com.chunk-buffer")

local format         = string.format
local sub            = string.sub
local pause          = Copas.pause
local newcontext     = Ssl.newcontext
local newchunkbuffer = chunkbuffer.newchunkbuffer

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local READ_WINDOW_SMALL = 1024
local READ_WINDOW_LARGE = 4096

--------------------------------------------------------------------------------
-- COPAS COROUTINE INTEGRATION                                                --
--------------------------------------------------------------------------------

-- The functions COPAS_ReadBytesOrYield and COPAS_ReadLineOrYield seems the same
-- as the ones in ssl.lua. They are actually different: here we are calling
-- "Copas.pause()" to let other Copas coroutines work cooperatively, whereas
-- in ssl.lua we return "want-read"
--
-- SharedState is a state shared between the mbedtls callbacks (SslReadCallback,
-- SslWriteCallback) and the Copas adapter (COPAS_ReadBytesOrYield,
-- COPAS_ReadLineOrYield and other methods). We use that to keep socket/error
-- state consistent.
--
local function COPAS_ReadBytesOrYield (ChunkBuffer, SslContext, WantSizeInBytes, RawSocket, SharedState, ServerEntry)
  -- local data
  local ChunkSizeInBytes = ChunkBuffer:len()
  local Success          = true
  local ErrorString
  -- Main loop
  while Success and (ChunkSizeInBytes < WantSizeInBytes) do
    if (SharedState.value == "closed")
      or (ServerEntry.state == "STOPPED")
    then
      ErrorString = "closed"
      Success     = false
    else
      local ReadSizeInBytes            = (WantSizeInBytes - ChunkSizeInBytes)
      local ReadChunk, ReadErrorString = SslContext:read(ReadSizeInBytes)
      if ReadChunk then
        if (#ReadChunk > 0) then
          ChunkBuffer:append(ReadChunk)
          ChunkSizeInBytes = (ChunkSizeInBytes + #ReadChunk)
        else
          ErrorString = "closed"
          Success     = false
        end
      elseif (ReadErrorString == "want-read") then
        pause(0) -- Copas yield: allow other coroutines to work
      else
        Success     = false
        ErrorString = ReadErrorString
      end
    end
  end
  -- Return value
  return Success, ErrorString
end

local function COPAS_ReadLineOrYield (ChunkBuffer, SslContext, RawSocket, SharedState, ServerEntry)
  -- local data
  local Success         = true
  local MAX_DATA_CHUNKS = 4096
  local MAX_ATTEMPTS    = 1000000
  local DataChunks      = 0
  local Attempts        = 0
  local HasNewLine      = ChunkBuffer:haslf()
  local ErrorString
  -- Main loop
  while Success and (not HasNewLine) and (DataChunks < MAX_DATA_CHUNKS) and (Attempts < MAX_ATTEMPTS) do
    if (SharedState.value == "closed")
      or (ServerEntry.state == "STOPPED")
    then
      ErrorString = "closed"
      Success     = false
    else
      local ReadChunk, ReadErrorString = SslContext:read(READ_WINDOW_SMALL)
      if ReadChunk then
        if (#ReadChunk > 0) then
          ChunkBuffer:append(ReadChunk)
          HasNewLine = ChunkBuffer:haslf()
          DataChunks = (DataChunks + 1)
        else
          Success     = false
          ErrorString = "closed"
        end
      elseif (ReadErrorString == "want-read") then
        pause(0) -- Copas yield: allow other coroutines to work
      else
        Success     = false
        ErrorString = ReadErrorString
      end
      Attempts = (Attempts + 1)
    end
  end
  -- Error handling
  if (not HasNewLine) and Success then
    if (DataChunks >= MAX_DATA_CHUNKS) then
      Success     = false
      ErrorString = "max iterations data"
    elseif (Attempts >= MAX_ATTEMPTS) then
      Success     = false
      ErrorString = "max iterations attempts"
    end
  end
  -- Return value
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- SERVER ADAPTER                                                             --
--------------------------------------------------------------------------------

local function C_ADAPTER_MethodSetTimeout (Adapter, TimeoutSeconds)
  -- Retrieve data
  local Socket = Adapter.Socket
  -- Return value
  return Socket:settimeout(TimeoutSeconds)
end

local function C_ADAPTER_MethodClose (Adapter)
  -- Retrieve data
  local Socket     = Adapter.Socket
  local SslContext = Adapter.SslContext
  -- Close and reset
  SslContext:closenotify()
  SslContext:reset()
  -- Return value
  return Socket:close()
end

local function C_ADAPTER_MethodGetFd (Adapter)
  -- Retrieve data
  local Socket = Adapter.Socket
  -- Return value
  return Socket:getfd()
end

local function C_ADAPTER_MethodGetPeerName (Adapter)
  -- Retrieve data
  local Socket = Adapter.Socket
  -- Return value
  return Socket:getpeername()
end

local function C_ADAPTER_MethodDirty (Adapter)
  -- Retrieve data
  local Socket = Adapter.Socket
  -- Return value
  return Socket:dirty()
end

local function C_ADAPTER_MethodReceive (Adapter, UserPattern, UserPrefix)
  -- Retrieve data
  local ChunkBuffer = Adapter.ChunkBuffer
  local SslContext  = Adapter.SslContext
  local RawSocket   = Adapter.Socket
  local SharedState = Adapter.SharedState
  local ServerEntry = Adapter.ServerEntry
  -- Handle defaults
  local Prefix  = (UserPrefix  or "")
  local Pattern = (UserPattern or "*l")
  -- local data
  local Result
  local ErrorString
  local PartialResult
  -- Handle request
  if (Pattern == "*l") then
    if (SharedState.value == "closed")
      or (ServerEntry.state == "STOPPED")
    then
      ErrorString   = "closed"
      PartialResult = Prefix
    else
      local Success, FillErrorString = COPAS_ReadLineOrYield(ChunkBuffer, SslContext, RawSocket, SharedState, ServerEntry)
      if Success then
        local Line = ChunkBuffer:takeline()
        if Line then
          Result = format("%s%s", Prefix, Line)
        else
          ErrorString   = "closed"
          PartialResult = Prefix
        end
      else
        ErrorString   = (FillErrorString or "closed")
        PartialResult = Prefix
      end
    end
  elseif (Pattern == "*a") then
    local Continue = true
    while Continue do
      if (SharedState.value == "closed")
        or (ServerEntry.state == "STOPPED")
      then
        Continue = false
      else
        local Chunk, ReadErrorString = SslContext:read(READ_WINDOW_LARGE)
        if Chunk and (#Chunk > 0) then
          ChunkBuffer:append(Chunk)
        elseif (ReadErrorString == "want-read") then
          pause(0) -- Copas yield: allow other coroutines to work
        else
          Continue = false
          if ReadErrorString and (ReadErrorString ~= "closed") then
            ErrorString = ReadErrorString
          end
        end
      end
    end
    -- Concatenate
    local ReceivedData = ChunkBuffer:takeall()
    Result = format("%s%s", Prefix, ReceivedData)
  else
    if (type(Pattern) == "number") then
      if (SharedState.value == "closed")
        or (ServerEntry.state == "STOPPED")
      then
        ErrorString   = "closed"
        PartialResult = Prefix
      else
        local Success, FillErrorString = COPAS_ReadBytesOrYield(ChunkBuffer, SslContext, Pattern, RawSocket, SharedState, ServerEntry)
        if Success then
          local ReceivedData = ChunkBuffer:consume(Pattern)
          Result = format("%s%s", Prefix, ReceivedData)
        else
          ErrorString   = (FillErrorString or "closed")
          PartialResult = Prefix
        end
      end
    else
      ErrorString   = format("Unsupported receive pattern %q", Pattern)
      PartialResult = Prefix
    end
  end
  -- Return value
  return Result, ErrorString, PartialResult
end

local function C_ADAPTER_MethodSend (Adapter, Data)
  -- Retrieve data
  local SslContext  = Adapter.SslContext
  local RawSocket   = Adapter.Socket
  local SharedState = Adapter.SharedState
  local ServerEntry = Adapter.ServerEntry
  -- local data
  local MAX_ATTEMPTS = 1000
  local DATA_LENGTH  = #Data
  local TotalSent    = 0
  local Attempts     = 0
  local Continue     = true
  local ErrorString
  -- Main loop: use mbedtls context to send data
  while Continue and (TotalSent < DATA_LENGTH) and (Attempts < MAX_ATTEMPTS) do
    if (SharedState.value == "closed")
      or (ServerEntry.state == "STOPPED")
    then
      ErrorString = "closed"
      Continue    = false
    else
      local RemainingData         = sub(Data, (TotalSent + 1))
      local BytesSent, WriteError = SslContext:write(RemainingData)
      if BytesSent and (BytesSent > 0) then
        TotalSent = (TotalSent + BytesSent)
        Attempts  = (Attempts + 1)
      elseif (WriteError == "want-write") then
        pause(0) -- Copas yield: allow other coroutines to work
      else
        ErrorString = (WriteError or "write-error")
        Continue    = false
      end
    end
  end
  -- Evaluate result
  local ReturnValue
  if (ErrorString == nil) then
    ReturnValue = TotalSent
  end
  -- Return value
  return ReturnValue, ErrorString
end

-- LuaSec/Copas compatibility: to keep
local function C_ADAPTER_MethodToString (Adapter)
  -- Retrieve data
  local Socket          = Adapter.Socket
  local SocketString    = tostring(Socket)
  local FormattedString = format("SSL-Server (mbedtls): %s", SocketString)
  -- Return value
  return FormattedString
end

local C_ADAPTER_Metatable = {
  -- Custom methods
  __index = {
    settimeout  = C_ADAPTER_MethodSetTimeout,
    close       = C_ADAPTER_MethodClose,
    getfd       = C_ADAPTER_MethodGetFd,
    getpeername = C_ADAPTER_MethodGetPeerName,
    dirty       = C_ADAPTER_MethodDirty,
    receive     = C_ADAPTER_MethodReceive,
    send        = C_ADAPTER_MethodSend,
  },
  -- Generic methods
  __tostring = C_ADAPTER_MethodToString,
}

local function NewServerAdapter (RawSocket, SslContext, SharedState, ServerEntry)
  -- Create new Lua object
  local NewAdapter = {
    Socket      = RawSocket,
    ChunkBuffer = newchunkbuffer(),
    SslContext  = SslContext,
    SharedState = SharedState,
    ServerEntry = ServerEntry,
  }
  -- Attach methods
  setmetatable(NewAdapter, C_ADAPTER_Metatable)
  -- return value
  return NewAdapter
end

--------------------------------------------------------------------------------
-- SSL HANDSHAKE                                                              --
--------------------------------------------------------------------------------

local function SERVER_SslHandshake (SslContext, MaxAttempts, RawSocket, SharedState, ServerEntry)
  -- local data
  local Success
  local ErrorString
  -- Main loop
  local Attempts = 0
  local State    = "ONGOING"
  -- Main loop
  while ((State == "ONGOING") and (Attempts < MaxAttempts)) do
    if (SharedState.value == "closed")
      or (ServerEntry.state == "STOPPED")
    then
      ErrorString = "SSL handshake failed: closed"
      State       = "FAILED"
    else
      local StepSuccess, StatusString = SslContext:handshake_step()
      if StepSuccess then
        State = "SUCCESS"
      else
        if (StatusString == "want-read") or (StatusString == "want-write")
          or (StatusString == "continue")
        then
          pause(0) -- Allow other Copas coroutines to do something
        else
          ErrorString = format("SSL handshake failed: %q", StatusString)
          State       = "FAILED"
        end
      end
    end
    Attempts = (Attempts + 1)
  end
  -- Evaluate success
  Success = (State == "SUCCESS")
  if (not Success) and (not ErrorString) then
    ErrorString = format("handshake timeout (%d/%d)", Attempts, MaxAttempts)
  end
  -- Return value
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- WRAPPER SSL                                                                --
--------------------------------------------------------------------------------

-- From software architecture, this part is not very nice. We have loops in
-- COPAS_ReadBytesOrYield and COPAS_ReadLineOrYield. We want to exit them as
-- soon as possible.
--
-- We need the state of the server from mini-http, so for simplicity, we provide
-- the ServerEntry table. We actually only need to get the ServerEntry.state.
--
-- We also need an additionnal SharedState, internal to ssl-server.lua which is
-- documented in COPAS_ReadBytesOrYield.

-- Wrap a raw client socket with server-side TLS
-- Performs handshake and returns a socket-like adapter
-- Parameters:
--   RawSocket: raw LuaSocket TCP socket (not Copas-wrapped)
--   SslConfig: mbedtls SSL config (from newconfig or newconfig_mem)
-- Returns:
--   WrappedSocket, nil on success
--   nil, ErrorString on failure
local function SERVER_WrapSSL (RawSocket, SslConfig, ServerEntry)
  -- NOTE: We intentionally use the raw LuaSocket during handshake.
  -- Copas-wrapped sockets may yield inside WrappedSocket:receive(), but mbedtls
  -- drives read/write callbacks while still inside a non-yieldable C function.
  -- Yielding will raises the error "attempt to yield across a C-call
  -- boundary". Using the raw socket keeps callbacks synchronous so
  -- handshake_step() can progress safely.
  local SharedState = { value = "initial-state" }
  local function SslReadCallback (SizeInBytes)
    local ReceiveData, ErrorMessage = RawSocket:receive(SizeInBytes)
    if (ErrorMessage == "closed") then
      SharedState.value = "closed"
    end
    -- On failure, return "" to signal want-read/closed to mbedtls
    -- Returning nil causes "invalid read result" in some bindings.
    return ReceiveData or ""
  end
  local function SslWriteCallback (Data)
    local SendSuccess, ErrorMessage = RawSocket:send(Data)
    if (ErrorMessage == "closed") then
      SharedState.value = "closed"
    end
    -- On failure, return 0 to signal want-write/closed to mbedtls
    return SendSuccess or 0
  end
  -- local variables
  local NewSslContext
  local ErrorString
  local NewAdapter
  -- Create SSL context
  NewSslContext, ErrorString = newcontext(SslConfig, SslReadCallback, SslWriteCallback)
  if NewSslContext then
    local Success
    local MaxAttempts    = 10000
    Success, ErrorString = SERVER_SslHandshake(NewSslContext, MaxAttempts, RawSocket, SharedState, ServerEntry)
    if Success then
      NewAdapter = NewServerAdapter(RawSocket, NewSslContext, SharedState, ServerEntry)
    end
  end
  -- Return value
  return NewAdapter, ErrorString
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  wrap = SERVER_WrapSSL,
}

return PUBLIC_API
