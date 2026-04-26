# ComEXE builtins

- [Multithreading](#multithreading)
- [libffi](#libffi)
- [luv: Cross-platform asynchronous I/O](#luv-cross-platform-asynchronous-io)
- [luasocket](#luasocket)
- [JSON](#json)

# Multithreading

ComEXE multithreading is based on OS-level native threads, not Lua green threads or coroutines. Each thread runs its own Lua interpreter and communicates with other threads using the event system.

## Quick start

**[my-thread.lua](../tests/examples/my-thread.lua)**

```lua title="my-thread.lua"
local Event = require("com.event")

function EventDoSomething (...)
  print("EventDoSomething", ...)
end

function EventExitThread ()
  Event.stoploop()
end

-- Block until stoploop() is called
Event.runloop()
print("my-thread close")
```

**[test-doc-main-thread.lua](../tests/examples/test-doc-main-thread.lua)**

```lua title="test-doc-main-thread.lua"
local uv = require("luv")

local Thread = require("com.thread")
local Event  = require("com.event")

-- Called when my-thread.lua exits
function EventMyThreadExit (ThreadId)
  Thread.join(ThreadId) -- Release the thread ID
  Event.stoploop()      -- Stop the loop
end

-- Create the thread by loading my-thread.lua
local ThreadId = Thread.create("my-thread", "EventMyThreadExit")

uv.sleep(1000)
Event.send(ThreadId, "EventDoSomething", 1, true, false, nil)
uv.sleep(1000)

Event.send(ThreadId, "EventExitThread")

-- Block until stoploop() is called
Event.runloop()
print("test-doc-main-thread close")
```

This will output:

```
>lua55ce.exe tests\examples\test-doc-main-thread.lua
EventDoSomething        1       true    false   nil
my-thread close
test-doc-main-thread close
```

## Overview

The multithreading library makes it easy to develop native multithreaded applications in Lua:
* `Thread.create` spawns a new Lua interpreter in a separate OS thread and loads the requested module
* Threads communicate with `Event.send`, which essentially enqueues an event to the target thread
* An event is just a call to a global Lua function
* When a thread exits, the parent is notified with a thread-exit event

Supported event argument types:
- [X] nil
- [X] booleans
- [X] light userdata
- [X] numbers
- [X] strings
- [ ] tables
- [ ] functions
- [ ] full userdata
- [ ] coroutines

Tables and other complex Lua values are not supported. If you need to send a more complex object between threads, serialize it to a string first using a library such as [binser](https://github.com/bakpakin/binser) or [dkjson](https://dkolf.de/dkjson-lua).

# libffi

ComEXE includes Sourceware [libffi](https://github.com/libffi/libffi)  through the `com.ffi` package. This is not [LuaJIT](https://luajit.org/ext_ffi.html)'s `ffi` wrapper, and the API is different.

See [tests/examples/test-doc-ffi.lua](../tests/examples/test-doc-ffi.lua) for an example.

# luv: Cross-platform asynchronous I/O

ComEXE uses [libuv](https://libuv.org) for portability. [luv](https://github.com/luvit/luv) is also included because it is [popular on LuaRocks](https://luarocks.org/search?q=libuv). This library has everything a man could wish for: [timers](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_timer_t--timer-handle), [processes](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_process_t--process-handle), [sockets](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_tcp_t--tcp-handle), [pipes](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_pipe_t--pipe-handle), [ttys](https://github.com/luvit/luv/blob/master/docs/docs.md#uv_tty_t--tty-handle), [file-systems](https://github.com/luvit/luv/blob/master/docs/docs.md#file-system-operations), [threads](https://github.com/luvit/luv/blob/master/docs/docs.md#threading-and-synchronization-utilities), and other [utilities](https://github.com/luvit/luv/blob/master/docs/docs.md#miscellaneous-utilities). You can read the [documentation on GitHub](https://github.com/luvit/luv/blob/master/docs/docs.md).

# luasocket

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

# JSON

ComEXE does not include any JSON library, but we can easily install the great [dkjson](https://dkolf.de/dkjson-lua) library from the integrated [package manager](./third-party-packages.md).
