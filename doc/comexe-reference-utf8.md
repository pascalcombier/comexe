# PUC Lua vs ComEXE: Unicode support on Windows

The official [Lua binaries on Windows](https://luabinaries.sourceforge.net) have limited UTF-8 support. ComEXE fixes some limitations.

| # | Function                                                              | Official Lua | ComEXE |
|---|-----------------------------------------------------------------------|--------------|--------|
| 1 | [`print`](https://www.lua.org/manual/5.5/manual.html#pdf-print)       | No           | Yes    |
| 2 | [`require`](https://www.lua.org/manual/5.5/manual.html#pdf-require)   | No           | Yes    |
| 3 | [`loadfile`](https://www.lua.org/manual/5.5/manual.html#pdf-loadfile) | No           | No     |
| 4 | [`io.open`](https://www.lua.org/manual/5.5/manual.html#pdf-io.open)   | No           | No     |

To test points 1 and 2, we wrote a [small set of tests](https://github.com/pascalcombier/comexe/tree/main/tests/basics/unicode-tests). The workaround for points 3 and 4 is to use the built-in [luv](https://github.com/luvit/luv/blob/master/docs/docs.md#uvfs_openpath-flags-mode-callback) library instead of standard Lua functions. We also wrote [a test](https://github.com/pascalcombier/comexe/blob/main/tests/basics/test-luv-unicode.lua) for this.

## PUC Lua on Windows

```console
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

## ComEXE on Windows

```console
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
