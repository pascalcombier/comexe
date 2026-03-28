# Differences with Lua PUC

## Unicode on Windows

Regarding Unicode on Windows, the official Lua binaries do not handle it well. The technical reasons are well-known: luaL_loadfilex is implemented with [fopen](https://github.com/lua/lua/blob/master/lauxlib.c). When linked against msvcrt.dll, the fopen function uses the ANSI codepage and not Unicode.

```
> lua55.exe test-greetings-привет.lua
lua55.exe: cannot open test-greetings-??????.lua: Invalid argument
> lua55.exe test-hello-こんにちは.lua
lua55.exe: cannot open test-hello-?????.lua: Invalid argument
> lua55.exe test-hola-世界.lua
lua55.exe: cannot open test-hola-??.lua: Invalid argument
> lua55.exe test-γεια-σας.lua
lua55.exe: cannot open test-?e?a-sa?.lua: Invalid argument
> lua55.exe test-안녕하세요-world.lua
lua55.exe: cannot open test-?????-world.lua: Invalid argument
```

With ComEXE, the experience is improved:

```
> lua55ce.exe test-greetings-привет.lua
arg[0]  test-greetings-привет.lua
> lua55ce.exe test-hello-こんにちは.lua
arg[0]  test-hello-こんにちは.lua
> lua55ce.exe test-hola-世界.lua
arg[0]  test-hola-世界.lua
> lua55ce.exe test-γεια-σας.lua
arg[0]  test-γεια-σας.lua
> lua55ce.exe test-안녕하세요-world.lua
arg[0]  test-안녕하세요-world.lua
```

## Default paths

Another difference in ComEXE is the way [package.path](https://www.lua.org/manual/5.5/manual.html#pdf-package.path) and [package.searchers](https://www.lua.org/manual/5.5/manual.html#pdf-package.searchers) are initialized. The main point is that ComEXE has been designed to develop *portable* programs — portable in the sense that a program can be moved across the filesystem and continue to work properly. The behavior of ComEXE on Windows and Linux is identical.

Let's look at an example: here, by default, the standard Lua binaries can't find `lib-hello.lua`, which is required by `main.lua`:

```
E:\example>tree /f
E:.
│   lua55.exe   # original Lua binary
│   lua55ce.exe # ComEXE Lua
└───hello
        lib-hello.lua
        main.lua

E:\example>type hello\main.lua
require("lib-hello")

E:\example>type hello\lib-hello.lua
print("Hello World!")

E:\example>lua55.exe hello\main.lua
lua55.exe: hello\main.lua:1: module 'lib-hello' not found:
        no field package.preload['lib-hello']
        no file 'E:\example\lua\lib-hello.lua'
        no file 'E:\example\lua\lib-hello\init.lua'
        no file 'E:\example\lib-hello.lua'
        no file 'E:\example\lib-hello\init.lua'
        no file 'E:\example\..\share\lua\5.5\lib-hello.lua'
        no file 'E:\example\..\share\lua\5.5\lib-hello\init.lua'
        no file '.\lib-hello.lua'
        no file '.\lib-hello\init.lua'
        no file 'E:\example\lib-hello.dll'
        no file 'E:\example\..\lib\lua\5.5\lib-hello.dll'
        no file 'E:\example\loadall.dll'
        no file '.\lib-hello.dll'
stack traceback:
        [C]: in global 'require'
        hello\main.lua:1: in main chunk
        [C]: in ?

E:\example>lua55ce.exe hello\main.lua
Hello World!
```

This also means that all dependencies should be shipped with the program. The files in `C:\Program Files\` are not available to ComEXE programs; instead, you can store external dependencies in the special directory `share\lua\5.5`.

```
E:\example>tree /f
E:.
│   lua55.exe   # original Lua binary
│   lua55ce.exe # ComEXE Lua
└───hello
    │   lib-hello.lua
    │   main.lua
    └───share
        └───lua
            └───5.5
                    fennel.lua

E:\example>type hello\main.lua
require("fennel")
require("lib-hello")

E:\example>type hello\lib-hello.lua
print("Hello World!")

E:\example>lua55.exe hello\main.lua
lua55.exe: hello\main.lua:1: module 'fennel' not found:
        no field package.preload['fennel']
        no file 'E:\example\lua\fennel.lua'
        no file 'E:\example\lua\fennel\init.lua'
        no file 'E:\example\fennel.lua'
        no file 'E:\example\fennel\init.lua'
        no file 'E:\example\..\share\lua\5.5\fennel.lua'
        no file 'E:\example\..\share\lua\5.5\fennel\init.lua'
        no file '.\fennel.lua'
        no file '.\fennel\init.lua'
        no file 'E:\example\fennel.dll'
        no file 'E:\example\..\lib\lua\5.5\fennel.dll'
        no file 'E:\example\loadall.dll'
        no file '.\fennel.dll'
stack traceback:
        [C]: in global 'require'
        hello\main.lua:1: in main chunk
        [C]: in ?

E:\example>lua55ce.exe hello\main.lua
Hello World!
```
