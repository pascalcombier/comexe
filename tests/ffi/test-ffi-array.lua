--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.raw.libffi")
local ffi    = require("com.ffi")

assert(libffi)
assert(ffi)
assert(libffi.sint32)
assert(libffi.NULL)

local sint32  = libffi.sint32
local pointer = libffi.pointer

local newinstance = ffi.newinstance

--------------------------------------------------------------------------------
-- C ARRAYS HIGH-LEVEL COM.FFI                                                --
--------------------------------------------------------------------------------

local PairStruct, PairTypeError = ffi.newstructure("Pair",
                                                   "First",  sint32,
                                                   "Second", sint32)
assert(PairStruct, PairTypeError)
assert(PairStruct.getsizeinbytes)
assert(PairStruct.getalignment)
assert(PairStruct.getoffsets)

local NumberArray = ffi.newarray(sint32, 3)
assert((#NumberArray == 3))

NumberArray:set(1, 11)
NumberArray:set(2, 22)
NumberArray:set(3, 33)

assert((NumberArray:get(1) == 11))
assert((NumberArray:get(2) == 22))
assert((NumberArray:get(3) == 33))

local NumberArrayPointer = NumberArray:getpointer()
assert((type(NumberArrayPointer) == "userdata"))

NumberArray:set(5000, 999)
local NumberArrayPointerAfterResize = NumberArray:getpointer()
assert((type(NumberArrayPointerAfterResize) == "userdata"))
assert((#NumberArray == 5000))
assert((NumberArray:get(1) == 11))
assert((NumberArray:get(2) == 22))
assert((NumberArray:get(3) == 33))
assert((NumberArray:get(5000) == 999))

local PairValueArray = ffi.newarray(PairStruct, 1)
local PairValueItem  = newinstance(PairStruct)
PairValueItem:setfield("First", 123)
PairValueItem:setfield("Second", 456)
PairValueArray:set(1, PairValueItem)

local PairValueRead = PairValueArray:get(1)
assert((type(PairValueRead) == "table"))
assert((PairValueRead:getfield("First") == 123))
assert((PairValueRead:getfield("Second") == 456))

local PointerArray = ffi.newarray(pointer, 3)
local ExternalPointer = ffi.malloc(32)
assert((type(ExternalPointer) == "userdata"))

PointerArray:set(1, nil)
PointerArray:set(2, ExternalPointer)
PointerArray:set(3, NumberArray)

assert((PointerArray:get(1) == libffi.NULL))
assert((PointerArray:get(2) == ExternalPointer))
assert((PointerArray:get(3) == NumberArray:getpointer()))

-- nil on a struct array zero-initializes the element
PairValueArray:set(1, nil)
local ZeroedValue = PairValueArray:get(1)
assert((type(ZeroedValue) == "table"))
assert((ZeroedValue:getfield("First") == 0))
assert((ZeroedValue:getfield("Second") == 0))

local PointerStringSetOk, PointerStringSetError = pcall(function ()
    PointerArray:set(1, "abc")
end)
assert(not PointerStringSetOk)
assert((type(PointerStringSetError) == "string"))
assert((string.find(PointerStringSetError, "allocstring", 1, true) ~= nil))

local PointerInvalidSetOk, PointerInvalidSetError = pcall(function ()
    PointerArray:set(1, {})
end)
assert(not PointerInvalidSetOk)
assert((type(PointerInvalidSetError) == "string"))
assert((string.find(PointerInvalidSetError, "pointer array expects nil, userdata, or object with getpointer() method", 1, true) ~= nil))

ffi.free(ExternalPointer)

NumberArray    = nil
PairValueArray = nil
PointerArray   = nil
PairStruct     = nil

collectgarbage()
collectgarbage()