local Thread = require("com.thread")
local Event  = require("com.event")

function WorkerExitEvent (ThreadId)
  print("JOINING...")
  Thread.join(ThreadId)
  print("CLOSING...")
  Event.stoploop()
end

print("CREATE THREAD")
local NewThread = Thread.create("worker", "WorkerExitEvent")
print("THREAD ID", NewThread)
print("RUNNING...")
Event.runloop()
print("CLOSED...")