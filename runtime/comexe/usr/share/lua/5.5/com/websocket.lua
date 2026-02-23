--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- WebSocket is implemented on the top of mini-httpd API 
-- It uses the "Request" object as input
-- Example: tests\mini-httpd\hello-httpd.lua

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local mbdetlsmd     = require("mbedtls.md")
local mbedtlsbase64 = require("mbedtls.base64")

local append = table.insert
local format = string.format
local lower  = string.lower
local find   = string.find
local concat = table.concat
local char   = string.char
local byte   = string.byte

local hash         = mbdetlsmd.hash
local encodeBase64 = mbedtlsbase64.encode

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

-- WebSocket GUID for Accept key calculation (RFC 6455)
local WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

-- WebSocket close codes (RFC 6455)
local WEBSOCKET_CLOSE_NORMAL = 1000

--------------------------------------------------------------------------------
-- FRAME DOCUMENTATION                                                        --
--------------------------------------------------------------------------------

-- WebSocket Frame Encoding/Decoding module for mini-httpd
-- Implements RFC 6455 WebSocket framing protocol
--
-- Frame format:
--  0                   1                   2                   3
--  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
-- +-+-+-+-+-------+-+-------------+-------------------------------+
-- |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
-- |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
-- |N|V|V|V|       |S|             |   (if payload len==126/127)   |
-- | |1|2|3|       |K|             |                               |
-- +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
-- |     Extended payload length continued, if payload len == 127  |
-- + - - - - - - - - - - - - - - - +-------------------------------+
-- |                               |Masking-key, if MASK set to 1  |
-- +-------------------------------+-------------------------------+
-- | Masking-key (continued)       |          Payload Data         |
-- +-------------------------------- - - - - - - - - - - - - - - - +
-- :                     Payload Data continued ...                :
-- + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
-- |                     Payload Data continued ...                |
-- +---------------------------------------------------------------+
--
-- Opcodes:
--   0x0 = continuation frame
--   0x1 = text frame
--   0x2 = binary frame
--   0x8 = connection close
--   0x9 = ping
--   0xA = pong

-- Notes:
-- client->server frames MUST be masked
-- server->client frames MUST NOT be masked

--------------------------------------------------------------------------------
-- FRAME                                                                      --
--------------------------------------------------------------------------------

-- WebSocket Opcodes
local OPCODE_CONTINUATION = 0x0
local OPCODE_TEXT         = 0x1
local OPCODE_BINARY       = 0x2
local OPCODE_CLOSE        = 0x8
local OPCODE_PING         = 0x9
local OPCODE_PONG         = 0xA

local FIN_BIT  = 0x80
local MASK_BIT = 0x80

-- client->server: frames are masked
-- Unmask payload data using XOR with 4-byte masking key
local function FRAME_UnmaskPayload (MaskedData, MaskKey)
  -- local data
  local UnmaskedBytes = {}
  local DataLen       = #MaskedData
  local Index         = 1
  -- Iterate over all the bytes
  while (Index <= DataLen) do
    local MaskedByte   = byte(MaskedData, Index)
    local KeyByte      = byte(MaskKey, ((Index - 1) % 4) + 1) -- 1->4->1->4->etc
    local UnmaskedByte = (MaskedByte ~ KeyByte) -- XOR
    UnmaskedBytes[Index] = char(UnmaskedByte)
    Index = (Index + 1)
  end
  -- Format result
  local Result = concat(UnmaskedBytes)
  return Result
end

-- This function use early returns style, hard to avoid without increased complexity
-- Read a WebSocket frame from socket
-- Returns: Frame table or nil, ErrorMessage
-- Frame table: { fin, opcode, masked, payload, closecode, closereason }
local function FRAME_Read (SocketReadFunction)
  local NewFrame = {}
  -- Read first two bytes (header)
  local Header, ErrorMessage = SocketReadFunction(2)
  if (not Header) or (#Header < 2) then
    return nil, (ErrorMessage or "connection closed")
  end
  local Byte1 = byte(Header, 1)
  local Byte2 = byte(Header, 2)
  -- Parse first byte: FIN + RSV + Opcode
  NewFrame.fin    = ((Byte1 & FIN_BIT) ~= 0)
  NewFrame.opcode = (Byte1 & 0x0F)
  -- Parse second byte: MASK + Payload length
  NewFrame.masked = ((Byte2 & MASK_BIT) ~= 0)
  local PayloadLen = (Byte2 & 0x7F)
  -- Extended payload length
  if (PayloadLen == 126) then
    -- 16-bit length
    local ExtLen = SocketReadFunction(2)
    if (not ExtLen) or (#ExtLen < 2) then
      return nil, "failed to read extended length"
    end
    PayloadLen = ((byte(ExtLen, 1) << 8) | byte(ExtLen, 2))
  elseif (PayloadLen == 127) then
    -- 64-bit length (read as 8 bytes, use lower 32 bits for safety)
    local ExtLen = SocketReadFunction(8)
    if (not ExtLen) or (#ExtLen < 8) then
      return nil, "failed to read extended length"
    end
    -- Use lower 4 bytes only (Lua numbers may not handle full 64-bit)
    PayloadLen = ((byte(ExtLen, 5) << 24) | (byte(ExtLen, 6) << 16) | (byte(ExtLen, 7) << 8) | byte(ExtLen, 8))
  end
  -- Read masking key if present (client-to-server frames must be masked)
  local MaskKey
  if NewFrame.masked then
    MaskKey = SocketReadFunction(4)
    if (not MaskKey) or (#MaskKey < 4) then
      return nil, "failed to read masking key"
    end
  end
  -- Read payload data
  local Payload = ""
  if (PayloadLen > 0) then
    Payload = SocketReadFunction(PayloadLen)
    if (not Payload) or (#Payload < PayloadLen) then
      return nil, "failed to read payload"
    end
    -- Unmask if needed
    if NewFrame.masked and MaskKey then
      Payload = FRAME_UnmaskPayload(Payload, MaskKey)
    end
  end
  NewFrame.payload = Payload
  -- Parse close frame payload (status code + reason)
  if (NewFrame.opcode == OPCODE_CLOSE) and (#Payload >= 2) then
    NewFrame.closecode   = ((byte(Payload, 1) << 8) | byte(Payload, 2))
    NewFrame.closereason = Payload:sub(3)
  end
  -- Return value
  return NewFrame
end

-- Low-level function for frame building, for potential OPCODE_CONTINUATION
-- server-to-client: no masking
-- Returns: frame data as string
-- IsFinal is for multi-frame messages OPCODE_CONTINUATION which is 0 by default
-- Don't support 64-bits lengths, only up to 32-bits (max 4GB)
local function FRAME_Build (Opcode, Payload, OptionalIsFinal)
  -- Handle defaults: IsFinal is true by default
  local IsFinal = (OptionalIsFinal ~= false)
  -- local data
  local FrameBytes  = {}
  local PayloadSize = #Payload
  -- First byte: FIN + Opcode
  if IsFinal then
    append(FrameBytes, char(Opcode | FIN_BIT))
  else
    append(FrameBytes, char(Opcode))
  end
  -- Second byte: no MASK + payload length
  if (PayloadSize <= 125) then
    append(FrameBytes, char(PayloadSize))
  elseif (PayloadSize <= 65535) then
    append(FrameBytes, char(126))
    append(FrameBytes, char(PayloadSize >> 8))
    append(FrameBytes, char(PayloadSize & 0xFF))
  else
    append(FrameBytes, char(127))
    -- 64-bit length: use only lower 32 bits
    append(FrameBytes, "\x00\x00\x00\x00")
    append(FrameBytes, char((PayloadSize >> 24) & 0xFF))
    append(FrameBytes, char((PayloadSize >> 16) & 0xFF))
    append(FrameBytes, char((PayloadSize >> 8) & 0xFF))
    append(FrameBytes, char(PayloadSize & 0xFF))
  end
  -- Payload (no masking for server-to-client)
  append(FrameBytes, Payload)
  -- Return value
  local FrameData = concat(FrameBytes)
  return FrameData
end

local function FRAME_BuildText (Text, IsFinal)
  -- Build frame
  local FrameData = FRAME_Build(OPCODE_TEXT, Text, IsFinal)
  -- Return value
  return FrameData
end

local function FRAME_BuildBinary (Data, IsFinal)
  -- Build frame
  local FrameData = FRAME_Build(OPCODE_BINARY, Data, IsFinal)
  -- Return value
  return FrameData
end

local function FRAME_BuildClose (StatusCode, Reason)
  local Payload
  if StatusCode then
    local BuildReason = (Reason or "")
    local CodeHigh    = char(StatusCode >> 8)
    local CodeLow     = char(StatusCode & 0xFF)
    Payload = format("%s%s%s", CodeHigh, CodeLow, BuildReason)
  else
    Payload = ""
  end
  local FrameData = FRAME_Build(OPCODE_CLOSE, Payload, true)
  return FrameData
end

local function FRAME_BuildPing (Data)
  local BuildData = (Data or "")
  local FrameData = FRAME_Build(OPCODE_PING, BuildData, true)
  return FrameData
end

local function FRAME_BuildPong (Data)
  local BuildData = (Data or "")
  local FrameData = FRAME_Build(OPCODE_PONG, BuildData, true)
  return FrameData
end

--------------------------------------------------------------------------------
-- WEBSOCKET CONNECTION OBJECT                                                --
--------------------------------------------------------------------------------

-- If WebSocket:IsOpen() is false, the socket need to be closed
local function CON_MethodIsOpen (Connexion)
  -- Retrieve data
  local IsOpen = Connexion.open
  -- Return value
  return IsOpen
end

local function CON_MethodSendText (Connexion, Text, OptionalIsFinal)
  -- Handle defaults: IsFinal is true by default
  local IsFinal = (OptionalIsFinal ~= false)
  -- Retrieve data
  local Request = Connexion.request
  -- Build frame and send
  local NewFrame = FRAME_BuildText(Text, IsFinal)
  local Success, ErrorString = Request:send(NewFrame)
  -- Return value
  return Success, ErrorString
end

local function CON_MethodSendBinary (Connexion, Data, OptionalIsFinal)
  -- Handle defaults: IsFinal is true by default
  local IsFinal = (OptionalIsFinal ~= false)
  -- Retrieve data
  local Request = Connexion.request
  -- Build frame and send
  local NewFrame = FRAME_BuildBinary(Data, IsFinal)
  local Success, ErrorString = Request:send(NewFrame)
  -- Return value
  return Success, ErrorString
end

local function CON_MethodSendPing (Connexion, Data)
  -- Handle defaults
  local SendData = (Data or "")
  -- Retrieve data
  local Request = Connexion.request
  -- Build frame and send
  local NewFrame = FRAME_BuildPing(SendData)
  local Success, ErrorString = Request:send(NewFrame)
  -- Return value
  return Success, ErrorString
end

-- Receive a message from WebSocket
-- Returns: payload, opcode (or nil, errorMessage)
-- Automatically handles ping/pong and close frames
local function CON_MethodReceive (Connexion)
  -- Retrieve data
  local IsOpen = Connexion.open
  -- local data
  local Payload
  local Opcode
  local ErrorString
  if IsOpen then
    -- Create receive function for frame reader using Request API
    local Request = Connexion.request
    local function SocketRead (SizeInBytes)
      return Request:receive(SizeInBytes)
    end
    -- Read and process frames
    local Continue = true
    while Continue do
      local Frame
      Frame, ErrorString = FRAME_Read(SocketRead)
      if Frame then
        local FramePayload   = Frame.payload
        local FrameOpcode    = Frame.opcode
        local FrameCloseCode = Frame.closecode
        if (FrameOpcode == OPCODE_CLOSE) then
          local CloseCode  = (FrameCloseCode or WEBSOCKET_CLOSE_NORMAL)
          local CloseFrame = FRAME_BuildClose(CloseCode)
          Request:send(CloseFrame)
          -- Update status
          Connexion.open = false
          Continue       = false
        elseif (FrameOpcode == OPCODE_PING) then
          local PongFrame = FRAME_BuildPong(FramePayload)
          Request:send(PongFrame)
          Request:yield()
        elseif (FrameOpcode == OPCODE_PONG) then
          Request:yield()
        else
          Payload  = FramePayload
          Opcode   = FrameOpcode
          Continue = false
        end
      else
        -- No frame read from readframe
        Connexion.open = false
        Continue = false
      end
    end
  else
    ErrorString = "connection closed"
  end
  -- Return value
  return Payload, Opcode, ErrorString
end

local function CON_MethodSleep (Connexion, Seconds)
  -- Retrieve data
  local Request = Connexion.request
  -- Perform action
  Request:sleep(Seconds)
end

local function CON_MethodSetTimeout (Connexion, TimeoutSec)
  -- Retrieve data
  local Request = Connexion.request
  -- Perform action
  Request:settimeout(TimeoutSec)
end

local function CON_MethodClose (Connexion, UserStatusCode, UserReason)
  -- Handle defaults
  local StatusCode = (UserStatusCode or WEBSOCKET_CLOSE_NORMAL)
  -- local data
  local Success
  local ErrorString
  -- Retrieve data
  local IsOpen  = Connexion.open
  local Request = Connexion.request
  -- Handle close
  if IsOpen then
    local NewFrame = FRAME_BuildClose(StatusCode, UserReason)
    Success, ErrorString = Request:send(NewFrame)
    -- NOTE: we don't call Request:finish() here it shall be the caller
    -- Update state
    Connexion.open = false
  else
    ErrorString = "connection already closed"
  end
  Success = (ErrorString == nil)
  -- Return value
  return Success, ErrorString
end

local function WS_NewConnexion (Request)
  local NewConnection = {
    -- state
    request = Request,
    open    = true,
    -- methods
    isopen     = CON_MethodIsOpen,
    sendtext   = CON_MethodSendText,
    sendbinary = CON_MethodSendBinary,
    sendping   = CON_MethodSendPing,
    receive    = CON_MethodReceive,
    sleep      = CON_MethodSleep,
    settimeout = CON_MethodSetTimeout,
    close      = CON_MethodClose,
  }
  return NewConnection
end

--------------------------------------------------------------------------------
-- MAIN FUNCTIONS                                                             --
--------------------------------------------------------------------------------

-- Check if HTTP request is a WebSocket upgrade request
local function WS_IsUpgradeRequest (Headers)
  -- Read headers
  local UpgradeHeader    = Headers["upgrade"]
  local ConnectionHeader = Headers["connection"]
  local SecKeyHeader     = Headers["sec-websocket-key"]
  local IsUpgrade
  if UpgradeHeader and ConnectionHeader and SecKeyHeader then
    local UpgradeLower    = lower(UpgradeHeader)
    local ConnectionLower = lower(ConnectionHeader)
    local HasUpgrade      = (UpgradeLower == "websocket")
    local HasConnection   = find(ConnectionLower, "upgrade", 1, true)
    IsUpgrade             = (HasUpgrade and HasConnection)
  else
    IsUpgrade = false
  end
  return IsUpgrade
end

-- Compute Sec-WebSocket-Accept value from Sec-WebSocket-Key
-- Accept = Base64(SHA1(Key + GUID))
local function WS_ComputeAcceptKey (SecWebSocketKey)
  local ConcatKey = format("%s%s", SecWebSocketKey, WEBSOCKET_GUID)
  local OptionRaw = true
  local Sha1Hash  = hash("SHA1", ConcatKey, OptionRaw)
  local AcceptKey = encodeBase64(Sha1Hash)
  return AcceptKey
end

-- Build HTTP 101 Switching Protocols response
local function WS_FormatUpgradeResponse (SecWebSocketKey, SubProtocol)
  local AcceptKey = WS_ComputeAcceptKey(SecWebSocketKey)
  local ResponseLines = {
    "HTTP/1.1 101 Switching Protocols\r\n",
    "Upgrade: websocket\r\n",
    "Connection: Upgrade\r\n",
    format("Sec-WebSocket-Accept: %s\r\n", AcceptKey),
  }
  if SubProtocol then
    append(ResponseLines, format("Sec-WebSocket-Protocol: %s\r\n", SubProtocol))
  end
  append(ResponseLines, "\r\n")
  -- Format response
  local Response = concat(ResponseLines)
  return Response
end

-- Sec-WebSocket-Protocol is an optional header used to negotiate an
-- application-level protocol. Exmaple below:
--
-- Request
-- Sec-WebSocket-Protocol: chat, superchat
-- Response
-- Sec-WebSocket-Protocol: chat
--
-- Below in WS_NewWebSocket, if PreferedProtocol is not provided we will return
-- all the protocols requested by the client, which is not correct according to
-- the standard. But would be OK if the SubProtocol contains only one protocol.
--
-- For a proper implementation, the client should read the headers and provide
-- the prefered protocol to use.

-- Create a new WebSocket from an HTTP Request object
-- Returns: WebSocket connection object or nil, errorMessage
local function WS_NewWebSocket (Request, PreferedProtocol)
  local NewConnexion
  local ErrorString
  local Headers = Request.headers
  local Key     = Headers["sec-websocket-key"]
  if Key then
    -- Check if it's a WebSocket upgrade request
    if WS_IsUpgradeRequest(Headers) then
      -- Notify mini-httpd that connection is upgraded (no longer keep-alive)
      Request:upgrade()
      -- Choose a protocol
      local SubProtocol     = Headers["sec-websocket-protocol"]
      local ChosenProtocol  = (PreferedProtocol or SubProtocol)
      local UpgradeResponse = WS_FormatUpgradeResponse(Key, ChosenProtocol)
      local Success
      Success, ErrorString = Request:send(UpgradeResponse)
      if Success then
        NewConnexion = WS_NewConnexion(Request)
      end
    else
      ErrorString = "not a WebSocket upgrade request"
    end
  else
    ErrorString = "missing Sec-WebSocket-Key header"
  end
  return NewConnexion, ErrorString
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  newwebsocket = WS_NewWebSocket
}

return PUBLIC_API
