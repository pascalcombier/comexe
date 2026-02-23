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
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local MiniReporter = require("mini-reporter")
local MiniHttpLib  = require("com.mini-httpd-lib")

local format = string.format

local parserequestline   = MiniHttpLib.parserequestline
local parserequesttarget = MiniHttpLib.parserequesttarget
local parseheaderline    = MiniHttpLib.parseheaderline
local parseheadervalue   = MiniHttpLib.parseheadervalue
local parseformdata      = MiniHttpLib.parseformdata
local parsechunkeddata   = MiniHttpLib.parsechunkeddata

assert(parserequestline,   "Missing API")
assert(parserequesttarget, "Missing API")
assert(parseheaderline,    "Missing API")
assert(parseheadervalue,   "Missing API")
assert(parseformdata,      "Missing API")
assert(parsechunkeddata,   "Missing API")

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local Reporter = MiniReporter.new()

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function TableCount (Table)
  local Count = 0
  for Key, Value in pairs(Table) do
    Count = (Count + 1)
  end
  return Count
end

--------------------------------------------------------------------------------
-- TESTS parserequestline                                                     --
--------------------------------------------------------------------------------

Reporter:block("parserequestline")

local ParseRequestLineCases = {
  {
    Input          = "GET /hello?x=1 HTTP/1.1",
    ExpectedMethod = "GET",
    ExpectedPath   = "/hello?x=1",
    ExpectedVer    = "HTTP/1.1",
  },
  {
    Input          = "  POST   /submit-form   HTTP/1.0  ",
    ExpectedMethod = "POST",
    ExpectedPath   = "/submit-form",
    ExpectedVer    = "HTTP/1.0",
  },
  {
    Input          = "HEAD /index.html HTTP/2.0",
    ExpectedMethod = "HEAD",
    ExpectedPath   = "/index.html",
    ExpectedVer    = "HTTP/2.0",
  },
}

for Index = 1, #ParseRequestLineCases do
  -- Prepare test
  local TestName = format("parserequestline-%2.2d", Index)
  local TestCase = ParseRequestLineCases[Index]
  local Input    = TestCase.Input
  -- Call the API
  local Method, Path, Version = parserequestline(Input)
  -- Print results
  Reporter:printf("LOG Test %s", TestName)
  Reporter:printf("LOG   INPUT [%s]", TestCase.Input)
  Reporter:printf("LOG  METHOD [%s]", TestCase.ExpectedMethod)
  Reporter:printf("LOG    PATH [%s]", TestCase.ExpectedPath)
  Reporter:printf("LOG VERSION [%s]", TestCase.ExpectedVer)
  -- Check the results
  Reporter:expect(format("%s-01", TestName), (Method  == TestCase.ExpectedMethod))
  Reporter:expect(format("%s-02", TestName), (Path    == TestCase.ExpectedPath))
  Reporter:expect(format("%s-03", TestName), (Version == TestCase.ExpectedVer))
end

--------------------------------------------------------------------------------
-- TESTS parserequesttarget                                                   --
--------------------------------------------------------------------------------

Reporter:block("parserequesttarget")

local ParseRequestTargetCases = {
  {
    Input           = "/hello?x=1",
    ExpectedPath    = "/hello",
    ExpectedQuery   = "x=1",
    Params         = { x = "1" },
  },
  {
    Input           = "/submit-form",
    ExpectedPath    = "/submit-form",
    ExpectedQuery   = "",
    Params         = {},
  },
  {
    Input           = "/search?q=lua&page=2",
    ExpectedPath    = "/search",
    ExpectedQuery   = "q=lua&page=2",
    Params         = { q = "lua", page = "2" },
  },
}

for Index = 1, #ParseRequestTargetCases do
  local TestName       = format("parserequesttarget-%2.2d", Index)
  local TestCase       = ParseRequestTargetCases[Index]
  local Input          = TestCase.Input
  local ExpectedParams = TestCase.Params
  -- Call the API
  local Path, Query, Parameters = parserequesttarget(Input)
  -- Print results (make it easy to review)
  Reporter:printf("LOG Test %s", TestName)
  Reporter:printf("LOG INPUT %q", Input)
  Reporter:printf("LOG  PATH %q", Path)
  Reporter:printf("LOG EXPEC %q", TestCase.ExpectedPath)
  Reporter:printf("LOG QUERY %q", Query)
  Reporter:printf("LOG EXPEC %q", TestCase.ExpectedQuery)
  print("LOG PARAMS")
  for Key, Value in pairs(Parameters) do
    print(format("LOG PARAMS[%q] = %q", Key, Value))
  end
  -- Check the results
  Reporter:expect(format("%s-01", TestName), (Path  == TestCase.ExpectedPath))
  Reporter:expect(format("%s-02", TestName), (Query == TestCase.ExpectedQuery))
  Reporter:expect(format("%s-03", TestName), type(Parameters) == "table")
  Reporter:expect(format("%s-04", TestName), (TableCount(Parameters) == TableCount(ExpectedParams)))
  -- each expected key/value pair matches
  for ExpectedKey, ExpectedValue in pairs(ExpectedParams) do
    Reporter:expect(format("%s-05-%s", TestName, ExpectedKey), (Parameters[ExpectedKey] == ExpectedValue))
  end
  -- no unexpected keys were returned
  for ExpectedKey, ExpectedValue in pairs(Parameters) do
    Reporter:expect(format("%s-06-%s", TestName, ExpectedKey), (ExpectedParams[ExpectedKey] ~= nil))
  end
end

--------------------------------------------------------------------------------
-- TESTS parseheaderline                                                      --
--------------------------------------------------------------------------------

Reporter:block("parseheaderline")

local ParseHeaderLineCases = {
  {
    Input         = "Host: example.com",
    ExpectedKey   = "host",
    ExpectedValue = "example.com",
  },
  {
    Input         = "CONTENT-LENGTH:   123",
    ExpectedKey   = "content-length",
    ExpectedValue = "123",
  },
  {
    Input         = "Content-Type: text/html; charset=UTF-8",
    ExpectedKey   = "content-type",
    ExpectedValue = "text/html; charset=UTF-8",
  },
  {
    Input         = "X-Empty-Header:",
    ExpectedKey   = "x-empty-header",
    ExpectedValue = "",
  },
  {
    Input         = "InvalidHeaderLine",
    IsValid       = false,
  },
}

for Index = 1, #ParseHeaderLineCases do
  local TestName = format("parseheaderline-%2.2d", Index)
  local TestCase = ParseHeaderLineCases[Index]
  local Input    = TestCase.Input
  -- Call the API
  local Key, Value = parseheaderline(Input)
  -- Log for easy review
  Reporter:printf("LOG Test %s", TestName)
  Reporter:printf("LOG INPUT %q", Input)
  if (TestCase.IsValid == false) then
    Reporter:printf("LOG EXPECT invalid header line")
    Reporter:expect(format("%s-01", TestName), (Key   == nil))
    Reporter:expect(format("%s-02", TestName), (Value == nil))
  else
    Reporter:printf("LOG   KEY %q", Key)
    Reporter:printf("LOG   EXP %q", TestCase.ExpectedKey)
    Reporter:printf("LOG VALUE %q", Value)
    Reporter:printf("LOG   EXP %q", TestCase.ExpectedValue)
    Reporter:expect(format("%s-01", TestName), (Key   == TestCase.ExpectedKey))
    Reporter:expect(format("%s-02", TestName), (Value == TestCase.ExpectedValue))
  end
end

--------------------------------------------------------------------------------
-- TESTS parseheadervalue                                                     --
--------------------------------------------------------------------------------

Reporter:block("parseheadervalue")

local Boundary = "----WebKitFormBoundary7xqcng04Y1s7WWtQ"

local ParseHeaderValueCases = {
  {
    Input = format("%s; boundary = %s", "multipart/form-data", Boundary),
    ExpectedValue  = "multipart/form-data",
    ExpectedParams = { boundary = Boundary },
  },
  {
    Input = format("%s ; boundary=%s", "multipart/form-data", Boundary),
    ExpectedValue  = "multipart/form-data",
    ExpectedParams = { boundary = Boundary },
  },
  {
    Input = format("%s; charset=%s; boundary=%s", "multipart/form-data", "UTF-8", Boundary),
    ExpectedValue  = "multipart/form-data",
    ExpectedParams = { charset = "UTF-8", boundary = Boundary },
  },
  {
    Input = format("%s; charset=%s; boundary=\"%s\"", "multipart/form-data", "UTF-8", Boundary),
    ExpectedValue  = "multipart/form-data",
    ExpectedParams = { charset = "UTF-8", boundary = Boundary },
  },
  {
    Input = format("%s; charset=%s; boundary= \"%s\"", "multipart/form-data", "UTF-8", Boundary),
    ExpectedValue  = "multipart/form-data",
    ExpectedParams = { charset = "UTF-8", boundary = Boundary },
  },
  -- RFC 5987/8187 extended parameter: filename* gets decoded and stored under base key
  {
    Input = format("%s; filename*=%s", "attachment", "UTF-8''caf%C3%A9.txt"),
    ExpectedValue  = "attachment",
    ExpectedParams = { filename = "café.txt" },
  },
  -- When both filename and filename* are present, star version overrides
  {
    Input = format("%s; filename=%q; filename*=%s", "attachment", "fallback.txt", "UTF-8''%E2%82%AC%20rates.txt"),
    ExpectedValue  = "attachment",
    ExpectedParams = { filename = "€ rates.txt" },
  },
  -- Accept: list with q-params; current parser treats main value up to first ';'
  -- and collects params thereafter (note: list semantics are not handled here).
  {
    Input = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    ExpectedValue  = "text/html,application/xhtml+xml,application/xml",
    ExpectedParams = { q = "0.8" },
  },
  -- Accept-Language: list with a single q-param
  {
    Input          = "en-US,en;q=0.5",
    ExpectedValue  = "en-us,en",
    ExpectedParams = { q = "0.5" },
  },
  -- Accept-Encoding: list without parameters
  {
    Input          = "gzip, deflate, br",
    ExpectedValue  = "gzip, deflate, br",
    ExpectedParams = {},
  },
  -- Connection: simple token
  {
    Input = "keep-alive",
    ExpectedValue  = "keep-alive",
    ExpectedParams = {},
  },
  -- Upgrade-Insecure-Requests: numeric flag
  {
    Input = "1",
    ExpectedValue  = "1",
    ExpectedParams = {},
  },
}

for Index = 1, #ParseHeaderValueCases do
  local TestName = format("parseheadervalue-%2.2d", Index)
  local TestCase = ParseHeaderValueCases[Index]
  local Input    = TestCase.Input
  -- Call API
  local Value, Params = parseheadervalue(Input)
  -- Logging
  Reporter:printf("LOG Test %s", TestName)
  Reporter:printf("LOG INPUT %q", Input)
  Reporter:printf("LOG VALUE %q", Value)
  Reporter:printf("LOG EXPEC %q", TestCase.ExpectedValue)
  Reporter:printf("LOG PARAMS")
  for K, V in pairs(Params) do
    Reporter:printf("LOG PARAMS[%q] = %q", K, V)
  end
  -- Expectations
  Reporter:expect(format("%s-01", TestName), (Value == TestCase.ExpectedValue))
  Reporter:expect(format("%s-02", TestName), (type(Params) == "table"))
  Reporter:expect(format("%s-03", TestName), (TableCount(Params) == TableCount(TestCase.ExpectedParams)))
  -- each expected key/value pair matches
  for ExpectedKey, ExpectedValue in pairs(TestCase.ExpectedParams) do
    Reporter:expect(format("%s-04-%s", TestName, ExpectedKey), (Params[ExpectedKey] == ExpectedValue))
  end
  -- no unexpected keys were returned
  for ExpectedKey, ExpectedValue in pairs(Params) do
    Reporter:expect(format("%s-05-%s", TestName, ExpectedKey), (TestCase.ExpectedParams[ExpectedKey] ~= nil))
  end
end

--------------------------------------------------------------------------------
-- TESTS parseformdata                                                        --
--------------------------------------------------------------------------------

Reporter:block("parseformdata")

local Boundary = "----WebKitFormBoundary7xqcng04Y1s7WWtQ"
local Body     = format("--%s\r\nContent-Disposition: form-data; name=\"foo\"\r\n\r\nbar\r\n--%s\r\nContent-Disposition: form-data; name=\"num\"\r\n\r\n123\r\n--%s--\r\n", Boundary, Boundary, Boundary)
local Parts, Fields = parseformdata(Body, Boundary)

Reporter:printf("LOG parseformdata: GOT Parts=%d EXPECTED=2", #Parts)
Reporter:printf("LOG parseformdata: GOT Fields.foo=%q EXPECTED=%q", Fields.foo, "bar")
Reporter:printf("LOG parseformdata: GOT Fields.num=%q EXPECTED=%q", Fields.num, "123")
Reporter:expect("parseformdata-01", type(Parts) == "table")
Reporter:expect("parseformdata-02", type(Fields) == "table")
Reporter:expect("parseformdata-03", (#Parts == 2))
Reporter:expect("parseformdata-04", Fields.foo == "bar")
Reporter:expect("parseformdata-05", Fields.num == "123")

--------------------------------------------------------------------------------
-- TEST parsechunkeddata                                                         --
--------------------------------------------------------------------------------

Reporter:block("parsechunkeddata")

local WriteSequence = {
  "7",
  "MozillaXXXXXXXXXXX",
  "\r\n",
  "9",
  "DeveloperXXXXXXXXX",
  "\r\n",
  "7",
  "NetworkXXXXXXXXXXXX",
  "\r\n",
  "0",
  "X-Foo: barXXXXXXXXX",
  "",
}

local ReadSequence = {
  "Mozilla",
  "Developer",
  "Network",
}

local WriteIndex = 1
local ReadCount  = 0

local function SocketReadFunction (Param)
  local Value
  if (Param == "l") then
    Value      = WriteSequence[WriteIndex]
    WriteIndex = WriteIndex + 1
  else
    if (type(Param) == "number") then
      local ByteCount  = Param
      local FullString = WriteSequence[WriteIndex]
      Value     = FullString:sub(1, ByteCount)
      WriteIndex = WriteIndex + 1
    end
  end
  Reporter:printf("LOG SocketReadFunction %q => %q", Param, Value)
  return Value
end

local function ReceiveChunkFunction (ChunkString)
  Reporter:printf("LOG ReceiveChunkFunction %q", ChunkString)
  ReadCount = (ReadCount + 1)
  local ReadIndex = ReadCount
  local Expected  = ReadSequence[ReadIndex]
  Reporter:printf("GOT CHUNK %q", ChunkString)
  Reporter:printf("EXP CHUNK %q", Expected)
  Reporter:expect(format("parsechunkeddata-%2.2d", ReadIndex), (ChunkString == Expected))
end

local Value, ErrorString = parsechunkeddata(SocketReadFunction, ReceiveChunkFunction)
Reporter:printf("parsechunkeddata return %q %q", Value, ErrorString)
Reporter:printf("parsechunkeddata read count %q", ReadCount)

Reporter:expect("parsechunkeddata-X01", (ReadCount == 3))
Reporter:expect("parsechunkeddata-X02", Value)

--------------------------------------------------------------------------------
-- SUMMARY                                                                    --
--------------------------------------------------------------------------------

Reporter:printf("== SUMMARY ==")
Reporter:summary("os.exit")
