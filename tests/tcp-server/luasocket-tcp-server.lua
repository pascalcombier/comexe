--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- Note that :receive("l") or :receive("a") is not working with luasocket. The
-- API is hardcoded in third-party\src\luasocket\src\buffer.c (in the function
-- buffer_meth_receive) and on accept old "*l" or "*a". The new Lua 5.4 API
-- :receive("a") or :receive("l") is not supported.

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Socket = require("socket")
assert(Socket, "Socket could not be loaded")

local SafeSocket = require("safe-socket")
assert(SafeSocket, "SafeSocket could not be loaded")

local Runtime = require("com.runtime")
assert(Runtime, "Runtime could not be loaded")

local mbedtls = require("mbedtls")
assert(mbedtls, "mbedtls could not be loaded")

local Ssl = require("mbedtls.ssl")
assert(Ssl, "SSL module could not be loaded")

local format                    = string.format
local createsafesocketandlisten = SafeSocket.createsafesocketandlisten
local stringtrim                = Runtime.stringtrim

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local DEFAULT_PORT = 12345
local DEFAULT_HOST = "127.0.0.1" -- Use IP instead of hostname to avoid DNS lookup

--------------------------------------------------------------------------------
-- SERVER WITHOUT SSL                                                         --
--------------------------------------------------------------------------------

local function ServerNoSsl (Port, FormatResponse)
  -- Create and listen on server socket
  local ServerSocket = createsafesocketandlisten("LuaSocket", DEFAULT_HOST, Port, 32)
  -- Log
  print(format("Server created on port %d (plain TCP)", Port))
  print("Ctrl+C to close the server")
  -- Main loop
  local CloseRequest = false
  local Response
  while (not CloseRequest) do
    local Client, ErrorMessage = ServerSocket:accept()
    assert((ErrorMessage == nil), ErrorMessage)
    assert(Client, "Failed to accept client connection")
    local Request, ErrorString = Client:receive("*l")
    Request = stringtrim(Request)
    print(format("REQ:[%s]", Request))
    CloseRequest, Response = FormatResponse(Request)
    Client:send(format("%s\n", Response))
    Client:close()
  end
  ServerSocket:close()
end

--------------------------------------------------------------------------------
-- SERVER WITH SSL                                                            --
--------------------------------------------------------------------------------

local function SSL_Handshake (SslContext, MaxAttempts)
  -- Local variables
  local HandshakeComplete = false
  local Attempts          = 0
  -- Iterate
  while ((not HandshakeComplete) and (Attempts < MaxAttempts)) do
    local Success, HandshakeErrorMessage = SslContext:handshake()
    if Success then
      HandshakeComplete = true
    else
      if ((HandshakeErrorMessage == "want-read") or (HandshakeErrorMessage == "want-write")) then
        Socket.sleep(0.01)
      else
        print(format("SSL handshake failed: %s", HandshakeErrorMessage or "unknown error"))
      end
    end
    Attempts = (Attempts + 1)
  end
  -- Return value
  return HandshakeComplete
end

local function ServerSsl (Port, HandleRequest)
  -- Create SSL configuration
  local SslConfig = Ssl.newconfig("tls-server")
  assert(SslConfig, "Failed to create SSL server configuration")
  -- Create and listen on server socket
  local ServerSocket = createsafesocketandlisten("LuaSocket", DEFAULT_HOST, Port, 32)
  -- Log
  print(format("Server created on port %d (SSL)", Port))
  print("Ctrl+C to close the server")
  -- Main loop
  local CloseRequest = false
  local Response
  while (not CloseRequest) do
    local Client, ErrorMessage = ServerSocket:accept()
    assert(Client, format("Failed to accept client connection: %s", ErrorMessage or "unknown error"))

    local function SSL_Read (SizeInBytes)
      local Data, ErrorMessage = Client:receive(SizeInBytes)
      return Data or ""
    end

    local function SSL_Write (Data)
      local BytesSent, ErrorMessage = Client:send(Data)
      return BytesSent or 0
    end

    local SslContext = Ssl.newcontext(SslConfig, SSL_Read, SSL_Write)
    assert(SslContext, "Failed to create SSL context")

    local HandshakeComplete = SSL_Handshake(SslContext, 100)

    if HandshakeComplete then
      local ReadString, ReadErrorMessage = SslContext:read(1024)
      if (ReadErrorMessage == "want-read") then
        ReadString = ""
      elseif (ReadErrorMessage and (ReadErrorMessage ~= "close-notify")) then
        print(format("SSL read error: %s", ReadErrorMessage))
        ReadString = ""
      end
      local Request = stringtrim(ReadString)
      print(format("REQ:[%s]", Request))
      CloseRequest, Response = HandleRequest(Request)
      local BytesWritten = SslContext:write(format("%s\n", Response))
      if (BytesWritten ~= #Response + 1) then
        print("SSL write error")
      end
      SslContext:closenotify()
    end
    Client:close()
  end
  ServerSocket:close()
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local function ParseCommandLine (Arg)
  -- Default values
  local Port         = DEFAULT_PORT
  local UseSsl       = false
  local ServerModule = "default-server"
  local Index       = 1
  -- Iteration
  while (Index <= #Arg) do
    if ((Arg[Index] == "-p") and Arg[Index+1]) then
      Port  = tonumber(Arg[Index+1]) or DEFAULT_PORT
      Index = (Index + 2)
    elseif (Arg[Index] == "-S") then
      UseSsl = true
      Index  = (Index + 1)
    elseif ((Arg[Index] == "-F") and Arg[Index+1]) then
      ServerModule = Arg[Index+1]
      Index        = (Index + 2)
    else
      Index = (Index + 1)
    end
  end
  -- Return the configuration
  return Port, UseSsl, ServerModule
end

local Port, UseSsl, ServerModule = ParseCommandLine(arg)

-- Load the server request handler
local RequestHandler = require(ServerModule)

if UseSsl then
  ServerSsl(Port, RequestHandler)
else
  ServerNoSsl(Port, RequestHandler)
end