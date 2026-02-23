-- This test is there because at some point we had a silent regression in
-- lua55ce for global variables, breaking the thread/events API.

-- This initial code was wrong in lua55ce because it impact lua_getglobal and
-- prevent the creation of new global variables
-- We now provide _G directly to loadfile
--
-- local function LoadFile (LuaScriptFilename, Arguments)
--   -- Create a metatable for the environment
--   local Metatable = {
--     __index = _G
--   }
--   -- Create a custom environment and store the arguments
--   local NewEnvironment = {
--     arg = Arguments
--   }
--   setmetatable(NewEnvironment, Metatable)
--   -- Load the script with the custom environment
--   local Chunk, ErrorString = loadfile(LuaScriptFilename, "bt", NewEnvironment)
--   TryChunk(Chunk, ErrorString)
-- end
--

function TEST_IN_GLOBAL ()
end

local TestGlobal = _G["TEST_IN_GLOBAL"]
if (TestGlobal == nil) then
  os.exit(1)
else
  os.exit(0)
end
