local LibTcc  = require("com.raw.libtcc")
local Runtime = require("com.runtime")

local InputFile  = Runtime.getrelativepath("hello.c")
local OutputFile = Runtime.getrelativepath("hello.exe")

local RunTccExe  = LibTcc.tcc_main
local ReturnCode = RunTccExe("-vv", InputFile, "-o", OutputFile)

if (ReturnCode == 0) then
  local Success, ExitType, ExitCode = os.execute(OutputFile)
  if not Success then
    os.exit(ExitCode)
  end
else
  os.exit(ReturnCode)
end