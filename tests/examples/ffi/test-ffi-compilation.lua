local Runtime = require("com.runtime")

local format          = string.format
local getparam        = Runtime.getparam
local getrelativepath = Runtime.getrelativepath

local LuaExe = getparam("LUA-EXE")

local HEADERS = {
  "tiny-libc.h",
  "tiny-sqlite3.h",
}

for Index, HeaderFilename in ipairs(HEADERS) do
  local HeaderFile = getrelativepath(HeaderFilename)
  local Command    = format([[%s -x --compile "%s"]], LuaExe, HeaderFile)
  local Success, Reason, ExitCode = os.execute(Command)
  if (ExitCode == 0) then
    print(format(" OK %s", HeaderFilename))
  else
    print(format("ERR %s compilation failed with exit code %d", HeaderFilename, ExitCode))
    os.exit(1)
  end
end