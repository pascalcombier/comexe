--
-- Test calling Lua from libtcc using LibFfi
--
-- This is named "closure" because in LibFfi the functions are:
-- ffi_closure_alloc
-- ffi_prep_closure_loc
-- ffi_closure_free
--

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local LibTcc = require("com.raw.libtcc")
local LibFfi = require("com.raw.libffi")

local tcc_new             = LibTcc.tcc_new
local tcc_set_output_type = LibTcc.tcc_set_output_type
local tcc_add_symbol      = LibTcc.tcc_add_symbol
local tcc_compile_string  = LibTcc.tcc_compile_string
local tcc_run             = LibTcc.tcc_run
local tcc_delete          = LibTcc.tcc_delete

--------------------------------------------------------------------------------
-- MAIN TEST FUNCTION                                                         --
--------------------------------------------------------------------------------

local ProgramC = [[
#include <stdio.h>

extern int LuaAdd(int a, int b);

int main ()
{
  int Result = LuaAdd(10, 20);
  return 0;
}
]]

--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS                                                            --
--------------------------------------------------------------------------------

local function LuaAdd (a, b)
  return a + b
end

local LuaAddCif = LibFfi.newcif("sint32", "sint32", "sint32")
assert(LuaAddCif)

local LuaClosure, LuaAddPointer = LibFfi.newclosure(LuaAddCif, LuaAdd)
assert(LuaClosure    ~= LibFfi.NULL)
assert(LuaAddPointer ~= LibFfi.NULL)

--------------------------------------------------------------------------------
-- MAIN SCRIPT                                                                --
--------------------------------------------------------------------------------

local TccState = tcc_new()
tcc_set_output_type(TccState, "memory")

local Result = tcc_add_symbol(TccState, "LuaAdd", LuaAddPointer)

-- Compile and run
Result = tcc_compile_string(TccState, ProgramC)
if (Result == 0) then
  Result = tcc_run(TccState)
else
  os.exit(1)
end

-- Clean up
tcc_delete(TccState)

-- Free closure and CIF
LibFfi.freeclosure(LuaClosure)
LibFfi.freecif(LuaAddCif)

-- Test result
os.exit(Result)