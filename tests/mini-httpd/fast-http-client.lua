--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- FastHttpClient: fast in the sense that it maintain connection KeepAlive
--
-- A wrapper for HTTP request functions that maintains persistent connections
-- to avoid SSL/TLS handshake overhead on repeated requests to the same host.
--
-- Limitation: just support 1 scheme/host/port at a time
-- It will automatically update its single socket when changing scheme/host/port
--
-- Usage:
--   local Wrapper = require("fast-http-client")
--   local Keeper  = Wrapper.newkeepalive(socket.http.request)
--   local Body, Code = Keeper:http(Url)
--   local Body, Code = Keeper:http(Url) -- reuses same connection
--   Keeper:close()

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local socket      = require("socket")
local ssl         = require("ssl")
local url         = require("socket.url")
local MiniHttpLib = require("com.mini-httpd-lib")

local format = string.format
local concat = table.concat
local append = table.insert

local parseheaderline  = MiniHttpLib.parseheaderline
local parseheadervalue = MiniHttpLib.parseheadervalue
local parsechunkeddata = MiniHttpLib.parsechunkeddata
local tcp              = socket.tcp
local wrap             = ssl.wrap
local parse            = url.parse

--------------------------------------------------------------------------------
-- IMPORTED FUNCTIONS (DUPLICATED FROM mini-http.lua)                         --
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

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function KA_CloseConnection (Wrapper)
  -- Close existing connection if any
  local Socket = Wrapper.Socket
  if Socket then
    Socket:close()
  end
  -- Reset state
  Wrapper.Socket = false
  Wrapper.Scheme = false
  Wrapper.Host   = false
  Wrapper.Port   = false
end

local function KA_CreateTcpSocket (Host, Port, TimeoutSeconds)
  -- Create a new TCP connection
  local NewSocket = tcp()
  local Result
  if NewSocket then
    NewSocket:settimeout(TimeoutSeconds)
    local Success, ErrorString = NewSocket:connect(Host, Port)
    if Success then
      Result = NewSocket
    else
      NewSocket:close()
    end
  end
  return Result
end

-- Wrap a socket and perform SSL handshake
local function KA_WrapSocket (Socket, Host)
  local SslParams = {
    mode     = "client",
    protocol = "any",
    verify   = "none",
    options  = "all",
  }
  local WrappedSocket = wrap(Socket, SslParams)
  local Result
  if WrappedSocket then
    WrappedSocket:sni(Host)
    local Success = WrappedSocket:dohandshake()
    if Success then
      Result = WrappedSocket
    else
      WrappedSocket:close()
    end
  end
  return Result
end

local function KA_EnsureConnection (Wrapper, UrlParsed)
  -- Ensure we have a valid connection to the target host
  local Scheme = UrlParsed.scheme
  local Host   = UrlParsed.host
  local Port   = tonumber(UrlParsed.port)
  local Result = true
  -- Determine default port based on scheme
  if (Port == nil) then
    if (Scheme == "https") then
      Port = 443
    else
      Port = 80
    end
  end
  -- Check if we need a new connection
  local NeedNewConnection = (Wrapper.Socket == nil)
      or (Wrapper.Scheme ~= Scheme)
      or (Wrapper.Host ~= Host)
      or (Wrapper.Port ~= Port)
  if NeedNewConnection then
    -- Close existing connection
    KA_CloseConnection(Wrapper)
    -- Create new TCP connection
    local NewSocket = KA_CreateTcpSocket(Host, Port, Wrapper.Timeout)
    if NewSocket then
      local Socket
      if (Scheme == "https") then
        Socket = KA_WrapSocket(NewSocket, Host)
        if (Socket == nil) then
          NewSocket:close()
        end
      else
        Socket = NewSocket
      end
      -- Socket is either a plain TCP socket or a wrapped socket
      if Socket then
        Wrapper.Socket = Socket
        Wrapper.Scheme = Scheme
        Wrapper.Host   = Host
        Wrapper.Port   = Port
      else
        Result = false
      end
    else
      Result = false
    end
  end
  return Result
end

local function KA_BuildRequestString (Method, Path, Host, Headers, Body)
  -- Build HTTP request string
  local Lines   = {}
  local Request = format("%s %s HTTP/1.1", Method, Path)
  append(Lines, Request)
  append(Lines, format("Host: %s", Host))
  append(Lines, "Connection: keep-alive")
  -- Add custom headers
  if Headers then
    for Key, Value in pairs(Headers) do
      local LowerKey = Key:lower()
      if (LowerKey ~= "host") and (LowerKey ~= "connection") then
        append(Lines, format("%s: %s", Key, Value))
      end
    end
  end
  -- Add Content-Length for body
  if Body and (#Body > 0) then
    append(Lines, format("Content-Length: %d", #Body))
  else
    Body = ""
  end
  append(Lines, "")
  append(Lines, Body)
  -- Format request string
  local ResultString = concat(Lines, "\r\n")
  return ResultString
end

local function KA_ReadAndParseStatusLine (Socket)
  local Line, Err = Socket:receive("*l")
  if not Line then return nil, Err end
  local HttpVersion, HttpCodeString, Reason = Line:match("^(HTTP/%d%.%d)%s+(%d+)%s*(.*)")
  local HttpCodeNumber
  if HttpCodeString then
    HttpCodeNumber = tonumber(HttpCodeString)
  end
  return HttpVersion, HttpCodeNumber, Reason
end

local function KA_ReadResponse (Wrapper)
  -- Retrieve data
  local Socket = Wrapper.Socket
  -- Initialize return values with defaults
  local Body        = nil
  local Headers     = nil
  local ErrorString = nil
  -- Read and parse status line
  local HttpVersion, HttpCode, Reason = KA_ReadAndParseStatusLine(Socket)
  if (not HttpCode) then
    KA_CloseConnection(Wrapper)
    ErrorString = "Invalid status line"
  else
    Headers = SERVER_ReadHeaders(Socket)
    if (not Headers) then
      KA_CloseConnection(Wrapper)
      ErrorString = "Failed to read headers"
    else
      -- Determine keep-alive
      local KeepAlive
      local Connection = Headers["connection"]
      if Connection and (parseheadervalue(Connection) == "close") then
        KeepAlive = false
      else
        KeepAlive = true
      end
      -- Read response body
      Body, ErrorString = SERVER_ReadBody(Socket, Headers)
      -- Close connection if needed
      if ErrorString or (not KeepAlive) then
        KA_CloseConnection(Wrapper)
      end
    end
  end
  -- Return value
  return Body, HttpCode, Headers, ErrorString
end

--------------------------------------------------------------------------------
-- METHODS                                                                    --
--------------------------------------------------------------------------------

-- Send a single HTTP request and return the response
local function KA_DoRequest (Wrapper, RequestMethod, Path, Host, Headers, Body)
  -- Prepare
  local RequestString = KA_BuildRequestString(RequestMethod, Path, Host, Headers, Body)
  -- Retrieve data 
  local Socket = Wrapper.Socket
  -- Send request 
  local LastByteIndex, ErrorString = Socket:send(RequestString)
  local ResponseBody
  local ResponseCode
  local ResponseHeaders
  if LastByteIndex then
    ResponseBody, ResponseCode, ResponseHeaders, ErrorString = KA_ReadResponse(Wrapper)
  else
    ResponseBody    = false
    ResponseCode    = false
    ResponseHeaders = false
    KA_CloseConnection(Wrapper)
  end
  -- Return values
  return ResponseBody, ResponseCode, ResponseHeaders, ErrorString
end

-- Perform HTTP request with keep-alive
local function KA_MethodHttp (Wrapper, Uri, Method, Headers, Body)
  -- Parse uri
  local Parsed          = parse(Uri)
  local ResponseBody    = nil
  local ResponseCode    = nil
  local ResponseHeaders = nil
  local ErrorString     = nil
  -- Handle URI
  if Parsed and Parsed.host then
    if KA_EnsureConnection(Wrapper, Parsed) then
      local RequestHost   = Parsed.host
      local RequestMethod = (Method or "GET")
      local RequestPath   = (Parsed.path or "/")
      if Parsed.query then
        RequestPath = format("%s?%s", RequestPath, Parsed.query)
      end
      -- Send request and read response
      ResponseBody, ResponseCode, ResponseHeaders, ErrorString = KA_DoRequest(Wrapper, RequestMethod, RequestPath, RequestHost, Headers, Body)
      local ShouldRetry = ((RequestMethod == "GET") or (RequestMethod == "HEAD"))
          and (ResponseCode == nil)
          and ((ErrorString == "closed")
            or (ErrorString == "close-notify")
            or (ErrorString == "invalid read result"))
      if ShouldRetry then
        if KA_EnsureConnection(Wrapper, Parsed) then
          ResponseBody, ResponseCode, ResponseHeaders, ErrorString = KA_DoRequest(Wrapper, RequestMethod, RequestPath, RequestHost, Headers, Body)
        else
          ErrorString = "Failed to connect"
        end
      end
    else
      ErrorString = "Failed to connect"
    end
  else
    ErrorString = "Invalid URL"
  end
  -- Return values
  return ResponseBody, ResponseCode, ResponseHeaders, ErrorString
end

local function KA_MethodClose (Wrapper)
  KA_CloseConnection(Wrapper) -- Close the current keep-alive connection
end

local function KA_NewHttpClient (OptionalTimeoutSeconds)
  -- Create new KeepAlive wrapper object
  local NewWrapper = {
    -- data
    Timeout = (OptionalTimeoutSeconds or 30),
    Socket  = false,
    Scheme  = false,
    Host    = false,
    Port    = false,
    -- Methods
    http  = KA_MethodHttp,
    close = KA_MethodClose,
  }
  -- Return value
  return NewWrapper
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  newhttpclient = KA_NewHttpClient,
}

return PUBLIC_API