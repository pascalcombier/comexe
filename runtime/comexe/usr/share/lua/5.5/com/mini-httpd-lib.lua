--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Initially, those functions were located in mini-httpd.lua, but it was making
-- automatic testing more difficult. So we have those functions in a dedicated
-- file.

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")
local Url     = require("socket.url")

local format     = string.format
local concat     = table.concat
local unescape   = Url.unescape
local append     = Runtime.append
local stringtrim = Runtime.stringtrim

--------------------------------------------------------------------------------
-- URL-ENCODED FORM                                                           --
--------------------------------------------------------------------------------

-- Parse a application/x-www-form-urlencoded body into a simple dict
-- Note that multiple keys will overwrite previous values
local function HTTP_ParseUrlEncodedForm (Data)
  -- local data
  local Fields = {}
  -- Iterate on key=value pairs separated by '&'
  for Key, Value in Data:gmatch("([^&=]+)=([^&]*)") do
    -- Replace '+' with space following application/x-www-form-urlencoded rules
    local CleanKey   = Key:gsub("%+", " ")
    local CleanValue = Value:gsub("%+", " ")
    -- Percent-decode
    local UnescapedKey   = unescape(CleanKey)
    local UnescapedValue = unescape(CleanValue)
    -- Store value
    if (UnescapedKey ~= "") then
      Fields[UnescapedKey] = UnescapedValue
    end
  end
  return Fields
end

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

--- Parses the HTTP request line and extracts the method, path, and version.
--
--   local method, path, version = SERVER_ParseHttpRequestLine("GET /hello?x=1 HTTP/1.1")
--   - method  == "GET"
--   - path    == "/hello?x=1"
--   - version == "HTTP/1.1"
local function HTTP_ParseHttpRequestLine (Request)
  local Method, Target, Version = Request:match("^%s*(%S+)%s+(%S+)%s+(%S+)")
  return Method, Target, Version
end

-- Parse the Path got in SERVER_ParseHttpRequestLine
-- Example:
--   local path, query, params = SERVER_ParseUrl("/hello/world?foo=bar&baz=42")
--   - path   == "/hello/world"
--   - query  == "foo=bar&baz=42"
--   - params == { foo = "bar", baz = "42" }
local function HTTP_ParseHttpPath (Path)
  local QueryString = ""
  local Parameters  = {}
  local PathPart, QueryPart = Path:match("^([^%?]*)%??(.*)$")
  if PathPart then
    Path = PathPart
  end
  if (QueryPart and QueryPart ~= "") then
    QueryString = QueryPart
    Parameters  = HTTP_ParseUrlEncodedForm(QueryPart)
  end
  return Path, QueryString, Parameters
end

--------------------------------------------------------------------------------
-- HEADER PARSING                                                             --
--------------------------------------------------------------------------------

-- Simply split a header line and return key and value
-- Value could nil
local function HTTP_ParseHeaderLine (HeaderLine)
  local Key, Value = HeaderLine:match("^(.-):%s*(.*)$")
  if Key then
    Key = Key:lower()
  end
  return Key, Value
end

-- Parse a header *value* string like
--  "multipart/form-data; charset=UTF-8; boundary="----WebKitFormBoundary7xqcng04Y1s7WWtQ"
--
-- Some parameter don't have value, this concept is named "Flag" below
-- "value; param;"
local function HTTP_ParseHeaderValue (HeaderString)
  -- Local data
  local Parameters = {}
  -- Allow UTF in headers
  -- To handle RFC 5987 and RFC 8187
  -- Extended value is always *not* quoted
  local function StoreParam (KeyLower, ValueClean)
    if (KeyLower:sub(-1) == "*") then
      local BaseKey = KeyLower:sub(1, -2)
      local Charset, EncodedValue = ValueClean:match("^([^']*)'%w*'(.*)$")
      if EncodedValue then
        -- Treated as URL encoded
        Parameters[BaseKey] = unescape(EncodedValue)
      else
        Parameters[BaseKey] = ValueClean
      end
    else
      Parameters[KeyLower] = ValueClean
    end
  end
  -- Split main value and parameter section
  local Length      = #HeaderString
  local PlainOption = true
  local SemiColon   = HeaderString:find(";", 1, PlainOption)
  local CurrentIndex
  local MainValue
  if SemiColon then
    -- Calculate offsets
    local FirstCharacter = 1
    local LastCharacter  = (SemiColon - 1)
    local ValueString    = HeaderString:sub(FirstCharacter, LastCharacter)
    -- Extract value
    MainValue    = stringtrim(ValueString)
    CurrentIndex = (SemiColon + 1)
  else
    MainValue    = stringtrim(HeaderString)
    CurrentIndex = (Length + 1)
  end
  -- Lower-case
  MainValue = MainValue:lower()
  -- Parse parameters
  while (CurrentIndex <= Length) do
    local ParamEnd = HeaderString:find("[=;]", CurrentIndex)
    if (not ParamEnd) then
      -- Special case: ending flag (no value and no semicolon)
      local Tail = HeaderString:sub(CurrentIndex)
      local Key  = stringtrim(Tail)
      if (Key ~= "") then
        local LowerKey = Key:lower()
        Parameters[LowerKey] = true
      end
      CurrentIndex = (Length + 1)
    else
      -- Usual case: key=value or flag
      -- Determine separator: either '=' or ';'
      local Separator   = HeaderString:sub(ParamEnd, ParamEnd)
      local StringStart = CurrentIndex
      local StringEnd   = (ParamEnd - 1)
      local KeyString   = HeaderString:sub(StringStart, StringEnd)
      local Key         = stringtrim(KeyString)
      if (Key == "") then
        -- Maltformed: ignore and skip to next parameter
        if (Separator == ";") then
          CurrentIndex = (ParamEnd + 1)
        else
          -- Malformed: ignore and resume at following ";"
          CurrentIndex = HeaderString:find(";", ParamEnd)
          if (not CurrentIndex) then
            CurrentIndex = (Length + 1)
          end
        end
      else
        -- We have a valid key, lower case just in case
        local KeyLower = Key:lower()
        -- The key has no value, it's just a flag
        if (Separator == ";") then
          Parameters[KeyLower] = true
          CurrentIndex = (ParamEnd + 1)
        else
          -- Separator is '='
          local ValueStart = (ParamEnd + 1)
          local Semicolon  = HeaderString:find(";", ValueStart, true)
          local ValueEnd
          if Semicolon then
            ValueEnd = (Semicolon - 1)
          else
            ValueEnd = (Length + 1)
          end
          -- Extract value
          local ValueString = HeaderString:sub(ValueStart, ValueEnd)
          local CleanValue  = stringtrim(ValueString)
          -- Optional: unquote values like "..." or '...'
          local First = CleanValue:sub(1, 1)
          local Last  = CleanValue:sub(-1, -1)
          if ((First == '"' or First == "'") and (Last == First)) then
            -- Handle escaped characters
            local Content = CleanValue:sub(2, -2)
            CleanValue = Content:gsub("\\(.)", "%1")
          end
          StoreParam(KeyLower, CleanValue)
          if Semicolon then
            CurrentIndex = (Semicolon + 1)
          else
            CurrentIndex = (Length + 1)
          end
        end
      end
    end
  end
  -- Return values
  return MainValue, Parameters
end

-- Parse a multipart/form-data body into a list of parts and a simple fields map.
-- Uses SERVER_ParseHeaderString to parse each part's headers (including RFC 5987/8187).
-- Returns Parts (array of { headers, name, filename, contenttype, value }) and Fields map.
--
-- This function is *strict* and need CRLF
--
-- --BOUNDARY\r\n
-- Header1\r\n
-- HeaderN\r\n
-- \r\n
-- Value\r\n
-- --BOUNDARY--\r\n
--
-- Example:
-- ------WebKitFormBoundaryR8CAMX0kdGB8YEpu
-- Content-Disposition: form-data; name="foo"
-- 
-- bar
-- ------WebKitFormBoundaryR8CAMX0kdGB8YEpu
-- Content-Disposition: form-data; name="num"
-- 
-- 123
-- ------WebKitFormBoundaryR8CAMX0kdGB8YEpu--\r\n
--
-- The function will return:
--   the list of parts (each part with headers, name, contenttype, etc)
--   a easy-to-use map of fields (name -> value)
--                            or (name -> part for files)
local function HTTP_ParseMultipartFormData (Data, BoundaryBase)
  -- Local data
  local Parts        = {}
  local Fields       = {}
  local Boundary     = format("--%s\r\n",   BoundaryBase)
  local CrLfBoundary = format("\r\n--%s",   BoundaryBase)
  local CrLfFinal    = format("\r\n--%s--", BoundaryBase)
  local BLANK_LINE   = "\r\n\r\n"
  -- Helper: parse a header block
  local function ParseHeaders (Block)
    local Headers = {}
    -- Iterate over each non-empty line of the multiline block string
    for Line in Block:gmatch("([^\r\n]+)") do
      local Key, Value = HTTP_ParseHeaderLine(Line)
      if Key then
        Headers[Key] = Value
      end
    end
    return Headers
  end
  -- Position at beginning; expect the body to start with "--boundary\r\n"
  local Start = Data:find(Boundary, 1, true)
  local State
  local Position
  if Start then
    Position = (Start + #Boundary)
    State    = "processing"
  else
    State    = "error"
  end
  while (State == "processing") do
    local HeadersEnd = Data:find(BLANK_LINE, Position, true)
    if (not HeadersEnd) then
      State = "error"
    else
      -- Extract header values (multiple lines)
      local HeaderBlock = Data:sub(Position, (HeadersEnd - 1))
      local Headers     = ParseHeaders(HeaderBlock)
      -- Analyse headers
      local ContentDispositionValue = Headers["content-disposition"]
      local ContentTypeValue        = (Headers["content-type"] or false)
      if (not ContentDispositionValue) then
        State = "error-malformed"
      else
        local ContentDisposition, Parameters = HTTP_ParseHeaderValue(ContentDispositionValue)
        local Name     = Parameters.name
        local Filename = Parameters.filename
        -- Move after the blank line
        local ValueStart = (HeadersEnd + #BLANK_LINE)
        local NextPos    = Data:find(CrLfBoundary, ValueStart, true)
        local ClosePos   = Data:find(CrLfFinal, ValueStart, true)
        local ValueEnd
        if NextPos and (not ClosePos or (NextPos < ClosePos)) then
          ValueEnd = (NextPos - 1)
          State    = "processing"
        elseif ClosePos then
          -- Final boundary detected: "\r\n--BOUNDARY--"
          -- Mark as final so we stop after recording this part.
          ValueEnd = (ClosePos - 1)
          State    = "done"
        else
          State = "error-malformed"
        end
        if (State == "processing") or (State == "done") then
          local Value = Data:sub(ValueStart, ValueEnd)
          local NewPart = {
            headers     = Headers,
            name        = Name,
            filename    = Filename,
            contenttype = ContentTypeValue,
            value       = Value
          }
          append(Parts, NewPart)
          if Name then
            if Filename then
              Fields[Name] = NewPart
            else
              Fields[Name] = Value
            end
          end
          if (State == "processing") then
            -- Move position to the next part's header line.
            Position = (NextPos + #CrLfBoundary + 2)
          end
        end
      end
    end
  end
  -- Return value
  return Parts, Fields
end

--------------------------------------------------------------------------------
-- HTTP CHUNKED                                                               --
--------------------------------------------------------------------------------

-- Example: (after the headers), 7 actually means 0x7
-- 7\r\n
-- Mozilla\r\n
-- 9\r\n
-- Developer\r\n
-- 7\r\n
-- Network\r\n
-- 0\r\n
-- X-Foo: bar\r\n
-- \r\n

local function HTTP_ParseChunkedData (SocketReadFunction, ReceiveChunkFunction)
  local Continue = true
  local Success
  local ErrorString
  while Continue do
    local SizeLineString = SocketReadFunction("l")
    if SizeLineString then
      -- Read data
      local SizeLineInBytes = tonumber(SizeLineString, 16)
      if (SizeLineInBytes == 0) then
        Continue = false
      else
        local ChunkString = SocketReadFunction(SizeLineInBytes)
        local CrLn        = SocketReadFunction(2)
        if (CrLn == "\r\n") then
          -- Notify caller
          ReceiveChunkFunction(ChunkString)
        else
          Continue    = false
          ErrorString = "malformed"
        end
      end
    else
      Continue    = false
      ErrorString = "malformed"
    end
  end
  Success = (ErrorString == nil)
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- HTTP FORMATTING                                                            --
--------------------------------------------------------------------------------

local HTTP_STATUS_TEXT = {
  [200] = "OK",
  [201] = "Created",
  [204] = "No Content",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [403] = "Forbidden",
  [404] = "Not Found",
  [500] = "Internal Server Error",
  [502] = "Bad Gateway",
  [503] = "Service Unavailable"
}

local function HTTP_FormatResponse (HttpCode, Content, UserHeaders, ContentType)
  -- Error handling
  assert(Content)
  assert(ContentType)
  -- Format response
  local StatusText = (HTTP_STATUS_TEXT[HttpCode] or "Unknown")
  local ResponseParts = {
    format("HTTP/1.1 %d %s\r\n", HttpCode, StatusText),
    format("Content-Type: %s\r\n", ContentType),
    format("Content-Length: %d\r\n", #Content),
    "X-Content-Type-Options: nosniff\r\n",
    "X-Frame-Options: DENY\r\n",
    "Referrer-Policy: no-referrer\r\n",
    "Permissions-Policy: geolocation=(), microphone=(), camera=()\r\n",
    "Cache-Control: no-store\r\n"
  }
  if UserHeaders then
    for Key, Value in pairs(UserHeaders) do
      append(ResponseParts, format("%s: %s\r\n", Key, Value))
    end
  end
  append(ResponseParts, "\r\n")
  append(ResponseParts, Content)
  -- Return value
  return concat(ResponseParts)
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  parserequestline    = HTTP_ParseHttpRequestLine,
  parserequesttarget  = HTTP_ParseHttpPath,
  formatresponse      = HTTP_FormatResponse,
  parseheaderline     = HTTP_ParseHeaderLine,
  parseheadervalue    = HTTP_ParseHeaderValue,
  parseformdata       = HTTP_ParseMultipartFormData,
  parseurlencodedform = HTTP_ParseUrlEncodedForm,
  parsechunkeddata    = HTTP_ParseChunkedData
}

return PUBLIC_API
