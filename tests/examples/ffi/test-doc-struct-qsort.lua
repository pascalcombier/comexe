--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.ffi")

local format = string.format

--------------------------------------------------------------------------------
-- FFI IMPORTS                                                                --
--------------------------------------------------------------------------------

-- @BEGIN import-c-header
-- @PARAM file tiny-libc.h
-- @PARAM function BindLibrary
-- @PARAM lib libffi
-- @OUTPUT
-- Functions
local free
local malloc
local puts
local qsort
local sprintf
-- Binding function
local function BindLibrary (Library)
  free = Library:bind(libffi.void, "free", libffi.pointer)
  malloc = Library:bind(libffi.pointer, "malloc", libffi.uint64)
  puts = Library:bind(libffi.sint32, "puts", libffi.pointer)
  qsort = Library:bind(libffi.void, "qsort", libffi.pointer, libffi.uint64, libffi.uint64, libffi.pointer)
  sprintf = Library:variadicbind(libffi.sint32, "sprintf", libffi.pointer, libffi.pointer)
end
-- @END

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so", "linux", "libc.so.6")
BindLibrary(libc)

local UserStruct = libffi.newstructure("User",
  libffi.int32_t, "Id",
  libffi.cstring, "Name",
  libffi.int32_t, "Age"
)

local function CompareByAge (PointerA, PointerB)
  local UserA = UserStruct:cast(PointerA)
  local UserB = UserStruct:cast(PointerB)
  return (UserA:get("Age") - UserB:get("Age"))
end

local CompareCallback = libffi.newcallback(CompareByAge, libffi.int32_t, libffi.pointer, libffi.pointer)

local function ConfigureUser (Array, Index, Id, Name, Age)
  local User = Array:get(Index)
  User:set("Id",   Id)
  User:set("Name", Name)
  User:set("Age",  Age)
end

local function PrintUsers (Array, Label)
  print(Label)
  local ElementCount = Array:getcount()
  for Index = 1, ElementCount do
    local User = Array:get(Index)
    local Name = User:get("Name")
    local Age  = User:get("Age")
    print(format("  %4.4s - Age %d", Name, Age))
  end
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local Users = libffi.newarray(UserStruct, 4)

ConfigureUser(Users, 1, 3, "Zoe",  28)
ConfigureUser(Users, 2, 1, "Amy",  35)
ConfigureUser(Users, 3, 4, "Carl", 22)
ConfigureUser(Users, 4, 2, "Bob",  42)

local UserStructSize = libffi.sizeof(UserStruct)
local ArrayPointer   = Users:getpointer()
local ComparePointer = CompareCallback:getpointer()

PrintUsers(Users, "Before")
local Count = Users:getcount()
qsort(ArrayPointer, Count, UserStructSize, ComparePointer)
PrintUsers(Users, "After")
