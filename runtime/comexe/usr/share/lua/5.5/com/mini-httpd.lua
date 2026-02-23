--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- Mini-httpd is not a HTTP server. It's a module with a few functions to
-- simplifiy the development of very simple, bugged, incomplete, trivial,
-- unefficient, single threaded, HTTP server.
--
-- This server is basically the integration of Copas loop with ComEXE event
-- loop.
--
-- The Copas server is stopped at the call of copas.removeserver(server), it
-- will prevent new incoming connections, but existing connections will continue
-- to be served until closed by the client or the server.
--
-- Keep-Alive behavior (HTTP/1.1):
--   HTTP/1.1 connections default to keep-alive unless "Connection: close"
--   HTTP/1.0 connections default to close unless "Connection: keep-alive"
--   Call finish() for normal requests, mini-httpd will close automatically when not keep-alive or upgraded
--   Call upgrade() for WebSockets
--
-- WebSocket Support:
--   Use com.websocket middleware module:
--     local WebSocket = require("com.websocket")
--     local Ws, Error = WebSocket.new(Request)

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime     = require("com.runtime")
local MiniHttpLib = require("com.mini-httpd-lib")
local LuaSocket   = require("socket")
local Copas       = require("copas")
local Event       = require("com.event")
local SslServer   = require("com.ssl-server")
local sslmod      = require("mbedtls.ssl")

local format        = string.format
local concat        = table.concat
local append        = Runtime.append
local hasprefix     = Runtime.hasprefix
local RunOnce       = Event.runonce
local step          = Copas.step
local pause         = Copas.pause
local finished      = Copas.finished
local wrap          = Copas.wrap
local addthread     = Copas.addthread
local timernew      = Copas.timer.new
local newconfig     = sslmod.newconfig
local newconfig_mem = sslmod.newconfig_mem
local sslwrap       = SslServer.wrap

local parserequestline    = MiniHttpLib.parserequestline
local parserequesttarget  = MiniHttpLib.parserequesttarget
local formatresponse      = MiniHttpLib.formatresponse
local parseheaderline     = MiniHttpLib.parseheaderline
local parseheadervalue    = MiniHttpLib.parseheadervalue
local parseformdata       = MiniHttpLib.parseformdata
local parseurlencodedform = MiniHttpLib.parseurlencodedform
local parsechunkeddata    = MiniHttpLib.parsechunkeddata

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local SERVER_SOCKET_BACKLOG    =  64 -- Maximum number of pending connections
local SERVER_KEEPALIVE_TIMEOUT =  15 -- Seconds to wait for next request on keep-alive
local SERVER_KEEPALIVE_MAXREQS = 100 -- Maximum requests per keep-alive connection

--------------------------------------------------------------------------------
-- SERVER TYPE                                                                --
--------------------------------------------------------------------------------

local function SERVER_ReadHeaders (Client)
  -- Read HTTP request headers
  local HttpHeaders = {}
  local HeadersDone = false
  repeat
    local Line, ErrorMessage = Client:receive("*l")
    if ErrorMessage or (not Line) or (Line == "") then
      HeadersDone = true
    else
      local Key, Value = parseheaderline(Line)
      if (Key and Value) then
        HttpHeaders[Key] = Value
      end
    end
  until HeadersDone
  -- Return value
  return HttpHeaders
end

-- Read HTTP request encoded with "Transfer-Encoding: chunked"
-- Can be tested with curl
-- curl -H "Transfer-Encoding: chunked" -d @test.bin --request POST http://127.0.0.1:8801/test-chunk-data-receive -vv
local function SERVER_ReadChunkedBody (Client)
  local Chunks = {}
  -- Read from socket
  local function SocketReadFunction (Parameter)
    local Data
    if (Parameter == "l") then
      Data = Client:receive("*l")
    else
      Data = Client:receive(Parameter)
    end
    return Data
  end
  local function ReceiveChunkFunction (ChunkData)
    append(Chunks, ChunkData)
  end
  -- Call API
  parsechunkeddata(SocketReadFunction, ReceiveChunkFunction)
  -- Return value
  local DataString = concat(Chunks)
  return DataString
end

local function SERVER_ReadBody (Client, Headers)
  local ContentLengthHeader = Headers["content-length"]
  local ContentLength       = tonumber(ContentLengthHeader)
  local TransferEncoding
  local ContentData
  -- Handle Content-Length when present
  if ContentLength and (ContentLength > 0) then
    local Data = Client:receive(ContentLength)
    if Data then
      ContentData = Data
    end
  else
    -- Handle chunked data
    TransferEncoding = Headers["transfer-encoding"]
    if TransferEncoding then
      TransferEncoding = TransferEncoding:lower()
      if (TransferEncoding == "chunked") then
        ContentData = SERVER_ReadChunkedBody(Client)
      end
    end
  end
  -- Return value
  return ContentData
end

local function REQUEST_MethodParseFormData (Request)
  -- Retrieve data
  local Data = Request.data
  local Parts
  local Form
  -- Check for multipart/form-data
  if Data then
    local Headers     = Request.headers
    local ContentType = Headers["content-type"]
    if ContentType then
      if hasprefix(ContentType, "multipart/form-data") then
        local Value, Parameters = Request:parseheadervalue(ContentType)
        local Boundary          = Parameters.boundary
        if Boundary then
          Parts, Form = parseformdata(Data, Boundary)
        end
      elseif hasprefix(ContentType, "application/x-www-form-urlencoded") then
        Form = parseurlencodedform(Data)
      end
    end
  end
  -- Return value
  return Form, Parts
end

-- Determine if connection should be kept alive based on HTTP version and headers
-- HTTP/1.1 defaults to keep-alive, HTTP/1.0 defaults to close
local function SERVER_ShouldKeepAlive (Version, Headers)
  local ConnectionHeader = Headers["connection"]
  local KeepAlive
  if ConnectionHeader then
    local LowerConnection = ConnectionHeader:lower()
    if (LowerConnection == "close") then
      KeepAlive = false
    elseif (LowerConnection == "keep-alive") then
      KeepAlive = true
    elseif (LowerConnection == "upgrade") then
      -- HTTP upgrade like websocket should not be keep-alive
      KeepAlive = false
    else
      -- Default based on HTTP version
      KeepAlive = (Version == "HTTP/1.1")
    end
  else
    -- No Connection header: HTTP/1.1 defaults to keep-alive
    KeepAlive = (Version == "HTTP/1.1")
  end
  return KeepAlive
end

local function SERVER_BuildRequest (Client, Method, HttpPath, Version, Headers, ContentData, KeepAliveRemaining)
  local Path
  local QueryString
  local Parameters
  if HttpPath then
    Path, QueryString, Parameters = parserequesttarget(HttpPath)
  end
  local ClientIp
  local ClientPort
  local Family
  local PeerSuccess, PeerPort, PeerFamily = Client:getpeername()
  if PeerSuccess then
    ClientIp   = PeerSuccess
    ClientPort = PeerPort
    Family     = PeerFamily
  end
  -- Keep-alive state
  -- If we are about to reach the server-side keep-alive max requests limit,
  -- force a clean close on this response. This ensures the response advertises
  -- "Connection: close", so clients won't attempt to pipeline/reuse a socket
  -- that the server will close immediately after serving this request.
  local RequestKeepAlive = (KeepAliveRemaining > 1) and SERVER_ShouldKeepAlive(Version, Headers)
  local RequestClosed    = false
  local RequestUpgraded  = false
  -- Methods
  local function MethodFormatResponse (Request, HttpCode, Content, UserHeaders, ContentType)
    -- Add Connection header based on keep-alive state
    local ResponseHeaders = (UserHeaders or {})
    if (not ResponseHeaders["Connection"]) then
      if RequestKeepAlive then
        ResponseHeaders["Connection"] = "keep-alive"
      else
        ResponseHeaders["Connection"] = "close"
      end
    end
    return formatresponse(HttpCode, Content, ResponseHeaders, ContentType)
  end
  local function MethodParseheaderValue (Request, HeaderValue)
    return parseheadervalue(HeaderValue)
  end
  local function MethodSetTimeout (Request, TimeoutSec)
    Client:settimeout(TimeoutSec)
  end
  local function MethodSend (Request, Data)
    local Success, ErrorMessage = Client:send(Data)
    if (not Success) then
      print("Server:Send Error", ErrorMessage)
    end
    return Success, ErrorMessage
  end
  -- finish() signals request is done.
  -- If keep-alive is enabled, the connection stays open for the next request
  -- unless the connection was marked non-keep-alive or was upgraded (WebSocket).
  local function MethodFinish (Request)
    local ShouldClose = ((not RequestKeepAlive) or RequestUpgraded) and (not RequestClosed)
    if ShouldClose then
      local Success, ErrorMessage = Client:close()
      if (not Success) then
        print("Server:Close Error", ErrorMessage)
      end
      RequestClosed = true
    end
  end
  -- upgrade() marks connection as upgraded (e.g., WebSocket)
  local function MethodUpgrade (Request)
    RequestUpgraded = true
  end
  local function MethodSleep (Request, Seconds)
    pause(Seconds)
  end
  local function MethodReceive (Request, Pattern)
    local Data, ErrorMessage = Client:receive(Pattern)
    return Data, ErrorMessage
  end
  -- Getter functions for internal state
  local function MethodIsClosed (Request)
    return RequestClosed
  end
  local function MethodIsUpgraded (Request)
    return RequestUpgraded
  end
  local function MethodIsKeepAlive (Request)
    return RequestKeepAlive
  end
  -- Create a new request object
  local NewRequest = {
    -- data
    clientip     = ClientIp,
    clientport   = ClientPort,
    clientfamily = Family,
    method       = Method,
    httppath     = HttpPath,
    version      = Version,
    headers      = Headers,
    path         = Path,
    querystring  = QueryString,
    parameters   = Parameters,
    data         = ContentData,
    keepalive    = RequestKeepAlive,
    -- methods
    formatresponse   = MethodFormatResponse,
    parseheadervalue = MethodParseheaderValue,
    parseformdata    = REQUEST_MethodParseFormData,
    settimeout       = MethodSetTimeout,
    send             = MethodSend,
    receive          = MethodReceive,
    sleep            = MethodSleep,
    yield            = MethodSleep,
    finish           = MethodFinish,
    upgrade          = MethodUpgrade,
    isclosed         = MethodIsClosed,
    isupgraded       = MethodIsUpgraded,
    iskeepalive      = MethodIsKeepAlive,
  }
  return NewRequest
end

local function SERVER_ConfigUseSsl (Config)
  local UseSsl = (Config.cert or Config.key or Config.certkeyfile)
  return UseSsl
end

local function SERVER_HandleHandshake (ServerEntry, Client)
  local WrappedClient = Client
  local Continue      = true
  local Config        = ServerEntry.config
  local UseSsl        = SERVER_ConfigUseSsl(Config)
  if UseSsl then
    -- Retrieve mbedtls SSL config
    local SslConfig = ServerEntry.sslconfig
    -- Create SSL config on first connection (cached for reuse)
    if (not SslConfig) then
      local CertPem     = Config["cert"]
      local KeyPem      = Config["key"]
      local CertKeyFile = Config["certkeyfile"]
      if CertKeyFile then
        SslConfig = newconfig("tls-server", nil, CertKeyFile)
      elseif (CertPem and KeyPem) then
        SslConfig = newconfig_mem("tls-server", nil, CertPem, KeyPem)
      else
        SslConfig = newconfig("tls-server")
      end
      assert(SslConfig, "mini-httpd: cannot create ssl server config")
      -- Save config
      ServerEntry.sslconfig = SslConfig
    end
    local ClientOrError, ErrorMessage = sslwrap(Client, SslConfig, ServerEntry)
    if ClientOrError then
      WrappedClient = ClientOrError
    else
      print(format("mini-httpd: SSL wrap failed: %q", ErrorMessage))
      Client:close()
      Continue = false
    end
  else
    WrappedClient = wrap(Client)
  end
  -- return value
  return WrappedClient, Continue
end

local function SERVER_StartKeepAliveTimer (WrappedClient, RequestCount)
  local KeepAliveTimer
  local TimerOptions = {
    delay     = SERVER_KEEPALIVE_TIMEOUT,
    recurring = false,
    callback  = function (Timer, UserData)
      WrappedClient:close()
    end
  }
  KeepAliveTimer = timernew(TimerOptions)
  return KeepAliveTimer
end

local function SERVER_CopasClientHandler (ServerEntry, Client)
  local WrappedClient, HandshakeOk = SERVER_HandleHandshake(ServerEntry, Client)
  local KeepAliveRemaining
  if HandshakeOk then
    KeepAliveRemaining = SERVER_KEEPALIVE_MAXREQS
  else
    KeepAliveRemaining = 0
  end
  local RequestCount = 0
  while (KeepAliveRemaining > 0) do
    -- Read request line
    local KeepAliveTimer = SERVER_StartKeepAliveTimer(WrappedClient, RequestCount)
    local RequestLine, ReceiveError = WrappedClient:receive("*l")
    KeepAliveTimer:cancel()
    -- Parse request
    local Method
    local HttpPath
    local Version
    if RequestLine then
      Method, HttpPath, Version = parserequestline(RequestLine)
    elseif (ReceiveError ~= "closed") and (ReceiveError ~= "close-notify") then
      -- close-notify sent by the client during SSL shutdown
      print(format("# WARNING: invalid request line %q %q", RequestLine, ReceiveError))
    end
    if Method and HttpPath and Version then
      -- Process request
      local Headers     = SERVER_ReadHeaders(WrappedClient)
      local ContentData = SERVER_ReadBody(WrappedClient, Headers)
      local Request     = SERVER_BuildRequest(WrappedClient, Method, HttpPath, Version, Headers, ContentData, KeepAliveRemaining)
      local ServerApp   = ServerEntry.serverapp
      -- Delegate request
      ServerApp:request(Request)
      -- Update counters
      RequestCount       = (RequestCount + 1)
      KeepAliveRemaining = (KeepAliveRemaining - 1)
      -- Determine if socket must be closed (preserve existing behavior)
      local ShouldClose = (not Request:iskeepalive()) or (KeepAliveRemaining <= 0)
      local ShouldExit  = (ShouldClose or Request:isupgraded() or Request:isclosed())
      if ShouldClose and (not Request:isclosed()) then
        WrappedClient:close()
      end
      if ShouldExit then
        KeepAliveRemaining = 0
      end
    else
      -- Invalid or empty request line (timeout or client closed)
      KeepAliveRemaining = 0
      WrappedClient:close()
    end
  end
end

local function SERVER_Start (ServerEntry, BindHost, Port)
  -- Create the server socket
  local NewServerSocket = LuaSocket.tcp()
  NewServerSocket:setoption("reuseaddr", true)
  local BindSuccess, ErrorString = NewServerSocket:bind(BindHost, Port)
  local NewUri
  if BindSuccess then
    local ListenSuccess, ListenErrorString = NewServerSocket:listen(SERVER_SOCKET_BACKLOG)
    if ListenSuccess then
      local function CopasCallback (Client)
        SERVER_CopasClientHandler(ServerEntry, Client)
      end
      Copas.addserver(NewServerSocket, CopasCallback)
      -- Format URI
      local Address, RealPort = NewServerSocket:getsockname()
      if SERVER_ConfigUseSsl(ServerEntry.config) then
        NewUri = format("https://%s:%d", Address, RealPort)
      else
        NewUri = format("http://%s:%d", Address, RealPort)
      end
    else
      ErrorString     = ListenErrorString
      NewServerSocket = false
    end
  else
    NewServerSocket = false
  end
  -- Return value
  return NewServerSocket, NewUri, ErrorString
end

local function SERVER_Stop (ServerEntry)
  if (ServerEntry.state ~= "STOPPED") then
    -- Retrieve data
    local ServerSocket = ServerEntry.socket
    local ServerApp    = ServerEntry.serverapp
    -- Stop the server, close socket and notify
    Copas.removeserver(ServerSocket)
    ServerSocket:close()
    ServerApp:event("Closed", nil)
    -- Update state
    ServerEntry.state     = "STOPPED"
    ServerEntry.socket    = false
    ServerEntry.sslconfig = false
  end
end

--------------------------------------------------------------------------------
-- SERVER METHODS                                                             --
--------------------------------------------------------------------------------

-- HTTPD_Bind takes SslOptions and a ServerApp
--
-- SslOptions can contain:
--   host        - bind host (required)
--   port        - bind port (required)
--   ssl         - true to enable SSL (optional, inferred if cert/key/certkeyfile present)
--   cert        - PEM certificate string
--   key         - PEM key string
--   certkeyfile - path to combined cert+key file
--
-- ServerApp must expose:
--   request(ServerApp, Request) - handle HTTP request
--   event(ServerApp, EventType, Value) - receive server events (Started, Closed)
--
local function HTTPD_Bind (Server, SslOptions, HttpHandler)
  -- Validate ServerApp
  assert(type(HttpHandler) == "table", "mini-httpd: ServerApp must be a table")
  assert(type(HttpHandler.request) == "function", "mini-httpd: ServerApp must expose request method")
  assert(type(HttpHandler.event) == "function", "mini-httpd: ServerApp must expose event method")
  -- Create the new entry
  local NewServerEntry = {
    serverapp = HttpHandler,
    config    = SslOptions,
    socket    = false,
    sslconfig = false,
    state     = "INIT",
  }
  -- Register in the main server
  local Entries = Server.entries
  Entries[HttpHandler] = NewServerEntry
end

local function HTTPD_MethodListen (Server, HttpHandler)
  local ServerEntry = Server.entries[HttpHandler]
  assert(ServerEntry, "mini-httpd: application not bound")
  local SslOptions = ServerEntry.config
  local Host = SslOptions["host"]
  local Port = SslOptions["port"]
  assert(Host, "mini-httpd: listen requires host in config")
  assert(Port, "mini-httpd: listen requires port in config")
  local ServerSocket, Uri, ErrorString = SERVER_Start(ServerEntry, Host, Port)
  ServerEntry.socket = ServerSocket
  if ServerSocket then
    ServerEntry.state = "RUNNING"
    HttpHandler:event("Started", Uri)
  end
  local Success = (ServerSocket ~= nil)
  return Success, ErrorString
end

local function HTTPD_MethodStop (Server, HttpHandler)
  local ServerEntry = Server.entries[HttpHandler]
  SERVER_Stop(ServerEntry)
end

local function HTTPD_MethodRunLoop (Server)
  local Continue = true
  while Continue do
    step()
    RunOnce()
    Continue = (not finished())
  end
end

local function HTTPD_MethodNewThread (Server, Callback, UserData)
  addthread(Callback, UserData)
end

local function HTTPD_MethodNewTimer (Server, DurationSec, IsRecurring, Callback, UserData)
  -- Validate inputs
  assert(type(DurationSec) == "number")
  assert(type(IsRecurring) == "boolean")
  assert(type(Callback) == "function")
  -- Create the Copas timer data
  local NewTimerOptions = {
    delay     = DurationSec,
    recurring = IsRecurring,
    callback  = Callback,
    params    = UserData
  }
  -- Create the Copas timer
  local NewCopasTimer = timernew(NewTimerOptions)
  -- Return the timer
  return NewCopasTimer
end

local function HTTPD_MethodSleep (Server, Seconds)
  pause(Seconds)
end

--------------------------------------------------------------------------------
-- CONSTRUCTOR                                                                --
--------------------------------------------------------------------------------

local function HTTPD_NewServer ()
  -- Create the main server object
  local NewServer = {
    -- private data
    entries = {},
    -- methods
    bind      = HTTPD_Bind,
    listen    = HTTPD_MethodListen,
    stop      = HTTPD_MethodStop,
    runloop   = HTTPD_MethodRunLoop,
    newthread = HTTPD_MethodNewThread,
    newtimer  = HTTPD_MethodNewTimer,
    sleep     = HTTPD_MethodSleep,
  }
  -- Return value
  return NewServer
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  newserver = HTTPD_NewServer,
}

return PUBLIC_API