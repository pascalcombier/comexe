--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- This is a luv-based implementation that clones the functionality of
-- tests\luasocket\tcp-server.lua but using the luv library instead of luasocket

-- This is significantly more difficult than the luasocket version
-- due to the asynchronous nature of luv and the way it handles SSL/TLS connections.

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local luv         = require("luv")
local mbedtls     = require("mbedtls")
local Ssl         = require("mbedtls.ssl")
local Runtime     = require("com.runtime")
local SafeSocket  = require("safe-socket")
local chunkbuffer = require("com.chunk-buffer")

local format         = string.format
local newchunkbuffer = chunkbuffer.newchunkbuffer
local stringtrim     = Runtime.stringtrim

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local DEFAULT_PORT = 12345
local DEFAULT_HOST = "127.0.0.1"

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function ClientMethodRead (Client, SizeInBytes)
  local ChunkBuffer = Client.ChunkBuffer
  local ReadData    = ChunkBuffer:consume(SizeInBytes)
  local Result
  if ReadData then
    Result = ReadData
  else
    Result = ""
  end
  return Result
end

local function ClientMethodWrite (Client, Data)
  local LibuvSocket = Client.LibuvSocket
  LibuvSocket:write(Data)
  return #Data
end

local function ClientHandleSocketRead (Client, Error, Chunk)
  local LibuvSocket = Client.LibuvSocket
  local ChunkBuffer = Client.ChunkBuffer
  if Error then
    LibuvSocket:close()
    return
  end
  if (not Chunk) then
    LibuvSocket:close()
    return
  end
  ChunkBuffer:append(Chunk)
  local ProcessingDone = Client:ProcessChunks()
end

local function ClientTryProcessHandshake (Client)
  local SslContext = Client.SslContext
  local Success, HandshakeErrorMessage = SslContext:handshake()
  local ProcessingDone
  if Success then
    Client.State   = "DataTransfer"
    ProcessingDone = Client:TryDataTransfer()
  else
    ProcessingDone = false
  end
  return ProcessingDone
end

local function ClientTryProcessDataTransfer (Client)
  local SslContext     = Client.SslContext
  local LibuvSocket    = Client.LibuvSocket
  local RequestHandler = Client.RequestHandler
  local ProcessingDone = false
  local ReadString, ReadErrorMessage = SslContext:read(1024)
  if (ReadErrorMessage == "want-read") then
    ProcessingDone = false
  elseif (ReadErrorMessage == "close-notify") then
    LibuvSocket:close()
    ProcessingDone = true
  elseif (ReadErrorMessage and (ReadErrorMessage ~= "close-notify")) then
    ProcessingDone = false
  else
    local Request = stringtrim(ReadString)
    if Request then
      local CloseRequest, Response = RequestHandler(Request)
      SslContext:write(format("%s\n", Response))
      LibuvSocket:shutdown()
      LibuvSocket:close()
      if CloseRequest then
        luv.stop()
      end
      ProcessingDone = true
    else
      ProcessingDone = false
    end
  end
  return ProcessingDone
end

local function ClientProcessChunks (Client)
  local State = Client.State
  local ProcessingDone
  if (State == "WaitForHandshake") then
    ProcessingDone = Client:TryHandshake()
  elseif (State == "DataTransfer") then
    ProcessingDone = Client:TryDataTransfer()
  else
    local LibuvSocket = Client.LibuvSocket
    LibuvSocket:close()
    ProcessingDone = true
  end
  return ProcessingDone
end

local ClientMetatable = {
  __index = {
    BlockingRead     = ClientMethodRead,
    BlockingWrite    = ClientMethodWrite,
    TryHandshake     = ClientTryProcessHandshake,
    TryDataTransfer  = ClientTryProcessDataTransfer,
    ProcessChunks    = ClientProcessChunks,
    handle_socket_read = ClientHandleSocketRead,
  }
}

local ActiveClientCount = 0

local function CreateClient (ClientSocket, SslConfig, RequestHandler)
  ActiveClientCount = (ActiveClientCount + 1)
  local NewClient = {
    Id             = tostring(ActiveClientCount),
    LibuvSocket    = ClientSocket,
    ChunkBuffer    = newchunkbuffer(),
    State          = "WaitForHandshake",
    RequestHandler = RequestHandler
  }
  setmetatable(NewClient, ClientMetatable)
  local function BlockingRead(SizeInBytes)
    return NewClient:BlockingRead(SizeInBytes)
  end
  local function BlockingWrite(Data)
    return NewClient:BlockingWrite(Data)
  end
  local NewSslContext = Ssl.newcontext(SslConfig, BlockingRead, BlockingWrite)
  assert(NewSslContext, "Failed to create SSL context")
  NewClient.SslContext = NewSslContext
  return NewClient
end

--------------------------------------------------------------------------------
-- LIBUV CALLBACKS                                                            --
--------------------------------------------------------------------------------

local function HandleNewClient (ClientSocket, SslConfig, RequestHandler)
  -- Create a new client
  local NewClient = CreateClient(ClientSocket, SslConfig, RequestHandler)
  -- Local socket read function
  local function OnSocketRead (...)
    NewClient:handle_socket_read(...)
  end
  -- Start reading from the client socket
  ClientSocket:read_start(OnSocketRead)
end

local function CreateServerSocket (Host, Port, OnNewConnection, SslConfig, RequestHandler)
  -- local data
  local ServerSocket
  -- Local listen function
  local function OnListen (ErrorMessage)
    assert((ErrorMessage == nil), ErrorMessage)
    local NewClientSocket = luv.new_tcp()
    ServerSocket:accept(NewClientSocket)
    -- Start handling the new client connection
    OnNewConnection(NewClientSocket, SslConfig, RequestHandler)
  end
  -- Create and listen on server socket
  ServerSocket = SafeSocket.createsafesocketandlisten("LUV", Host, Port, 128, OnListen)
  -- Return value
  return ServerSocket
end

--------------------------------------------------------------------------------
-- PLAINTEXT SERVER                                                           --
--------------------------------------------------------------------------------

local function ServerNoSsl (Port, RequestHandler)
  -- local data
  local ServerSocket
  -- Local listen function
  local function OnListen (ErrorMessage)
    assert((ErrorMessage == nil), ErrorMessage)
    local ClientSocket = luv.new_tcp()
    ServerSocket:accept(ClientSocket)
    -- Local socket read function
    local function OnSocketRead (Error, Chunk)
      if Error then
        ClientSocket:close()
        return
      end
      if (not Chunk) then
        ClientSocket:close()
        return
      end
      local Request = stringtrim(Chunk)
      print(format("REQ:[%s]", Request))
      local CloseRequest, Response = RequestHandler(Request)
      ClientSocket:write(format("%s\n", Response))
      ClientSocket:shutdown()
      ClientSocket:close()
      if CloseRequest then
        luv.stop()
      end
    end
    -- Start reading from the client socket
    ClientSocket:read_start(OnSocketRead)
  end
  -- Create and listen on server socket
  ServerSocket = SafeSocket.createsafesocketandlisten("LUV", DEFAULT_HOST, Port, 128, OnListen)
  -- Log
  print(format("Server created on port %d (plain TCP)", Port))
  print("Ctrl+C to close the server")
  luv.run()
end

--------------------------------------------------------------------------------
-- SSL SERVER                                                                 --
--------------------------------------------------------------------------------

local function ServerSsl (Port, RequestHandler)
  local SslConfig    = Ssl.newconfig("tls-server")
  local ServerSocket = CreateServerSocket(DEFAULT_HOST, Port, HandleNewClient, SslConfig, RequestHandler)
  print(format("Server created on port %d (SSL)", Port))
  print("Ctrl+C to close the server")
  luv.run()
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