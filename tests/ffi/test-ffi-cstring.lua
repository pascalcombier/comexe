--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local ffi = require("com.ffi")

local format = string.format

local uint64  = ffi.uint64
local sint32  = ffi.sint32
local pointer = ffi.pointer
local cstring = ffi.cstring
local NULL    = ffi.NULL

local Libc = ffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so")
assert(Libc)

--------------------------------------------------------------------------------
-- GETENV RETURNING C-STRING                                                  --
--------------------------------------------------------------------------------

local getenv = Libc:bind(cstring, "getenv", cstring)
assert(getenv)

local PathValue = getenv("PATH")
assert((type(PathValue) == "string"), "cstring return should convert to Lua string")
assert((#PathValue > 0), "PATH should not be empty")

local strstr = Libc:bind(cstring, "strstr", cstring, cstring)
assert(strstr)

local Found = strstr("hello world", "world")
assert((type(Found) == "string"), "strstr cstring return should be a Lua string")
assert((Found == "world"), "strstr should find the substring")

-- strstr with no match returns NULL, returning nil (not NULL)
-- because it use "cstring"
local NotFound = strstr("hello", "xyz")
assert((NotFound == nil), "strstr NULL result should be nil")

-- strlen takes cstring, returns uint64
local strlen = Libc:bind(uint64, "strlen", cstring)
assert(strlen)

local Length = strlen("abcdef")
assert((Length == 6), "strlen should return 6")

-- variadicbind with cstring
local BufferSize = 256
local Buffer = ffi.malloc(BufferSize)
assert(Buffer ~= NULL)

local sprintf = Libc:variadicbind(sint32, "sprintf", pointer)
assert(sprintf)
local SprintfLength = sprintf(Buffer, "%s %d", "test", 42)
assert((SprintfLength > 0))
local SprintfResult = ffi.readmemory(Buffer, 0, SprintfLength)
assert((SprintfResult == "test 42"))

ffi.free(Buffer)

--------------------------------------------------------------------------------
-- GETENV RETURNING GENERIC POINTER                                           --
--------------------------------------------------------------------------------

-- Same as getenv but return pointer (lightuserdata)
local getenv2 = Libc:bind(pointer, "getenv", cstring)
assert(getenv2)

local RawPointer = getenv2("PATH")
assert((type(RawPointer) == "userdata"), "pointer return should still be lightuserdata")

local ReadBack = ffi.readstring(RawPointer)
assert((type(ReadBack) == "string"))
assert((#ReadBack > 0))

--------------------------------------------------------------------------------
-- newcstring                                                                 --
--------------------------------------------------------------------------------

local ManagedString = ffi.newcstring("hello")
assert((type(ManagedString) == "table"))
assert((tostring(ManagedString) == "hello"))
assert((type(ManagedString:getpointer()) == "userdata"), "getpointer should return a lightuserdata")

-- Empty string
local EmptyString = ffi.newcstring("")
assert((type(EmptyString) == "table"))
assert((tostring(EmptyString) == ""))
assert((EmptyString:getpointer() ~= NULL))

-- newcstring in pointer array
local PointerArray = ffi.newarray(pointer, 2)
assert((#PointerArray == 2))
local NameObject = ffi.newcstring("Bob")
PointerArray:set(1, NameObject)
PointerArray:set(2, NULL)

local ReadPointer = PointerArray:get(1)
assert((type(ReadPointer) == "userdata"))
local ReadString = ffi.readstring(ReadPointer)
assert((ReadString == "Bob"))

local ReadNull = PointerArray:get(2)
assert((ReadNull == NULL))

-- newcstring pointer passed to struct field (pointer type, manual)
local UserStructV1, UserErrorV1 = ffi.newstructure("TestUserV1",
                                                    sint32,  "Id",
                                                    pointer, "Name")
assert(UserStructV1, UserErrorV1)

local UserInstanceV1 = ffi.newinstance(UserStructV1)
local UserName       = ffi.newcstring("Zoe")

UserInstanceV1:setfield("Id", 42)
UserInstanceV1:setfield("Name", UserName:getpointer())

assert((UserInstanceV1:getfield("Id") == 42))
local NameFieldPtrV1 = UserInstanceV1:getfield("Name")
assert((type(NameFieldPtrV1) == "userdata"))
assert((ffi.readstring(NameFieldPtrV1) == "Zoe"))

--------------------------------------------------------------------------------
-- CSTRING FIELDS IN STRUCTURES (AUTOMATIC CONVERSION)                        --
--------------------------------------------------------------------------------

-- Named structure with cstring field
local UserStruct, UserError = ffi.newstructure("TestUser",
                                               sint32,  "Id",
                                               cstring, "Name")
assert(UserStruct, UserError)

-- Anonymous structure with cstring field
local AnonStruct, AnonError = ffi.newstructurea(cstring, sint32)
assert(AnonStruct, AnonError)

-- Create instance and set fields
local UserInstance = ffi.newinstance(UserStruct)
assert((type(UserInstance) == "table"))
assert(UserInstance.getpointer)

-- Set cstring field with Lua string
UserInstance:setfield("Id", 42)
UserInstance:setfield("Name", "Zoe")
assert((UserInstance:getfield("Id") == 42))

-- Read cstring field: should return Lua string automatically
local NameValue = UserInstance:getfield("Name")
assert((type(NameValue) == "string"), format("cstring field get should return string, got %s", type(NameValue)))
assert((NameValue == "Zoe"), format("Expected 'Zoe', got %q", NameValue))

-- Set cstring field to nil (NULL pointer)
UserInstance:setfield("Name", nil)
local NilName = UserInstance:getfield("Name")
assert((NilName == nil), format("cstring field with NULL should return nil, got %s", tostring(NilName)))

-- Re-set cstring field (old allocation should be freed, new one allocated)
UserInstance:setfield("Name", "Alice")
local ReSetName = UserInstance:getfield("Name")
assert((ReSetName == "Alice"), format("Expected 'Alice', got %q", ReSetName))

-- Multiple re-sets should not leak memory
UserInstance:setfield("Name", "Bob")
assert((UserInstance:getfield("Name") == "Bob"))
UserInstance:setfield("Name", "Charlie")
assert((UserInstance:getfield("Name") == "Charlie"))

-- Anonymous structure: set by index
local AnonInstance = ffi.newinstance(AnonStruct)
AnonInstance:set(1, "Hello")
AnonInstance:set(2, 99)
local AnonStr = AnonInstance:get(1)
assert((type(AnonStr) == "string"), "anonymous cstring field get should return string")
assert((AnonStr == "Hello"))
assert((AnonInstance:get(2) == 99))

AnonInstance:set(1, nil)
assert((AnonInstance:get(1) == nil), "anonymous cstring field nil should return nil")

-- Structure with multiple cstring fields
local MultiStringStruct, MultiError = ffi.newstructure("MultiCString",
                                                       cstring, "First",
                                                       cstring, "Second")
assert(MultiStringStruct, MultiError)

local MultiInstance = ffi.newinstance(MultiStringStruct)
MultiInstance:setfield("First", "One")
MultiInstance:setfield("Second", "Two")
assert((MultiInstance:getfield("First") == "One"))
assert((MultiInstance:getfield("Second") == "Two"))

-- Partial nil
MultiInstance:setfield("First", nil)
assert((MultiInstance:getfield("First") == nil))
assert((MultiInstance:getfield("Second") == "Two"))

-- Set back
MultiInstance:setfield("First", "Updated")
assert((MultiInstance:getfield("First") == "Updated"))

-- GC cleanup: instance GC should free tracked cstring allocations
UserInstanceV1    = nil
UserInstance      = nil
AnonInstance      = nil
MultiInstance     = nil
MultiStringStruct = nil
AnonStruct        = nil
UserStruct        = nil
UserStructV1      = nil

collectgarbage()
collectgarbage()

--------------------------------------------------------------------------------
-- FINAL CLEANUP                                                              --
--------------------------------------------------------------------------------

ManagedString = nil
EmptyString   = nil
NameObject    = nil
UserName      = nil
PointerArray  = nil

collectgarbage()
collectgarbage()

print("OK")
