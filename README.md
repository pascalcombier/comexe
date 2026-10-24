# 📋 ComEXE

**`lua55ce` is a Lua 5.5 interpreter for Windows x64 and Linux x64 that can turn a Lua project into a standalone executable, without any C/C++ compiler.**

```sh
> lua55ce src\hello.lua                                 # run a script
> lua55ce -x --make src\hello.lua                       # standalone executable, current OS, ~2.0 MiB
> lua55ce -x --make src\hello.lua -t x86_64-windows     # Windows x64, console
> lua55ce -x --make src\hello.lua -t x86_64-windows-gui # Windows x64, GUI subsystem
> lua55ce -x --make src\hello.lua -t x86_64-linux-musl  # Linux x64, static
> lua55ce -x --make src\hello.lua -t x86_64-linux-gnu   # Linux x64, glibc
```

[![Release](https://img.shields.io/github/v/release/pascalcombier/comexe?color=blue)](https://github.com/pascalcombier/comexe/releases/latest)
![Platform](https://img.shields.io/badge/platform-Windows%20x64%20%7C%20Linux%20x64-lightgrey)
![Lua](https://img.shields.io/badge/Lua-5.5.1-2C2D72?logo=lua&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

# 🚀 Quick start

Download and extract the [latest binary release](https://github.com/pascalcombier/comexe/releases/latest), rename `lua55ce-x86_64.exe` to `lua55ce.exe` for convenience:

```sh
> lua55ce -v
Lua 5.5.1  Copyright (C) 1994-2025 Lua.org, PUC-Rio, ComEXE 0.0.12 2026-10-11T16:35:28
> mkdir src
> echo print("Hello World!") > src\hello.lua
> lua55ce src\hello.lua
Hello World!
> lua55ce -x --make src\hello.lua
> hello.exe
Hello World!
```

Option `--verbose` shows more information:

```
> lua55ce -x --make src\hello.lua --verbose
Building target 'x86_64-windows' -> hello.exe
NOTE compressing directory 'src'
hello.exe created (2.0 MiB)
```

The key point is that the whole `src` directory is packed and included in the standalone executable, not only `hello.lua`. See [Standalone executables](./doc/comexe-reference-standalone-executables.md) for details.

# 🌐 Cross-compiling

Windows and Linux hosts can build for both systems:

```sh
> lua55ce -x --list-targets
x86_64-windows
x86_64-windows-dbg
x86_64-windows-gui
x86_64-linux-musl
x86_64-linux-musl-dbg
x86_64-linux-gnu
x86_64-linux-gnu-dbg
> lua55ce -x --make src\hello.lua -t x86_64-linux-musl
```

| Build                                   | Size     |
|-----------------------------------------|----------|
| Windows x64, full runtime               | 1.99 MiB |
| Windows x64, `--nostdlib`               | 1.41 MiB |
| Linux x64, `x86_64-linux-musl` (static) | 2.82 MiB |
| Linux x64, `x86_64-linux-gnu` (glibc)   | 2.64 MiB |

The option `--nostdlib` strips all the Lua modules from the executable.

# 🚀 Key features

- [x] [Create standalone executables](./doc/comexe-reference-standalone-executables.md)
- [x] [Native multithreading](./doc/comexe-reference-threads.md)
- [x] [Built-in libffi](./doc/comexe-reference-ffi.md) & [preprocessor](./doc/comexe-reference-preprocessor.md)
- [x] [Built-in libuv](./doc/comexe-page-batteries.md#luv-cross-platform-asynchronous-io), [luasocket](./doc/comexe-page-batteries.md#luasocket), [LPEG](http://www.inf.puc-rio.br/~roberto/lpeg/), [dkjson](https://dkolf.de/dkjson-lua/)
- [x] [Built-in SQLite support](./doc/comexe-reference-sqlite3.md)
- [x] [Built-in WebView2 support](./doc/comexe-reference-webview2.md)
- [x] [Built-in Win32 API support](./doc/comexe-reference-win32.md)
- [x] [Integrated Package Manager](./doc/comexe-reference-third-party-packages.md)
- [x] [Improved UTF-8 support on Windows](./doc/comexe-page-utf8-on-windows.md)
- [x] [MIT license](./LICENSE)

# 📘 Guides & Notes

- [Building ComEXE from source](./doc/page-build-from-source.md)
- [Fetching JSON data over HTTP](./doc/page-github-http-client.md)
- [Using the FFI to wrap a C library](./doc/page-ffi-sqlite.md)
- [Building a GUI with WebView2](./doc/page-webview2.md)
- [Using the FFI to build a Win32 GUI](./doc/page-ffi-win32-gui.md)
- [Using Easycom with Excel](./doc/page-win32-com-excel.md)
- [Using Fennel with ComEXE](./doc/page-fennel.md)
- [Differences with Lua PUC](./doc/page-differences-lua-puc.md)

# ➡️ Next

- [Download binaries for Windows x86-64 and Linux x86-64](https://github.com/pascalcombier/comexe/releases)
