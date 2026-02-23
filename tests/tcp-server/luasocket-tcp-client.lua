--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")
assert(Runtime, "Runtime could not be loaded")

local SafeSocket = require("safe-socket")
assert(SafeSocket, "SafeSocket could not be loaded")

local mbedtls = require("mbedtls")
assert(mbedtls, "mbedtls could not be loaded")

local Ssl = require("mbedtls.ssl")
assert(Ssl, "SSL module could not be loaded")

local format            = string.format
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
  local Client = connectsafesocket("LuaSocket", Host, Port)
  assert(Client, "Failed to connect to server")
  -- Send send request
  Client:send(format("%s\n", Message))
  -- Receive response
  local Response, ReceiveErrorMessage = Client:receive("*l")
  assert((ReceiveErrorMessage == nil), ReceiveErrorMessage)
  print(format("%s", tostring(Response)))
  Client:close()
end

--------------------------------------------------------------------------------
-- SSL CLIENT                                                                 --
--------------------------------------------------------------------------------

local GLOBAL_ClientSocket

local function SSL_Read (SizeInBytes)
  local Data, ErrorMessage = GLOBAL_ClientSocket:receive(SizeInBytes)
  local Result
  if Data then
    Result = Data
  else
    if (ErrorMessage == "timeout") then
      Result = ""
    else
      error(ErrorMessage or "Read error")
    end
  end
  return Result
end

local function SSL_Write (Data)
  local BytesSent, ErrorMessage = GLOBAL_ClientSocket:send(Data)
  local Result
  if BytesSent then
    Result = BytesSent
  else
    if (ErrorMessage == "timeout") then
      Result = 0
    else
      error(ErrorMessage or "Write error")
    end
  end
  return Result
end

local function ClientSsl (Host, Port, Message)
  -- Create socket
  GLOBAL_ClientSocket = connectsafesocket("LuaSocket", Host, Port)
  assert(GLOBAL_ClientSocket, "Failed to connect to server")
  -- Create SSL context
  local SslConfig  = Ssl.newconfig("tls-client")
  local SslContext = Ssl.newcontext(SslConfig, SSL_Read, SSL_Write)
  -- Perform handshake
  local HandshakeComplete = false
  while (not HandshakeComplete) do
    local Success, HandshakeErrorMessage = SslContext:handshake()
    if Success then
      HandshakeComplete = true
    else
      if (HandshakeErrorMessage == "want-read") or (HandshakeErrorMessage == "want-write") then
        Runtime.sleepms(100)
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
