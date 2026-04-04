# Libraries shipped with ComEXE

## luv: Cross-platform asynchronous I/O

ComEXE uses [libuv](https://libuv.org) for portability. [luv](https://github.com/luvit/luv) is also included because it seems [popular on LuaRocks](https://luarocks.org/search?q=libuv). This library has everything a man could wish for: timers, processes, sockets, pipes, ttys, file-systems, threads, and other utilities. You can read [documentation on GitHub](https://github.com/luvit/luv/blob/master/docs/docs.md).

## luasocket

This library is [very popular on LuaRocks](https://luarocks.org/search?q=luasocket), many packages depend on it. ComEXE's default setup lets you fetch resources from HTTP/HTTPS.

```lua title="test-fetch-http.lua"
local http = require("socket.http")

local BodyString, StatusCode, ResponseHeaders, StatusLine = http.request("https://github.com/pascalcombier/comexe/blob/main/README.md")

print("Body Length", #BodyString)
print("HttpCode", StatusCode)
if ResponseHeaders then
  print("Response Headers", #ResponseHeaders)
else
  print("Response Headers none")
end
print("StatusLine", StatusLine)
```

This should give you this output:

```
E:\my-program>lua55ce-x86_64-windows.exe test-http.lua
Body Length      229287
HttpCode         200
Response Headers 0
StatusLine       HTTP/1.1 200 OK
```

LuaSocket also has [online documentation](https://lunarmodules.github.io/luasocket/index.html). Note that SSL support is now limited to HTTP. It may not work for FTP or SMTP.

## JSON

ComEXE does not include any JSON library, but we can easily install the great [dkjson](https://dkolf.de/dkjson-lua) library from the integrated [package manager](./third-party-packages.md).
