local Runtime = require("com.runtime")

local format          = string.format
local getparam        = Runtime.getparam
local getrelativepath = Runtime.getrelativepath

local LuaExe     = getparam("LUA-EXE")
local HeaderFile = getrelativepath("tiny-libc.h")
local Command    = format([[%s -x --compile "%s"]], LuaExe, HeaderFile)

print(format("TRY %s", Command))

local Success, Reason, ExitCode = os.execute(Command)

if (ExitCode == 0) then
  print(format(" OK %s", Command))
else
  print(format("ERR  tiny-libc.h compilation failed with exit code %d", ExitCode))
  os.exit(1)
end
