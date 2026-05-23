local uv = require("luv")

local Thread = require("com.thread")
local Event  = require("com.event")

-- Called when my-thread.lua exits
function EventMyThreadExit (ThreadId)
  Thread.join(ThreadId) -- Release the thread ID
  Event.stoploop()      -- Stop the loop
end

-- Create a new thread and load my-thread.lua
local ThreadId = Thread.create("my-thread", "EventMyThreadExit")

uv.sleep(1000)
Event.send(ThreadId, "EventDoSomething", 1, true, false, nil)
uv.sleep(1000)

Event.send(ThreadId, "EventExitThread")

-- Block until stoploop() is called
Event.runloop()
print("test-doc-main-thread closed")
