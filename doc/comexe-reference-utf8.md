# PUC Lua vs ComEXE: Unicode on Windows

Regarding Unicode on Windows, the official Lua binaries do not handle it well. The technical reasons are well-known: `luaL_loadfilex` is implemented with [fopen](https://github.com/lua/lua/blob/master/lauxlib.c). When linked against msvcrt.dll, the fopen function uses the ANSI codepage and not Unicode.

To highlight that, we have a couple of tests available [here](https://github.com/pascalcombier/comexe/tree/main/tests/basics/unicode-tests).

# PUC Lua on Windows

```sh
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

# ComEXE on Windows

```sh
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

# io.open on Windows does not handle UTF-8 properly

Because ComEXE uses an unmodified Lua 5.5, `io.open` is also broken on Windows for UTF-8 filenames; the integrated `luv` library works well for those cases.