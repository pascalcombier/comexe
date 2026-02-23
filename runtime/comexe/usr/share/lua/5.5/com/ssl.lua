--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- MBEDTLS/SSL CLIENT ADAPTER
--
-- This file provide a compatibility layer to allow LuaSocket.request to use
-- HTTPS. To do that, this file provides a LuaSec-compliant "wrap" function
-- which is compliant with LuaSec API (LuaSocket use LuaSec for HTTPS, which use
-- OpenSSL).
--
-- We basically want to support SSL from mbedtls-lua without modifying LuaSocket
-- runtime\comexe\usr\share\lua\5.5\ssl\https.lua
--

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local mbedtls     = require("mbedtls")
local Ssl         = require("mbedtls.ssl")
local chunkbuffer = require("com.chunk-buffer")

local format         = string.format
local newconfig      = Ssl.newconfig
local newcontext     = Ssl.newcontext
local newchunkbuffer = chunkbuffer.newchunkbuffer

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local READ_WINDOW_SMALL = 512
local READ_WINDOW_LARGE = 2048

--------------------------------------------------------------------------------
-- TLS CALLBACKS                                                             --
--------------------------------------------------------------------------------

local function CLIENT_ReadCallback (Socket, SizeInBytes)
  -- local data
  local Data, ErrorString, PartialData = Socket:receive(SizeInBytes)
  local ReturnValue
  if Data then
    ReturnValue = Data
  elseif (ErrorString == "timeout") then
    if PartialData and (#PartialData > 0) then
      ReturnValue = PartialData
    else
      ReturnValue = ""
    end
  end
  -- Return value
  return ReturnValue
end

local function CLIENT_WriteCallback (Socket, Data)
  -- local data
  local BytesSent, ErrorString = Socket:send(Data)
  local ReturnValue
  if BytesSent then
    ReturnValue = BytesSent
  elseif (ErrorString == "timeout") then
    ReturnValue = 0
  end
  -- Return value
  return ReturnValue
end

--------------------------------------------------------------------------------
-- FILL HELPERS                                                              --
--------------------------------------------------------------------------------

local function CLIENT_FillBytes (ChunkBuffer, SslContext, SizeInBytes)
  -- local data
  local Success = true
  local ErrorString
  -- Main loop
  while Success and (ChunkBuffer:len() < SizeInBytes) do
    local RemainingSizeInBytes       = (SizeInBytes - ChunkBuffer:len())
    local ReadChunk, ReadErrorString = SslContext:read(RemainingSizeInBytes)
    if ReadChunk then
      ChunkBuffer:append(ReadChunk)
    elseif (ReadErrorString == "want-read") then
      Success     = false
      ErrorString = "wantread" -- Rename to "wantread" to make it Copas-compliant
    else
      Success     = false
      ErrorString = ReadErrorString
    end
  end
  -- Return value
  return Success, ErrorString
end

local function CLIENT_FillLine (ChunkBuffer, SslContext)
  -- local data
  local Success = true
  local ErrorString
  -- Main loop
  while Success and (not ChunkBuffer:haslf()) do
    local ReadChunk, ReadErrorString = SslContext:read(READ_WINDOW_SMALL)
    if ReadChunk then
      ChunkBuffer:append(ReadChunk)
    elseif (ReadErrorString == "want-read") then
      Success     = false
      ErrorString = "wantread" -- Rename to "wantread" to make it Copas-compliant
    else
      Success     = false
      ErrorString = ReadErrorString
    end
  end
  -- Return value
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- ADAPTER METHODS                                                          --
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

local function C_ADAPTER_MethodReceive (Adapter, OptionalPattern, OptionalPrefix)
  -- Retrieve data
  local ChunkBuffer = Adapter.ChunkBuffer
  local SslContext  = Adapter.SslContext
  -- Handle defaults
  local Prefix  = (OptionalPrefix  or "")
  local Pattern = (OptionalPattern or "*l")
  -- local data
  local Result
  local ErrorString
  local PartialResult
  -- Handle request
  if (Pattern == "*l") then
    local Success, FillErrorString = CLIENT_FillLine(ChunkBuffer, SslContext)
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
  elseif (Pattern == "*a") then
    local Continue = true
    while Continue do
      local Chunk, ReadErrorString = SslContext:read(READ_WINDOW_LARGE)
      if Chunk and (#Chunk > 0) then
        ChunkBuffer:append(Chunk)
      elseif (ReadErrorString == "want-read") then
        Continue = false
      else
        Continue = false
        if (ReadErrorString ~= "closed") then
          ErrorString = ReadErrorString
        end
      end
    end
    local ReceivedData = ChunkBuffer:takeall()
    Result = format("%s%s", Prefix, ReceivedData)
  else
    if (type(Pattern) == "number") then
      local Success, FillErrorString = CLIENT_FillBytes(ChunkBuffer, SslContext, Pattern)
      if Success then
        local Data = ChunkBuffer:consume(Pattern)
        Result = format("%s%s", Prefix, Data)
      else
        ErrorString   = (FillErrorString or "closed")
        PartialResult = Prefix
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
  local SslContext = Adapter.SslContext
  -- local data
  local BytesSent, ErrorString = SslContext:write(Data)
  if (BytesSent == nil) then
    if (ErrorString == "want-write") then
      ErrorString = "wantwrite"
    elseif (ErrorString == "want-read") then
      ErrorString = "wantread"
    end
  end
  -- Return value
  return BytesSent, ErrorString
end

-- Non-blocking handshake for Copas integration.
-- Returns:
--   true             on success
--   nil, "wantread"   when SSL needs to read more data
--   nil, "wantwrite"  when SSL needs to write more data
--   nil, <error>     on other errors
local function C_ADAPTER_MethodDoHandshake (Adapter)
  -- Retrieve data
  local SslContext = Adapter.SslContext
  -- local data
  local ReturnValue
  local ErrorString
  -- Handshake
  local Success, StatusString = SslContext:handshake()
  if Success then
    ReturnValue = true
  else
    if (StatusString == "continue") or (StatusString == "want-write") then
      ErrorString = "wantwrite"
    elseif (StatusString == "want-read") then
      ErrorString = "wantread"
    else
      ErrorString = StatusString
    end
  end
  -- Return value
  return ReturnValue, ErrorString
end

local function C_ADAPTER_MethodSni (Adapter, Hostname)
  -- Retrieve data
  local SslContext = Adapter.SslContext
  -- Perform SNI
  return SslContext:sethostname(Hostname)
end

local function C_ADAPTER_MethodConnect (Adapter, Host, Port)
  -- Retrieve data
  local Socket = Adapter.Socket
  -- Perform TCP connection (SSL context already existing)
  return Socket:connect(Host, Port)
end

-- LuaSec/Copas compatibility: to keep
local function C_ADAPTER_MethodToString (Adapter)
  -- Retrieve data
  local SocketString = tostring(Adapter.Socket)
  local LuaSecString = format("SSL (mbedtls): %s", SocketString)
  -- Return value
  return LuaSecString
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
    dohandshake = C_ADAPTER_MethodDoHandshake,
    sni         = C_ADAPTER_MethodSni,
    connect     = C_ADAPTER_MethodConnect,
  },
  -- Generic methods
  __tostring = C_ADAPTER_MethodToString,
}

local function NewClientAdapter (Socket, SslContext, Config)
  -- Create new Lua object
  local NewAdapter = {
    Socket      = Socket,
    SslContext  = SslContext,
    Config      = Config,
    ChunkBuffer = newchunkbuffer(),
  }
  -- Attach methods
  setmetatable(NewAdapter, C_ADAPTER_Metatable)
  -- Return value
  return NewAdapter
end

--------------------------------------------------------------------------------
-- WRAPPER SSL                                                               --
--------------------------------------------------------------------------------

-- We have copied LuaSec https file verbatim in the runtime:
-- runtime/comexe/usr/share/lua/5.5/ssl/https.lua
--
-- We also implemented a ssl.lua which essentially load com/ssl.lua:
-- runtime/comexe/usr/share/lua/5.5/com/ssl.lua (this file)
--
-- This provide a wrapper which is compatible with https.lua
--
-- Config here is a config from luasocket.http (ssl_params.wrap)
-- With the following fields:
--  verify   none
--  protocol tlsv1_2
--  options  all
--  mode     client
--#region
--
-- LIMITATION: only 1 wrapped SSL context for a given SSL configuration
-- The Wrapped thing cannot be reused
-- Because C_ADAPTER_MethodConnect is just reusing the SslContext
--
-- So the limitation is just on the performance. It won't allow reuse of SslConfig.
-- From usage perspective, it's not an issue, because we can reuse the socket.
-- We wrap it one more time with the new SSL config.
--
local function CLIENT_WrapSSL (Socket, Config)
  -- Validate inputs
  assert((Config.mode) == "client", "Only SSL client is supported")
  -- Create mbedtls context and adapter
  local NewSslConfig  = newconfig("tls-client")
  local NewSslContext = newcontext(NewSslConfig, CLIENT_ReadCallback, CLIENT_WriteCallback, Socket)
  local NewAdapter    = NewClientAdapter(Socket, NewSslContext, Config)
  -- Return value
  return NewAdapter
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  wrap = CLIENT_WrapSSL,
}

return PUBLIC_API
