--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Test mini-httpd
-- * Static data
-- * SSE-Events
-- * chunked data
-- * websockets

--------------------------------------------------------------------------------
-- TESTS BOILERPLATE FOR PACKAGE.PATH                                         --
--------------------------------------------------------------------------------

-- This kind of code should not appear in the real use of ComEXE
--
-- Initialize package.path to include ..\lib\xxx because test libraries are in
-- this directory

local function TEST_UpdatePackagePath (RelativeDirectory)
  -- Retrieve package confiuration (file loadlib.c, function luaopen_package)
  local Configuration = package.config
  local LUA_DIRSEP    = Configuration:sub(1, 1)
  local LUA_PATH_SEP  = Configuration:sub(3, 3)
  local LUA_PATH_MARK = Configuration:sub(5, 5)
  -- Load required modules
  local Runtime   = require("com.runtime")
  local Directory = Runtime.getrelativepath(RelativeDirectory) -- relative to arg[0] directory
  -- Prepend path in a Linux/Windows compatible way
  package.path = string.format("%s%s%s.lua%s%s", Directory, LUA_DIRSEP, LUA_PATH_MARK, LUA_PATH_SEP, package.path)
end

TEST_UpdatePackagePath("../lib")

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime   = require("com.runtime")
local WebSocket = require("com.websocket")
local Json      = require("dkjson")
local http      = require("copas.http")
local ltn12     = require("ltn12")

local format       = string.format
local concat       = table.concat
local JsonEncode   = Json.encode
local LoadResource = Runtime.loadresource
local newwebsocket = WebSocket.newwebsocket

local OS = Runtime.getparam("OS")

--------------------------------------------------------------------------------
-- WIN32-SPECIFIC                                                             --
--------------------------------------------------------------------------------

local OpenBrowser

if (OS == "windows") then
  local Win32 = require("com.win32")
  OpenBrowser = Win32.openbrowser
else
  OpenBrowser = function (Uri)
    print(format("OpenBrowser: %s", Uri))
  end
end

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local TEST_MainHtml       = LoadResource("test.html")
local TEST_MainCss        = LoadResource("test.css")
local TEST_MainJavascript = LoadResource("test.js")

assert(TEST_MainHtml,       "Failed to load resource")
assert(TEST_MainCss,        "Failed to load resource")
assert(TEST_MainJavascript, "Failed to load resource")

--------------------------------------------------------------------------------
-- SERVER                                                                     --
--------------------------------------------------------------------------------

local function HELLO_CountdownTimer (Timer, Instance)
  -- Update count
  Instance.counter = (Instance.counter - 1)
  -- Counter went negative, time to stop
  if (Instance.counter < 0) then
    -- we let it reach 0, so SSE clients can receive the final value
    print(format("COUNTDOWN REACHED 0: CLOSING"))
    if Timer then
      Timer:cancel()
      Instance.timer = false
    end
    -- Stop the server via handle
    Instance.server:stop(Instance)
  end
end

local function HELLO_Thread (Server)
  -- Retrieve data
  local Options = Server.options
  -- Do something
  if (Options == "COUNTDOWN") then
    -- Useless: just to check the API is working
    print("COPAS THREAD: started")
  end
end

--------------------------------------------------------------------------------
-- SERVER                                                                     --
--------------------------------------------------------------------------------

local HeaderSseResponse = [[HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: close

]]

local function HELLO_HandleSse (Instance, Request)
  local Success, ErrorString = Request:send(HeaderSseResponse)
  local Continue = Success
  while Continue do
    -- JSON payload
    local Message = {
      count = Instance.counter
    }
    local JsonString     = JsonEncode(Message)
    Success, ErrorString = Request:send(format("data: %s\n\n", JsonString))
    if (not Success) then
      Continue = false
    else
      if (Instance.counter > 0) then
        Request:sleep(1)
      else
        Continue = false
      end
    end
  end
  -- Close socket
  Request:finish()
end

local function HELLO_HandleGetVariables (Request)
  -- Format JSON object
  local JsonObject = Request.parameters
  -- Format JSON
  local JsonString = JsonEncode(JsonObject)
  local Response   = Request:formatresponse(200, JsonString, nil, "application/json")
  -- Send response
  Request:send(Response)
  Request:finish()
end

local function HELLO_HandlePostFormData (Request)
  -- Parse form
  local Fields, Parts = Request:parseformdata()
  -- Format response
  local FormData = Fields
  -- Format JSON
  local JsonString = JsonEncode(FormData)
  local Response   = Request:formatresponse(200, JsonString, nil, "application/json")
  -- Send response
  Request:send(Response)
  Request:finish()
end

local function HELLO_HandlePostUrlEncodedForm (Request)
  -- Parse form
  local Fields, Parts = Request:parseformdata()
  -- Format JSON
  local JsonString = JsonEncode(Fields)
  local Response   = Request:formatresponse(200, JsonString, nil, "application/json")
  -- Send response
  Request:send(Response)
  Request:finish()
end

-- Create a function where each call will provide a new chunk from ChunkList
local function MakeChunkedSource (ChunkList)
  local ChunkIndex = 1
  local function ReadNextChunk()
    local ChunkString = ChunkList[ChunkIndex]
    ChunkIndex = (ChunkIndex + 1)
    return ChunkString
  end
  return ReadNextChunk
end

-- This is the starting point for the (tricky) chunked-data. We want to test
-- that mini-http handle properly the requests which are "chunked".
-- Specifically: "Transfer-Encoding: chunked".
--
-- The difficulty is that one cannot specify "Chunked" from the JavaScript. We
-- need another way to test, for simplicity, we trigger the test from the server
-- side. That's the point of this function, launch a new HTTP request which
-- is "chunked".
--
-- Here we cannot use socket.http because it would block Copas loop, we need to
-- use copas.http which is basically a wrapper.
local function HELLO_HandleChunkData (Instance, Request)
  -- local data
  -- test-chunk-data-receive simply return the body which has been received
  local UriSendChunk   = format("%s/test-chunk-data-receive", Instance.uri)
  local ResponseChunks = {}
  -- Test data
  local InputChunks = {
    "aaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "cccccccccccccccccccccc",
    "ddddddddddddddddddddddddddddddd",
    "e"
  }
  local HttpRequest = {
    url     = UriSendChunk,
    method  = "POST",
    headers = {
      ["transfer-encoding"] = "chunked",
    },
    source = MakeChunkedSource(InputChunks),
    sink   = ltn12.sink.table(ResponseChunks),
  }
  local Success, HttpCode, HttpHeaders, HttpStatus = http.request(HttpRequest)
  -- Format response
  local InputReference  = concat(InputChunks)
  local OutputReference = concat(ResponseChunks)
  local ReportSuccess  = (HttpCode == 200)
    and (InputReference == OutputReference)
  local JsonResponse = {
    Input      = InputReference,
    Output     = OutputReference,
    InputSize  = #InputReference,
    OutputSize = #OutputReference,
    Success    = ReportSuccess
  }
  -- Format JSON
  local JsonString = JsonEncode(JsonResponse)
  local Response   = Request:formatresponse(200, JsonString, nil, "application/json")
  -- Send response
  Request:send(Response)
  Request:finish()
end

-- Simply output the received data which has been "unchunked" by mini-httpd
local function HELLO_HandleChunkDataReceive (Request)
  -- Format JSON
  local JsonString = Request.data
  local Response   = Request:formatresponse(200, JsonString, nil, "application/json")
  -- Send response
  Request:send(Response)
  Request:finish()
end

-- Send back any message received
local function HELLO_HandleWebSocket (Instance, Request)
  local WebSocket, ErrorString = newwebsocket(Request)
  if WebSocket then
    print("WebSocket connection established")
    -- main loop
    while WebSocket:isopen() do
      local Payload, Opcode = WebSocket:receive()
      if Payload then
        -- Echo back the message with same opcode (text or binary)
        if (Opcode == 1) then
          WebSocket:sendtext(Payload)
        elseif (Opcode == 2) then
          WebSocket:sendbinary(Payload)
        end
      end
      WebSocket:sleep(0)
    end
    -- Tricky: when WebSocket:isopen() is false the underlying socket is not closed
    Request:finish()
    print("WebSocket connection closed")
  else
    print(format("WebSocket upgrade failed: %s", ErrorString))
    local Response = Request:formatresponse(400, "WebSocket upgrade failed", nil, "text/plain")
    Request:send(Response)
    Request:finish()
  end
end

local function HELLO_HandleExit (Instance, Request)
  print("GET /exit received: stopping server")
  -- Provide response
  local Response = Request:formatresponse(200, "OK", nil, "text/plain")
  Request:send(Response)
  Request:finish()
  -- Stop the server via handle
  Instance.server:stop(Instance)
end

local HELLO_STATIC_DATA = {
 ["/test.css"] =  { TEST_MainCss ,       "text/css"               },
 ["/test.js"]  =  { TEST_MainJavascript, "application/javascript" },
 ["/test.html"] = { TEST_MainHtml,       "text/html"              }
}

local function HELLO_MethodRequest (Instance, Request)
  local Method = Request.method
  local Path   = Request.path
  -- local data
  local StaticData
  local MimeType
  -- Check static data
  if (Method == "GET") then
    local Entry = HELLO_STATIC_DATA[Path]
    if Entry then
      StaticData = Entry[1]
      MimeType   = Entry[2]
    end
  end
  -- Handle static data
  if StaticData then
    local Response = Request:formatresponse(200, StaticData, nil, MimeType)
    Request:send(Response)
    Request:finish()
  elseif (Method == "GET") and (Path == "/sse") then
    HELLO_HandleSse(Instance, Request)
  elseif (Path == "/js-test-result") and ((Method == "GET") or (Method == "POST")) then
    -- Return a small JSON payload. If the client POSTs JSON we echo it back in the
    -- "echo" field (we assume it's already JSON). If no body is present, echo is null.
    TEST_TestState = "DONE"
    local Received = Request.data
    local EchoPart = Received and Received or "null"
    local Message  = format('{"status":"ok","echo":%s}', EchoPart)
    local Response = Request:formatresponse(200, Message, nil, "application/json")
    Request:send(Response)
    Request:finish()
  elseif (Method == "GET") and (Path == "/test-get-variables") then
    HELLO_HandleGetVariables(Request)
  elseif (Method == "POST") and (Path == "/test-post-urlencoded") then
    HELLO_HandlePostFormData(Request)
  elseif (Method == "POST") and (Path == "/test-post-urlencoded-form") then
    HELLO_HandlePostUrlEncodedForm(Request)
  elseif (Method == "GET") and (Path == "/test-chunk-data") then
    HELLO_HandleChunkData(Instance, Request)
  elseif (Method == "POST") and (Path == "/test-chunk-data-receive") then
    HELLO_HandleChunkDataReceive(Request)
  elseif (Method == "GET") and (Path == "/ws") then
    HELLO_HandleWebSocket(Instance, Request)
  elseif (Method == "GET") and (Path == "/exit") then
    HELLO_HandleExit(Instance, Request)
  else
    print(Method, Path, Request.httppath)
    local Response = Request:formatresponse(404, "", nil, "text/plain")
    Request:send(Response)
    Request:finish()
  end
end

local function HELLO_SpawnBrowser (Instance, Uri)
  -- Start the JavaScript test page in the browser
  TEST_TestState   = "ONGOING"
  local BrowserUri = format("%s/test.html", Uri)
  OpenBrowser(BrowserUri)
end

local function HELLO_HandleStartEvent (Instance)
  -- Counter to stop the server automatically
  local Server = Instance.server
  Server:newthread(HELLO_Thread, Server)
  -- Retrieve options
  local Options = Instance.options
  if (Options == "COUNTDOWN") then
    -- Create the timer
    local NewTimer = Server:newtimer(1, true, HELLO_CountdownTimer, Instance)
    Instance.timer = NewTimer
    -- Browser
    local Uri = Instance.uri
    print(format("SERVER RUNNING %s", Uri))
    HELLO_SpawnBrowser(Instance, Uri)
  end
end

local function HELLO_MethodEvent (Instance, EventType, Value)
  if (EventType == "Started") then
    Instance.uri = Value
    HELLO_HandleStartEvent(Instance)
  elseif (EventType == "Closed") then
    -- Cleanup resources
    local Timer = Instance.timer
    if Timer then
      Timer:cancel()
      Instance.timer = false
    end
  end
end

--------------------------------------------------------------------------------
-- CONSTRUCTOR                                                                --
--------------------------------------------------------------------------------

local function HELLO_NewHttpHandler (Server, UserOptions)
  local Options = (UserOptions or "COUNTDOWN")
  -- New server instance
  local NewHttpHandler = {
    -- private data
    server  = Server,
    uri     = false,
    counter = 8,
    options = Options,
    -- local methods
    request  = HELLO_MethodRequest,
    event    = HELLO_MethodEvent
  }
  -- Return value
  return NewHttpHandler
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

-- newserverapp provided a new server application for mini-httpd (factory pattern)
local PUBLIC_API = {
  newserverapp = HELLO_NewHttpHandler
}

return PUBLIC_API
