--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- This file contains a simple Read-Eval-Print-Loop (REPL) implementation for
-- the Lua ComEXE environment. It provides a basic interactive console where
-- users can input Lua code, which gets evaluated and the results are displayed.
--
-- The main function is TrivialRepl.Run(PrintFunction) which initializes and
-- runs the REPL loop.
--
-- This program tries to mimic default behaviour of Lua 54 REPL implemented in
-- lua.c, but is not 100% identical unfortunately, especially due to the <eof>
-- string matching which is not done in the original implementation.
--
-- Therefore, we keep the original issues with the former implementation, the
-- expression "return 'TEST', 1, 2, 3" will not quote the TEST string.
--
-- > TEST    1       2       3
--
-- The user can still provide its own PrintFunction as a parameter of
-- TrivialRepl.Run to allow pretty printing of the output.
--

--------------------------------------------------------------------------------
-- IMPORT FUNCTIONS                                                           --
--------------------------------------------------------------------------------

local format = string.format
local pack   = table.pack
local unpack = table.unpack
local read   = io.read
local write  = io.write
local stdout = io.stdout

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

-- We need to use table.pack because the expression local table = {...} does not
-- handle nil properly. With table.pack, nil are handled properly, the number of
-- elements in the resulting table is provided in table.n
local function REPL_CollectResults (Success, ...)
  local ErrorMessage
  local ReturnedValues
  if Success then
    ReturnedValues = pack(...)
  else
    local Data = pack(...)
    ErrorMessage = Data[1]
  end
  return Success, ErrorMessage, ReturnedValues
end

local function REPL_Eval (InputString)
  -- local variables
  local Success
  local ErrorMessageMessage
  local Results
  local Chunk
  -- First try to compile with "return" prefix (expression mode)
  local WithReturn = format("return %s", InputString)
  Chunk, ErrorMessageMessage = load(WithReturn, "=stdin")
  -- If expression compilation succeeds, execute it
  if Chunk then
    Success, ErrorMessage, Results = REPL_CollectResults(pcall(Chunk))
  else
    -- Otherwise, try as a regular statement
    Chunk, ErrorMessage = load(InputString, "=stdin")
    -- If statement compilation succeeds, execute it
    if Chunk then
      Success, ErrorMessage, Results = REPL_CollectResults(pcall(Chunk))
    else
      -- Both compilation attempts failed
      Success = false
      Results = nil
    end
  end
  -- return values
  return Success, ErrorMessage, Results
end

-- Default Print function. Result is a table from table.pack with the field
-- table.n representing the number of results
local function REPL_Print (Result)
  if (Result.n >= 1) then
    print(unpack(Result, 1, Result.n))
  end
end

-- Determine if input is incomplete by checking compilation errors
local function REPL_IsIncomplete (InputString)
  -- Try to compile the InputString
  local Succcess, ErrorString = load(InputString, "=stdin")
  -- Return true only if there is an ErrorString and it contains "<eof>"
  return (ErrorString and ErrorString:find("<eof>"))
end

local function REPL_Run (UserPrintFunction)
  -- Configure
  local PrintFunction = (UserPrintFunction or REPL_Print)
  -- Local variables
  local InputString = ""
  local MultiLine   = false
  local Continue    = true
  -- Run the loop
  while Continue do
    -- Show appropriate prompt
    if MultiLine then
      write(">> ")
    else
      write("> ")
    end
    stdout:flush()
    -- Read user input
    local Line = read()
    if (not Line) or ((not MultiLine) and (Line == "exit")) then
      Continue = false
    else
      -- Append the new line to existing InputString
      if MultiLine then
        InputString = format("%s\n%s", InputString, Line)
      else
        InputString = Line
      end
      -- Try to evaluate
      local Success, Error, Result = REPL_Eval(InputString)
      if Success then
        -- We have a valid result, print it
        PrintFunction(Result)
        -- Reset for next InputString
        InputString = ""
        MultiLine   = false
      else
        if REPL_IsIncomplete(InputString) then
          MultiLine = true
        else
          -- It's a syntax error or other error, like:
          -- if then end
          -- MyNonExistingFunc()
          -- for i=1,10 do print(i) end)
          -- local t={} print(t.test.test)
          print(Error)
          InputString = ""
          MultiLine   = false
        end
      end
    end
  end
  print()
end

--------------------------------------------------------------------------------
-- MODULE DEFINITION                                                          --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  Run = REPL_Run
}

return PUBLIC_API
