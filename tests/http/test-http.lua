local http = require("socket.http")

local format = string.format

local function TEST_Uri (Uri)
  print(format("TEST [%s]", Uri))
  local Body, HttpCode, Headers, StatusLine = http.request(Uri)
  print(Body)
  print(HttpCode)
  print(Headers)
  print(StatusLine)
  return Body, HttpCode, Headers, StatusLine
end

local Body1, HttpCode1, Headers1, StatusLine1 = TEST_Uri("http://example.com")
local Body2, HttpCode2, Headers2, StatusLine2 = TEST_Uri("https://example.com")

if (Body1 == Body2)
  and HttpCode1 == HttpCode2
  and StatusLine1 == StatusLine2
then
  print("TEST OK")
  os.exit(0)
else
  print("TEST OK")
  os.exit(1)
end
