# ComEXE builtins

- [libffi](#libffi)
- [luv: Cross-platform asynchronous I/O](#luv-cross-platform-asynchronous-io)
- [luasocket](#luasocket)
- [mbedtls](#mbedtls)

# libffi

ComEXE includes Sourceware [libffi](https://github.com/libffi/libffi)  through the `com.ffi` package. This is not [LuaJIT](https://luajit.org/ext_ffi.html)'s `ffi`, and the API is different.

See [tests/examples/test-doc-ffi.lua](../tests/examples/test-doc-ffi.lua) for an example.

# luv: Cross-platform asynchronous I/O

ComEXE uses [libuv](https://libuv.org) for portability. [luv](https://github.com/luvit/luv) is also included because it is [popular on LuaRocks](https://luarocks.org/search?q=libuv). This library has everything a man could wish for: [timers](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_timer_t--timer-handle), [processes](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_process_t--process-handle), [sockets](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_tcp_t--tcp-handle), [pipes](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_pipe_t--pipe-handle), [ttys](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_tty_t--tty-handle), [file-systems](https://github.com/luvit/luv/blob/master/docs/docs.md#file-system-operations), [threads](https://github.com/luvit/luv/blob/master/docs/docs.md#threading-and-synchronization-utilities), and other [utilities](https://github.com/luvit/luv/blob/master/docs/docs.md#miscellaneous-utilities). You can read the [documentation on GitHub](https://github.com/luvit/luv/blob/master/docs/docs.md).

# luasocket

## Overview

ComEXE embeds [LuaSocket](https://lunarmodules.github.io/luasocket/index.html):

* Fetch resources from HTTP and HTTPS via `socket.http`
* TLS support is available for HTTP but support for FTP, SMTP, and other socket protocols may be limited

## Example fetching HTTPS

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

```sh
E:\my-program>lua55ce-x86_64-windows.exe test-http.lua
Body Length      229287
HttpCode         200
Response Headers 0
StatusLine       HTTP/1.1 200 OK
```

## Example decoding JSON data

JSON is supported by [installing third-party packages](./comexe-reference-standalone-executables.md) and [dkjson](https://dkolf.de/dkjson-lua) can be installed:

```
lua55ce.exe -x --apm install dkjson-2.8
```

Use the JSON library as [documented](https://dkolf.de/dkjson-lua/):

```
local json = require("dkjson")
local http = require("socket.http")
local URI  = "https://api.github.com"

local JsonString, HttpCode, ResponseHeaders, StatusLine = http.request(URI)

if (HttpCode == 200) then
  local JsonObject = json.decode(JsonString)
  if JsonObject then
    for Key, Value in pairs(JsonObject) do
      print(string.format("%q = %q", Key, Value))
    end
  end
end
```

This should output the [GitHub JSON API](https://api.github.com):
```
"issue_search_url" = "https://api.github.com/search/issues?q={query}{&page,per_page,sort,order}"
"current_user_repositories_url" = "https://api.github.com/user/repos{?type,page,per_page,sort}"
"authorizations_url" = "https://api.github.com/authorizations"
"repository_url" = "https://api.github.com/repos/{owner}/{repo}"
"public_gists_url" = "https://api.github.com/gists/public"
...
```

This example use `dkjson`, but multiple other JSON libraries can be used as well.

## Example encoding JSON data

```lua
local json = require("dkjson")

local LuaObject  = { Hello = "world", Answer = 42 }
local JsonString = json.encode(LuaObject)
print(string.format("%q", JsonString))
```

This should output:

```
"{\"Answer\":42,\"Hello\":\"world\"}"
```

# mbedtls

ComEXE embeds [mbedtls](https://github.com/Mbed-TLS/mbedtls) and [lua-mbedtls](https://github.com/neoxic/lua-mbedtls)
