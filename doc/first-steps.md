# First steps with ComEXE

ComEXE is distributed as a [binary program](https://github.com/pascalcombier/comexe/releases) called lua55ce.exe on Windows and lua55ce on Linux. The name is very close to the original Lua binaries lua55.exe and lua55 because it is intended as a drop-in replacement: ComEXE embeds the unmodified source code of Lua 5.5.

```
> lua55ce
Lua 5.5.0  Copyright (C) 1994-2025 Lua.org, PUC-Rio, ComEXE 0.0.1 2026-02-22T16:04:59
> print("Hello World!")
Hello World!
> 
```

The [command-line flags](https://www.lua.org/manual/5.5/manual.html#7) of the official Lua interpreter are compatible with ComEXE.

```
> lua55ce -h
lua55ce: unrecognized option '-h'
usage: lua55ce [options] [script [args]]
Available options are:
  -e stat   execute string 'stat'
  -i        enter interactive mode after executing 'script'
  -l mod    require library 'mod' into global 'mod'
  -l g=mod  require library 'mod' into global 'g'
  -v        show version information
  -E        ignore environment variables
  -W        turn warnings on
  --        stop handling options
  -         stop handling options and execute stdin
  -x        Enable ComEXE extended commands
```

Each release contains the release binaries for Linux and Windows:

```
lua55ce-x86_64-linux
lua55ce-x86_64-windows.exe
LICENSE
```

After download, rename the Linux binary to `lua55ce` and the Windows binary to `lua55ce.exe`.