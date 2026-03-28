# Integrate third-party packages with ComEXE programs

## With the package manager APM

APM is shipped with ComEXE, making all packages from [ComLIB](https://github.com/pascalcombier/comlib) available.

List the available packages:
```
E:\my-program\src>lua55ce -x --apm list
FETCHING https://raw.githubusercontent.com/pascalcombier/comlib/refs/heads/main/packages/lua/5.5/index.zip...OK
CREATING DIRECTORY .comexe\apm...OK
WRITING .comexe/apm/apm-repository-01.zip...OK
APM cache updated: .comexe/apm/apm-index.lua
BetterPrint-2.0.0
BioLua-0.15
Caelum-1.1
CognitioLogger-0.0.3
Colorise-1.0
Colors-8.05.26
...
```

Install a package:

```
E:\my-program\src>lua55ce -x --apm install uint-0.186
CHECKING lua >= 5.1...OK
FETCHING https://raw.githubusercontent.com/pascalcombier/comlib/refs/heads/main/packages/lua/5.5/uint.zip...OK
WRITING .comexe/apm/uint.zip...OK
WRITING share\lua\5.5\uint.lua...OK
INSTALLED uint-0.186
Note: Packages are third-party software with their own LICENSES
```

Use a package interactively:
```
E:\my-program\src>lua55ce
Lua 5.5.0  Copyright (C) 1994-2025 Lua.org, PUC-Rio, ComEXE 0.0.3 2026-03-28T11:30:47
> int = require("uint")
> x, y = int.new("20", "10")
> print(x ^ y)
10240000000000
```

Use a package in a program:
```
E:\my-program\src>REM check the contents of main.lua

E:\my-program\src>type main.lua
-- require a module
local int = require("uint")

-- build a new int object
local x, y = int.new("20", "10")

print(x ^ y) -- output: 10240000000000

E:\my-program\src>REM run the script

E:\my-program\src>lua55ce main.lua
10240000000000
```
## Manually

Just create a directory `share\lua\5.5\` in the source directory and copy the files there.

```
E:\my-program\src>REM check the files available in the share directory

E:\my-program\src>dir share\lua\5.5
03/28/2026  12:49 PM    <DIR>          .
03/28/2026  12:49 PM    <DIR>          ..
03/28/2026  12:49 PM            55,226 uint.lua
               1 File(s)         55,226 bytes
               2 Dir(s)  401,337,143,296 bytes free

E:\my-program\src>REM check the contents of main.lua

E:\my-program\src>type main.lua
-- require a module
local int = require("uint")

-- build a new int object
local x, y = int.new("20", "10")

print(x ^ y) -- output: 10240000000000

E:\my-program\src>REM run the program

E:\my-program\src>lua55ce main.lua
10240000000000
```
