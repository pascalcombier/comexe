--
-- This is an example of libtcc running a long main function while keeping
-- communication with Lua side by polling and calling ProcessEvents()
--
-- The key thing is to demonstrate a bi-directional communication:
-- The other threads communicate to libtcc by sending events PostEvent
-- libtcc process the event loop by doing some polling
-- libtcc calling Lua functions to communicate its status
--
-- This example is using libffi raw bindings because we focus on testing tcc
-- In a real program, it would be much easier to use the high level com.ffi

--------------------------------------------------------------------------------
-- IMPORT FUNCTIONS                                                           --
--------------------------------------------------------------------------------

local LibFfi  = require("com.raw.libffi")
local LibTcc  = require("com.raw.libtcc")
local Thread  = require("com.thread")
local Event   = require("com.event")
local Runtime = require("com.runtime")

local EventLoopRunOnce = Event.runonce

local tcc_new             = LibTcc.tcc_new
local tcc_set_output_type = LibTcc.tcc_set_output_type
local tcc_add_symbol      = LibTcc.tcc_add_symbol
local tcc_compile_string  = LibTcc.tcc_compile_string
local tcc_run             = LibTcc.tcc_run
local tcc_delete          = LibTcc.tcc_delete

--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS                                                            --
--------------------------------------------------------------------------------

local GLOBAL_LuaEventExitRequest = 0

local function SleepMs (Milliseconds)
  Runtime.sleepms(Milliseconds)
end

local function NeedExit ()
  return GLOBAL_LuaEventExitRequest
end

--------------------------------------------------------------------------------
-- PUBLIC EVENTS (CANNOT BE LOCAL)                                            --
--------------------------------------------------------------------------------

-- The Lua thread is exited, notify the tcc program
function WorkerExitEvent (ThreadId)
  Thread.join(ThreadId)
  GLOBAL_LuaEventExitRequest = 1
end

--------------------------------------------------------------------------------
-- C PROGRAM                                                                  --
--------------------------------------------------------------------------------

local CProgramString = Runtime.loadresource("program.c")

--------------------------------------------------------------------------------
-- IMPORT FUNCTIONS                                                           --
--------------------------------------------------------------------------------

function StartProgram ()
  -- Initialize TCC state
  local TccState = tcc_new()
  tcc_set_output_type(TccState, "memory")
  -- Make Lua functions callable by libtcc using new API
  local SleepMsCif       = LibFfi.newcif("void", "sint32")
  local ProcessEventsCif = LibFfi.newcif("void")
  local NeedExitCif      = LibFfi.newcif("sint32")
  local SleepMsClosure,       SleepMsPointer       = LibFfi.newclosure(SleepMsCif, SleepMs)
  local ProcessEventsClosure, ProcessEventsPointer = LibFfi.newclosure(ProcessEventsCif, EventLoopRunOnce)
  local NeedExitClosure,      NeedExitPointer      = LibFfi.newclosure(NeedExitCif,      NeedExit)
  -- Register the callbacks to libtcc
  tcc_add_symbol(TccState, "SleepMs",       SleepMsPointer)
  tcc_add_symbol(TccState, "ProcessEvents", ProcessEventsPointer)
  tcc_add_symbol(TccState, "NeedExit",      NeedExitPointer)
  -- Compile and run the program
  local Status, ErrorMessage = tcc_compile_string(TccState, CProgramString)
  assert((Status == 0), ErrorMessage)
  -- Create a worker thread who will send the WorkerExitEvent at some point
  local NewThread = Thread.create("worker", "WorkerExitEvent")
  Event.send(NewThread, "WaitAndClose", 5)
  -- Run the C program
  Status = tcc_run(TccState)
  assert((Status == 0), "main didnt return EXIT_SUCCESS (0)")
  -- Clean up
  tcc_delete(TccState)
  LibFfi.freeclosure(SleepMsClosure)
  LibFfi.freeclosure(ProcessEventsClosure)
  LibFfi.freeclosure(NeedExitClosure)
  LibFfi.freecif(SleepMsCif)
  LibFfi.freecif(ProcessEventsCif)
  LibFfi.freecif(NeedExitCif)
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

StartProgram()
