--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local luv        = require("luv")
local mbedtls    = require("mbedtls")
local Ssl        = require("mbedtls.ssl")
local SafeSocket = require("safe-socket")

local format            = string.format
local append            = table.insert
local concat            = table.concat
local min               = math.min
local connectsafesocket = SafeSocket.connectsafesocket

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local DEFAULT_HOST = "127.0.0.1" -- Use IP instead of hostname to avoid DNS lookup
local DEFAULT_PORT = 12345

--------------------------------------------------------------------------------
-- PLAINTEXT CLIENT                                                           --
--------------------------------------------------------------------------------

local function ClientNoSsl (Host, Port, Message)
  -- Connect
  local Socket = connectsafesocket("LUV", Host, Port)
  assert(Socket, "Failed to connect to server")
  -- local data
  local ResponseDone   = false
  local ResponseChunks = {}
  -- local read callback
  local function ReadCallback (Error, Chunk)
    assert(not Error, Error)
    if Chunk then
      append(ResponseChunks, Chunk)
      if Chunk:find("\n") then
        Socket:shutdown()
      end
    end
    -- all the cases: if chunk or not
    Socket:close()
    ResponseDone = true
  end
  -- Send send request
  Socket:write(format("%s\n", Message))
  -- Read response
  Socket:read_start(ReadCallback)
  -- Run the event loop until response is received
  while (not ResponseDone) do
    luv.run("once")
  end
  -- Format response
  local ReadData = concat(ResponseChunks)
  local Response = ReadData:match("([^\r\n]*)")
  print(format("%s", Response))
end

--------------------------------------------------------------------------------
-- SSL CLIENT                                                                 --
--------------------------------------------------------------------------------

local GLOBAL_ClientSocket
local ReadBuffer = ""

local function SSL_Read (SizeInBytes)
  -- Case we already have enough data
  if (#ReadBuffer >= SizeInBytes) then
    -- Just extract the needed bytes and uodate the global buffer
    local Data = ReadBuffer:sub(1, SizeInBytes)
    ReadBuffer = ReadBuffer:sub(SizeInBytes + 1)
    return Data
  end
  -- local data
  local ResponseDone = false
  -- local read callback
  local function ReadCallback (Error, Chunk)
    assert(not Error, Error)
    if Chunk then
      -- Dirty concatenation
      ReadBuffer = format("%s%s", ReadBuffer, Chunk)
      if (#ReadBuffer >= SizeInBytes) then
        GLOBAL_ClientSocket:read_stop()
      end
    else
      -- EOF
      GLOBAL_ClientSocket:read_stop()
    end
    ResponseDone = true
  end
  -- Request luv to read
  GLOBAL_ClientSocket:read_start(ReadCallback)
  -- Wait for read
  while (not ResponseDone) do
    luv.run("once")
  end
  -- Check the response
  if (#ReadBuffer == 0) then
    return "" -- EOF
  end
  -- Update the global buffer and return data
  local Available = #ReadBuffer
  local ToRead    = min(SizeInBytes, Available)
  local Data = ReadBuffer:sub(1, ToRead)
  ReadBuffer = ReadBuffer:sub(ToRead + 1)
  return Data
end

local function SSL_Write (Data)
  -- local data
  local WriteDone = false
  local BytesSent = 0
  -- local write callback
  local function WriteCallback (Error)
    assert(not Error, Error)
    BytesSent = #Data
    WriteDone = true
  end
  -- Call write
  GLOBAL_ClientSocket:write(Data, WriteCallback)
  -- Wait for write to be done
  while (not WriteDone) do
    luv.run("once")
  end
  -- Return value
  return BytesSent
end

local function ClientSsl (Host, Port, Message)
  -- Create SSL context
  local SslConfig  = Ssl.newconfig("tls-client")
  local SslContext = Ssl.newcontext(SslConfig, SSL_Read, SSL_Write)
  -- Connect socket
  GLOBAL_ClientSocket = connectsafesocket("LUV", Host, Port)
  assert(GLOBAL_ClientSocket, "Failed to connect to server")
  -- Perform handshake
  local HandshakeComplete = false
  while (not HandshakeComplete) do
    local Success, HandshakeErrorMessage = SslContext:handshake()
    if Success then
      HandshakeComplete = true
    else
      if (HandshakeErrorMessage == "want-read") or (HandshakeErrorMessage == "want-write") then
        luv.run("once")
      else
        error(format("SSL handshake failed: %s", HandshakeErrorMessage))
      end
    end
  end
  -- Send request
  local BytesWritten, WriteErrorMessage = SslContext:write(format("%s\n", Message))
  if (not BytesWritten) then
    error(format("SSL write failed: %s", WriteErrorMessage))
  end
  -- Receive response
  local Response, ReadErrorMessage = SslContext:read(1024)
  if Response then
    local Line = Response:match("([^\r\n]*)")
    print(format("%s", Line))
  else
    if (ReadErrorMessage ~= "close-notify") then
      error(format("SSL read failed: %s", ReadErrorMessage))
    end
  end
  -- Close connection
  SslContext:closenotify()
  GLOBAL_ClientSocket:shutdown()
  GLOBAL_ClientSocket:close()
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local function ParseCommandLine (Arg)
  -- Default values
  local Host    = DEFAULT_HOST
  local Port    = DEFAULT_PORT
  local Message = "REQUEST"
  local UseSsl  = false
  -- Iteration
  local Index = 1
  while (Index <= #Arg) do
    if ((Arg[Index] == "-h") and Arg[Index+1]) then
      Host  = Arg[Index+1]
      Index = (Index + 2)
    elseif ((Arg[Index] == "-p") and Arg[Index+1]) then
      Port  = (tonumber(Arg[Index+1]) or DEFAULT_PORT)
      Index = (Index + 2) -- Skip both -p and its value
    elseif (Arg[Index] == "-S") then
      UseSsl = true
      Index  = (Index + 1)
    else
      -- This is the message parameter
      Message = Arg[Index]
      Index   = (Index + 1)
    end
  end
  -- Return the configuration
  return Host, Port, UseSsl, Message
end

local Host, Port, UseSsl, Message = ParseCommandLine(arg)

if UseSsl then
  ClientSsl(Host, Port, Message)
else
  ClientNoSsl(Host, Port, Message)
end
