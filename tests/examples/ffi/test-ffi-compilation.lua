local Runtime = require("com.runtime")

local format          = string.format
local getparam        = Runtime.getparam
local getrelativepath = Runtime.getrelativepath

local LuaExe = getparam("LUA-EXE")

local FFI_FILES = {
  "test-tiny-libc.lua",
  "test-doc-struct-qsort.lua",
  "test-win32-gui.lua",
}

for Index, Filename in ipairs(FFI_FILES) do
  local FilePath = getrelativepath(Filename)
  local Command  = format([[%s -x --preprocess "%s"]], LuaExe, FilePath)
  local Success, Reason, ExitCode = os.execute(Command)
  if (ExitCode == 0) then
    print(format(" OK %s", Filename))
  else
    print(format("ERR %s preprocessing failed with exit code %d", Filename, ExitCode))
    os.exit(1)
  end
end