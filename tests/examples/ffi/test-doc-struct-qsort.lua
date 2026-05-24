--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local ffi = require("com.ffi")

local format = string.format

local libc = ffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so")
libc:load("tiny-libc-ffi")

local UserStruct = ffi.newstructure("User",
  ffi.int32_t, "Id",
  ffi.cstring, "Name",
  ffi.int32_t, "Age"
)

local function CompareByAge (PointerA, PointerB)
  local UserA = UserStruct:cast(PointerA)
  local UserB = UserStruct:cast(PointerB)
  return (UserA:getfield("Age") - UserB:getfield("Age"))
end

local CompareCallback = ffi.newcallback(CompareByAge, ffi.int32_t, ffi.pointer, ffi.pointer)

local function ConfigureUser (Array, Index, Id, Name, Age)
  local User = Array:get(Index)
  User:setfield("Id",   Id)
  User:setfield("Name", Name)
  User:setfield("Age",  Age)
end

local function PrintUsers (Array, Label)
  print(Label)
  local ElementCount = Array:getcount()
  for Index = 1, ElementCount do
    local User = Array:get(Index)
    local Name = User:getfield("Name")
    local Age  = User:getfield("Age")
    print(format("  %4.4s - Age %d", Name, Age))
  end
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local Users = ffi.newarray(UserStruct, 4)

ConfigureUser(Users, 1, 3, "Zoe",  28)
ConfigureUser(Users, 2, 1, "Amy",  35)
ConfigureUser(Users, 3, 4, "Carl", 22)
ConfigureUser(Users, 4, 2, "Bob",  42)

local UserStructSize = UserStruct:getsizeinbytes()
local ArrayPointer   = Users:getpointer()
local ComparePointer = CompareCallback:getpointer()

PrintUsers(Users, "Before")
local Count = Users:getcount()
libc.qsort(ArrayPointer, Count, UserStructSize, ComparePointer)
PrintUsers(Users, "After")
