local Runtime = require("com.runtime")

local function WAIT_SECONDS (Seconds)
  local TimeoutMs = (Seconds * 1000)
  Runtime.sleepms(TimeoutMs)
end

io.write("WAIT..")
io.flush()
WAIT_SECONDS(1)
io.write(".")
io.flush()
WAIT_SECONDS(1)
print("OK")
