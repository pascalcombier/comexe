# Libraries shipped with ComEXE

## luv: Cross-platform asynchronous I/O

ComEXE uses [libuv](https://libuv.org) for portability. [luv](https://github.com/luvit/luv) is also included because it is [popular on LuaRocks](https://luarocks.org/search?q=libuv). This library has everything a man could wish for: [timers](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_timer_t--timer-handle), [processes](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_process_t--process-handle), [sockets](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_tcp_t--tcp-handle), [pipes](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_pipe_t--pipe-handle), [ttys](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_tty_t--tty-handle), [file-systems](https://github.com/luvit/luv/blob/master/docs/docs.md#file-system-operations), [threads](https://github.com/luvit/luv/blob/master/docs/docs.md#threading-and-synchronization-utilities), and other [utilities](https://github.com/luvit/luv/blob/master/docs/docs.md#miscellaneous-utilities). You can read the [documentation on GitHub](https://github.com/luvit/luv/blob/master/docs/docs.md).

## luasocket

This library is [very popular on LuaRocks](https://luarocks.org/search?q=luasocket), many packages depend on it. ComEXE's default setup lets you fetch resources from HTTP/HTTPS. LuaSocket also has a great [online documentation](https://lunarmodules.github.io/luasocket/index.html). Note that SSL support is now limited to HTTP, it may not work for FTP or SMTP.

```lua title="test-fetch-http.lua"
local http = require("socket.http")
local URI  = "https://github.com/pascalcombier/comexe/blob/main/README.md"

local BodyString, StatusCode, ResponseHeaders, StatusLine = http.request(URI)

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

## JSON

ComEXE does not include any JSON library, but we can easily install the great [dkjson](https://dkolf.de/dkjson-lua) library from the integrated [package manager](./third-party-packages.md).
