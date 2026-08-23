# 📋 Overview

ComEXE is a statically linked, drop-in replacement for the [Lua standalone program](https://www.lua.org/manual/5.5/manual.html#7), with additional command options and built-in libraries for practical use.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey)]()
[![Lua](https://img.shields.io/badge/Lua-5.5-blue)]()
[![GitHub stars](https://img.shields.io/github/stars/pascalcombier/comexe?style=social)]()

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

- [Fetching JSON data over HTTP](./doc/page-github-http-client.md)
- [Using the FFI to wrap a C library](./doc/page-ffi-sqlite.md)
- [Building a GUI with WebView2](./doc/page-webview2.md)
- [Using the FFI to build a Win32 GUI](./doc/page-ffi-win32-gui.md)
- [Using Easycom with Excel](./doc/page-win32-com-excel.md)
- [Using Fennel with ComEXE](./doc/page-fennel.md)
- [Differences with Lua PUC](./doc/page-differences-lua-puc.md)

# ➡️ Next

- [Download binaries for Windows x86-64 and Linux x86-64](https://github.com/pascalcombier/comexe/releases)
