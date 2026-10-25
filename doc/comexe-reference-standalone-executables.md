# Generating Standalone Executables

`lua55ce` turns a Lua project into a standalone executable. The executable contains the Lua runtime and your project files.

* [Hello World example](#hello-world-example)
* [Compile it into a 2 MiB executable](#compile-it-into-a-2-mib-executable)
* [Cross-compile for other platforms](#cross-compile-for-other-platforms)
* [Executable contents](#executable-contents)
* [Make the executable smaller](#make-the-executable-smaller)

## Hello World example

**main.lua**

```lua title="src\main.lua"
print("Hello World!")
```

This will output:

```sh
E:\my-program>lua55ce src\main.lua
Hello World!
```

## Compile it into a 2 MiB executable

```batch
E:\my-program>lua55ce -x --make src\main.lua

E:\my-program>main.exe
Hello World!
```

## Cross-compile for other platforms

```batch
E:\my-program>lua55ce -x --list-targets
x86_64-linux-gnu
x86_64-linux-gnu-dbg
x86_64-linux-musl
x86_64-linux-musl-dbg
x86_64-windows
x86_64-windows-dbg
x86_64-windows-gui

E:\my-program>lua55ce -x --make src\main.lua -t x86_64-linux-musl
```

Cross-compilation works both ways: build Windows binaries on Linux or Linux binaries on Windows.

A target name without the variant suffixes `-dbg` or `-gui` refers to the console build, intended for command line programs. `-gui` is Win32-only and refers to the Windows subsystem. `-dbg` is the debug build, which is larger and includes debug symbols.

## Executable contents

Option `--verbose` shows more information:

```
> lua55ce -x --make src\main.lua --verbose
TARGET 'main.exe' 'x86_64-windows'
 ENTRY 'main'
ZIPDIR 'src'
CREATE 'main.exe' 2.0 MiB
```

The whole `src` directory is packed and included in the standalone executable, not only `main.lua`.

This command packs *everything* inside the `src` folder:

```sh
lua55ce -x --make src\main.lua
```

Similarly, the following command packs everything inside the current folder (`.`):

```sh
lua55ce -x --make main.lua
```

So if the current folder has those files:
- main.lua
- main.exe

The command will pack both main.lua (good) and main.exe (bad) into the new main.exe, which will make the executable file larger.

Always put the source code in its own folder!

The ZIP part of the executable can be inspected:

```sh
> lua55ce -x --zip l main.exe
comexe/init.lua
comexe/usr/share/lua/5.5/com/runtime.lua
...
main.lua
data.txt
```

The executable size can be reduced by editing the ZIP contents with a ZIP editor such as [7-zip](https://7-zip.org).

## Make the executable smaller

```sh
lua55ce -x --make src\main.lua --nostdlib
```

This removes every bundled Lua module and gives you a ~1.4 MiB executable on Windows.

Removed modules:
- luasocket
- dkjson
- `com.sqlite3`
- `com.ffi`
- `com.win32.easycom`
- `com.webview2`
