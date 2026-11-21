# Generating Standalone Executables

* [Overview](#overview)
* [A first script](#a-first-script)
* [Building an executable](#building-an-executable)
* [Executable layout](#executable-layout)
  * [ComEXE runtime](#comexe-runtime)
  * [Standard Lua runtime](#standard-lua-runtime)
* [Project example](#project-example)
  * [Project structure](#project-structure)
  * [Third-party libraries](#third-party-libraries)
  * [Resources](#resources)
  * [Build the example](#build-the-example)
* [Cross-compilation](#cross-compilation)
* [Troubleshooting](#troubleshooting)
  * [Executable size is larger than expected](#executable-size-is-larger-than-expected)

# Overview

`lua55ce` runs Lua scripts like the standard [Lua interpreter](https://www.lua.org/manual/5.5/manual.html#7). `lua55ce -x --make` generates standalone executables for Windows and Linux, natively or by cross-compilation. Those executables are [self-extracting archives](https://en.wikipedia.org/wiki/Self-extracting_archive). Their contents can be listed with `lua55ce -x --zip l` or with ZIP tools such as [7-Zip](https://7-zip.org/). At startup the Lua runtime is read from the ZIP in memory, so nothing is extracted to disk. Lua is statically linked into each executable, so target machines do not need a Lua library.

# A first script

Create a script and run it:

```console
> mkdir src
> echo print("Hello World!") > src\hello.lua
> lua55ce src\hello.lua
Hello World!
```

# Building an executable

`lua55ce -x --make` builds an executable from a Lua file:

```console
> lua55ce -x --make src\hello.lua
> hello.exe
Hello World!
```

The executable is named after the script file and written to the current directory. Use `-o` to set another name:

```console
> lua55ce -x --make src\hello.lua -o my-program.exe
```

The same build with `--verbose`:

```console
> lua55ce -x --make src\hello.lua --verbose
TARGET 'hello.exe' 'x86_64-windows' 'comexe-runtime'
 ENTRY 'hello'
ZIPDIR 'src'
CREATE 'hello.exe' 2.0 MiB
```

`ZIPDIR` is `src`: the whole directory is packed, not only `hello.lua`. The last line reports the size of the generated executable.

# Executable layout

## ComEXE runtime

The executable embeds a ZIP with ComEXE's runtime files and the contents of the source directory:

```console
> lua55ce -x --zip l hello.exe
... (runtime files)
comexe/init.lua
comexe/usr/share/lua/5.5/com/runtime.lua
... (packed files)
hello.lua
```

ComEXE's runtime is made of multiple files, providing LuaSocket, dkjson, minizip and others. `--stdlua` omits them when a program uses only [the Lua standard libraries](https://www.lua.org/manual/5.5/manual.html#6).

## Standard Lua runtime

```console
> lua55ce -x --make src\hello.lua --stdlua --verbose
TARGET 'hello.exe' 'x86_64-windows' 'lua-runtime'
 ENTRY 'hello'
ZIPDIR 'src'
CREATE 'hello.exe' 1.4 MiB
> lua55ce -x --zip l hello.exe
comexe/init.lua
hello.lua
```

With `--stdlua`, the runtime is limited to the file `comexe/init.lua`, so the executable is 1.4 MiB.

# Project example

A project can use third-party libraries or embed data files.

## Project structure

The `src` directory contains three files:

* `project.lua`: project entry point
* `project.dat`: data loaded at runtime
* `share/lua/5.5/inspect.lua`: third-party library dependency

**project.dat**

```
Hello World!
```

**project.lua**

```lua
local Runtime = require("com.runtime")
local Inspect = require("inspect")

local Text = Runtime.loadresource("project.dat")

print(Inspect({ text = Text }))
```

## Third-party libraries

The optional `share\lua\5.5` directory is automatically added to [`package.path`](https://www.lua.org/manual/5.5/manual.html#6.3), so third-party libraries can be placed there: `require("inspect")` loads `share\lua\5.5\inspect.lua`.

## Resources

The `--make` command packs every file of the source directory, not only the Lua sources. `Runtime.loadresource` can retrieve any packed file at runtime.

`Runtime.loadresource` reads from the file system under `lua55ce` or from the embedded ZIP under `project.exe`:

| Command                   | `loadresource("project.dat")` |
|---------------------------|-------------------------------|
| `lua55ce src\project.lua` | File `src\project.dat`        |
| `project.exe`             | ZIP Entry `project.dat`       |

`Runtime.loadresource` returns `nil` when the resource is not found.

## Build the example

```console
> lua55ce -x --make src\project.lua
> project.exe
{ text = "Hello World!" }
```

# Cross-compilation

List the available targets:

```console
> lua55ce -x --list-targets
x86_64-windows
x86_64-windows-dbg
x86_64-windows-gui
x86_64-linux-musl
x86_64-linux-musl-dbg
x86_64-linux-gnu
x86_64-linux-gnu-dbg
```

| Target                  | ARCH   | OS           | LIBC  | Variant | Mode    |
|-------------------------|--------|--------------|-------|---------|---------|
| `x86_64-windows`        | x86_64 | Windows 10+  | UCRT  | Console | Release |
| `x86_64-windows-dbg`    | x86_64 | Windows 10+  | UCRT  | Console | Debug   |
| `x86_64-windows-gui`    | x86_64 | Windows 10+  | UCRT  | GUI     | Release |
| `x86_64-linux-musl`     | x86_64 | Linux        | musl  | Console | Release |
| `x86_64-linux-musl-dbg` | x86_64 | Linux        | musl  | Console | Debug   |
| `x86_64-linux-gnu`      | x86_64 | Linux        | glibc | Console | Release |
| `x86_64-linux-gnu-dbg`  | x86_64 | Linux        | glibc | Console | Debug   |

Build the executable for another target:

```console
> lua55ce -x --make src\project.lua -t x86_64-linux-musl
```

Cross-compilation works both ways: build Windows binaries on Linux, or Linux binaries on Windows.

# Troubleshooting

## Executable size is larger than expected

The build runs in the source directory:

```console
> echo print("Hello World!") > hello.lua
> lua55ce -x --make hello.lua --verbose --stdlua
TARGET 'hello.exe' 'x86_64-windows' 'lua-runtime'
 ENTRY 'hello'
ZIPDIR '.'
CREATE 'hello.exe' 1.4 MiB
```

The build creates `hello.exe` next to `hello.lua`:

```
hello.lua
hello.exe
```

`hello.exe` embeds two files:

```console
> lua55ce -x --zip l hello.exe
comexe/init.lua
hello.lua
```

Building again increases the binary size:

```console
> lua55ce -x --make hello.lua --verbose --stdlua
TARGET 'hello.exe' 'x86_64-windows' 'lua-runtime'
 ENTRY 'hello'
ZIPDIR '.'
CREATE 'hello.exe' 2.1 MiB
```

The new `hello.exe` is bigger because it contains the previous executable:

```console
> lua55ce -x --zip l hello.exe
comexe/init.lua
hello.exe
hello.lua
```
