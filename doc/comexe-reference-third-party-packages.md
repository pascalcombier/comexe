# Installing Third-Party Packages in ComEXE

## With the package manager APM

APM is shipped with ComEXE, making all packages from [ComLIB](https://github.com/pascalcombier/comlib) available.

### List the available packages

```sh
> lua55ce -x --apm list
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

### Install a package

The `apm install` command downloads the package files and places them in the `share\lua\5.5` directory.

```sh
> lua55ce -x --apm install uint-0.186
CHECKING lua >= 5.1...OK
FETCHING https://raw.githubusercontent.com/pascalcombier/comlib/refs/heads/main/packages/lua/5.5/uint.zip...OK
WRITING .comexe/apm/uint.zip...OK
WRITING share\lua\5.5\uint.lua...OK
INSTALLED uint-0.186
Note: Packages are third-party software with their own LICENSES
```

### Use a package from a program

Note that the source file "main.lua" and the directory "share" should be placed together:
```
main.lua
share\lua\5.5\uint.lua
```

This is the example from the [uint documentation](https://github.com/SupTan85/lua-uint):

```lua title="main.lua"
-- require a module
local int = require("uint")

-- build a new int object
local x, y = int.new("20", "10")

print(x ^ y) -- output: 10240000000000
```

Run the program:

```sh
> lua55ce main.lua
10240000000000
```

## Manually

Just create the directory `share\lua\5.5\` and copy the files there. You will be able to call [require](https://www.lua.org/manual/5.5/manual.html#pdf-require) normally.
