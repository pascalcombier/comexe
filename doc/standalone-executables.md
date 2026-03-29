# Generating Standalone Executables

ComEXE lets you turn Lua programs into standalone executables.

## Hello World example

```
E:\my-program>type src\main.lua
print("Hello World!")

E:\my-program>lua55ce src\main.lua
Hello World!
```

## Compile it into a 2.6 MiB executable

```
E:\my-program>lua55ce -x --make src\main.lua

E:\my-program>main.exe
Hello World!
```

## Make the executable smaller

```
lua55ce -x --make src\main.lua --nostdlib
```

This removes the standard libraries and gives you a ~2 MiB executable on Windows.

## Cross-compile for other systems

```
E:\my-program>lua55ce -x --list-targets
x86_64-linux-dbg
x86_64-linux-con
x86_64-windows-con
x86_64-windows-dbg
x86_64-windows-gui

E:\my-program>lua55ce -x --make src\main.lua -t x86_64-linux-con
```

# Important note

ComEXE bundles all files from the source directory into your executable.

This command bundles everything inside the src folder:

```
lua55ce -x --make src\main.lua
```

This command bundles everything inside the current folder (`.`):

```
lua55ce -x --make main.lua
```

So if your current folder has these files:

```
main.lua
main.exe
```

The command will bundle both main.lua (good) and main.exe (bad) into the new main.exe.

Always put your source code in its own folder!
