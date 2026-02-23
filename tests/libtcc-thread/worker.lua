--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Event   = require("com.event")
local Runtime = require("com.runtime")

local tointeger = math.tointeger
local sleepms   = Runtime.sleepms

--------------------------------------------------------------------------------
-- PUBLIC EVENTS (CANNOT BE LOCAL)                                            --
--------------------------------------------------------------------------------

function WaitAndClose (TimeoutSeconds)
  local TimeoutMs = tointeger(TimeoutSeconds * 1000)
  sleepms(TimeoutMs)
  Event.stoploop()
end

--------------------------------------------------------------------------------
-- MAIN SCRIPT                                                                --
--------------------------------------------------------------------------------

-- Wait for Event.stoploop()
Event.runloop()
