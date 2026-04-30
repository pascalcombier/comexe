# Generating Standalone Executables

ComEXE lets you turn Lua programs into standalone executables.

## Hello World example

```lua title="src\main.lua"
print("Hello World!")
```

This will output:

```sh
E:\my-program>lua55ce src\main.lua
Hello World!
```

## Compile it into a 2.6 MiB executable

```batch
E:\my-program>lua55ce -x --make src\main.lua

E:\my-program>main.exe
Hello World!
```

## Make the executable smaller

```sh
lua55ce -x --make src\main.lua --nostdlib
```

This removes the standard libraries and gives you a ~2 MiB executable on Windows.

## Cross-compile for other platforms

```batch
E:\my-program>lua55ce -x --list-targets
x86_64-linux-dbg
x86_64-linux-con
x86_64-windows-con
x86_64-windows-dbg
x86_64-windows-gui

E:\my-program>lua55ce -x --make src\main.lua -t x86_64-linux-con
```

Cross-compilation works both ways: build Windows binaries on Linux or Linux binaries on Windows.

*con* stands for console, intended for console applications; *gui* is Win32-only and refers to the Windows subsystem. *dbg* is the debug build, larger and includes debug symbols.

# Important note

ComEXE bundles all files from the source directory into your executable.

This command bundles *everything* inside the src folder:

```sh
lua55ce -x --make src\main.lua
```

Similarly, the following command bundles everything inside the current folder (`.`):

```sh
lua55ce -x --make main.lua
```

So if your current folder has those files:
- main.lua
- main.exe

The command will bundle both main.lua (good) and main.exe (bad) into the new main.exe, which will make the executable file larger.

Always put your source code in its own folder!
