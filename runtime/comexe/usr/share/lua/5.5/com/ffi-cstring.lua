--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- This module provides C-string support for:
-- ffi.lua
-- ffi-structure.lua

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.raw.libffi")

local allocstring = libffi.allocstring
local readstring  = libffi.readstring
local free        = libffi.free

-- Global constant
local CSTRING = {}

--------------------------------------------------------------------------------
-- TRIVIAL C-STRING                                                           --
--------------------------------------------------------------------------------

local function CSTRING_MethodGetPointer (CString)
  local Pointer = CString.Pointer
  return Pointer
end

local function CSTRING_MethodToString (CString)
  local Pointer = CString.Pointer
  return readstring(Pointer)
end

local function CSTRING_MethodFree (CString)
  local Pointer = CString.Pointer
  free(Pointer)
end

local CSTRING_Metatable = {
  -- METATABLE_LuaDefinedMethods
  __gc       = CSTRING_MethodFree,
  __tostring = CSTRING_MethodToString,
  -- METATABLE_UserDefinedMethods
  __index = {
    getpointer = CSTRING_MethodGetPointer,
  },
}

local function NewCString (LuaString)
  -- Allocate the string in the C side
  local Pointer = allocstring(LuaString)
  -- Create a new Lua wrapper
  local NewStringObject = {
    Pointer = Pointer,
  }
  -- Attach metatable
  setmetatable(NewStringObject, CSTRING_Metatable)
  -- Return value
  return NewStringObject
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  cstring    = CSTRING,
  newcstring = NewCString,
}

return PUBLIC_API