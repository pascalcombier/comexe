--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local ffi = require("com.ffi")

local void    = ffi.void
local sint32  = ffi.sint32
local pointer = ffi.pointer
local size_t  = ffi.size_t

--------------------------------------------------------------------------------
-- USER                                                                       --
--------------------------------------------------------------------------------

local UserStruct = ffi.newstructure("User",
  "Id",   sint32,
  "Name", pointer)

local UserStructSize = UserStruct:getsizeinbytes()

local function PrintUsers (Users)
  local Count = #Users
  for Index = 1, Count do
    local User = Users[Index]
    local UserId          = User:getfield("Id")
    local UserNamePointer = User:getfield("Name")
    local Name = ffi.readstring(UserNamePointer)
    print(string.format("id:%2.2d - %s", UserId, Name))
  end
end

local function CompareUsersById (PointerA, PointerB)
  -- Create Lua objects from pointers
  local UserA = UserStruct:frompointer(PointerA)
  local UserB = UserStruct:frompointer(PointerB)
  -- Read fields
  local UserIdA = UserA:getfield("Id")
  local UserIdB = UserB:getfield("Id")
  -- Compare
  return (UserIdA - UserIdB)
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local Libc  = ffi.loadlib("msvcrt.dll")
local Qsort = Libc:getfunction(void, "qsort", pointer, size_t, size_t, pointer)

local INIT_Data = {
  { Name = "Zoe",  Id = 3 },
  { Name = "Amy",  Id = 1 },
  { Name = "Carl", Id = 4 },
  { Name = "Bob",  Id = 2 },
}

local Count = #INIT_Data
local Users = UserStruct:newarray(Count)

local FirstUser         = Users[1]
local ArrayStartPointer = FirstUser:getpointer()

for Index = 1, Count do
  local User        = Users[Index]
  local NamePointer = ffi.allocstring(INIT_Data[Index].Name)
  User:setfield("Id", INIT_Data[Index].Id)
  User:setfield("Name", NamePointer)
end

local CompareClosure, CompareUserByIdPointer = ffi.newcfunction(CompareUsersById, sint32, pointer, pointer)

print("BEFORE qsort")
PrintUsers(Users)
Qsort(ArrayStartPointer, Count, UserStructSize, CompareUserByIdPointer)
print(" AFTER qsort")
PrintUsers(Users)

for Index = 1, Count do
  local User        = Users[Index]
  local NamePointer = User:getfield("Name")
  ffi.free(NamePointer)
  User:setfield("Name", nil)
end

print("OK")