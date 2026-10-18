# 📋 ComEXE

The ComEXE project currently ships one program: `lua55ce`, a statically linked drop-in replacement for the [Lua standalone program](https://www.lua.org/manual/5.5/manual.html#7) with extra command options and built-in libraries. It can turn a Lua script into a standalone executable for Windows x64 or Linux x64, with no C toolchain and no runtime to install.

```sh
lua55ce -x --make src\hello.lua --nostdlib # Windows x64, 1.4 MiB
```

One can also generate executables for different platforms:

```
lua55ce -x --make src\hello.lua -t x86_64-linux-musl # static
lua55ce -x --make src\hello.lua -t x86_64-linux-gnu  # glibc
```

[![Release](https://img.shields.io/github/v/release/pascalcombier/comexe)](https://github.com/pascalcombier/comexe/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey)]()
[![Lua](https://img.shields.io/badge/Lua-5.5-blue)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

# 🚀 Quick start

Download and extract the [the latest binary release](https://github.com/pascalcombier/comexe/releases/latest). For convenience, rename the `lua55ce-x86_64.exe` to `lua55ce.exe`.

Check the version

```sh
lua55ce -v
```

Write and execute a Lua script

```sh
> mkdir hello
> echo print("Hello World!") > hello\hello.lua
> lua55ce hello\hello.lua
Hello World!
```

Compile the script

```sh
> lua55ce -x --make hello\hello.lua --nostdlib
> hello.exe
Hello World!
```

List the available targets

```sh
> lua55ce -x --list-targets
x86_64-windows
x86_64-windows-dbg
x86_64-windows-gui
x86_64-linux-musl
x86_64-linux-musl-dbg
x86_64-linux-gnu
x86_64-linux-gnu-dbg
```

Compile for Linux musl:

```
> lua55ce -x --make hello\hello.lua --nostdlib -t x86_64-linux-musl -o hello-static
```

# 🚀 Key features

- [x] [Create standalone executables](./doc/comexe-reference-standalone-executables.md)
- [x] [Native multithreading](./doc/comexe-reference-threads.md)
- [x] [Built-in libffi](./doc/comexe-reference-ffi.md) & [preprocessor](./doc/comexe-reference-preprocessor.md)
- [x] [Built-in libuv](./doc/comexe-reference-batteries.md#luv-cross-platform-asynchronous-io), [luasocket](./doc/comexe-reference-batteries.md#luasocket), [LPEG](http://www.inf.puc-rio.br/~roberto/lpeg/), [dkjson](https://dkolf.de/dkjson-lua/)
- [x] [Built-in SQLite support](./doc/comexe-reference-sqlite3.md)
- [x] [Built-in WebView2 support](./doc/comexe-reference-webview2.md)
- [x] [Built-in Win32 API support](./doc/comexe-reference-win32.md)
- [x] [Integrated Package Manager](./doc/comexe-reference-third-party-packages.md)
- [x] [Improved UTF-8 support on Windows](./doc/comexe-reference-utf8.md)
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
