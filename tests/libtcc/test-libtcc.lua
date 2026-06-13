local tcc     = require("libtcc")
local Runtime = require("com.runtime")

for Key, Value in pairs(tcc) do
  print(Key, Value)
end

tcc.tcc_main("hello.c", "-o", "hello.exe")

-- We use absolute path to avoid the Linux/Windows difference:
-- os.execute("hello.exe") for Windows
-- os.execute("./hello") for Linux
local ExeFile = Runtime.getrelativepath("hello.exe")

local Success, String, Number = os.execute(ExeFile)
assert(Success)
assert(String == "exit")
assert(Number == 0)

os.remove(ExeFile)
