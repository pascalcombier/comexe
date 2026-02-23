--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local LibTcc  = require("com.raw.libtcc")
local LibFfi  = require("com.raw.libffi")
local Runtime = require("com.runtime")

local format = string.format

local tcc_new             = LibTcc.tcc_new
local tcc_set_output_type = LibTcc.tcc_set_output_type
local tcc_add_symbol      = LibTcc.tcc_add_symbol
local tcc_compile_string  = LibTcc.tcc_compile_string
local tcc_run             = LibTcc.tcc_run
local tcc_delete          = LibTcc.tcc_delete
local tcc_get_luastate    = LibTcc.tcc_get_luastate
local NULL                = LibFfi.NULL

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function TCC_LoadLuaStandardLibrary (TccState)
  -- Retrieve the Lua library symbols
  local Symbols = LibTcc.tcc_get_lualib()
  -- Register them into TCC state
  for SymbolName, SymbolAddress in pairs(Symbols) do
    -- tcc_add_symbol always returns 0
    tcc_add_symbol(TccState, SymbolName, SymbolAddress)
    print("IMPORT", SymbolName, SymbolAddress)
  end
end

--------------------------------------------------------------------------------
-- INTERFACE LUA AND TCC                                                      --
--------------------------------------------------------------------------------

local function GetLuaState ()
  return tcc_get_luastate()
end

local GetLuaStateCif = LibFfi.newcif("pointer")
assert(GetLuaStateCif)

local GetLuaStateClosure, GetLuaStatePointer = LibFfi.newclosure(GetLuaStateCif, GetLuaState)

assert((GetLuaStateClosure ~= NULL), "Failed to allocate closure")
assert((GetLuaStatePointer ~= NULL), "Failed to get closure pointer")

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local SourceC = Runtime.loadresource("test-extends-lua.c")
assert(SourceC, "Missing C source file")

local TccState = tcc_new()
tcc_set_output_type(TccState, "memory")

-- tcc_add_symbol always returns 0
tcc_add_symbol(TccState, "GetLuaState", GetLuaStatePointer)

-- Load functions like lua_createtable, lua_settop, etc into tcc state
TCC_LoadLuaStandardLibrary(TccState)

local CompileResult = tcc_compile_string(TccState, SourceC)
assert((CompileResult == 0), format("Compilation failed (%d)", CompileResult))

-- Call tcc:main() to register the module
local RunResult = tcc_run(TccState)
assert((RunResult == 0), format("Execution failed (%d)", RunResult))

-- Try to load the Tcc library and use it
local TccModule = require("example")
TccModule.cprint("HELLO-FROM-LUA")

-- Release the resources
tcc_delete(TccState)
LibFfi.freeclosure(GetLuaStateClosure)
LibFfi.freecif(GetLuaStateCif)
