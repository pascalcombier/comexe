--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local runtime = require("com.runtime")
local ffi     = require("com.ffi")

local format   = string.format
local getparam = runtime.getparam
local sizeof   = ffi.sizeof

local pointer = ffi.pointer
local cstring = ffi.cstring

-- We test with the PUBLIC_API, not internal libffi type names (sint32, etc)
local int8_t   = ffi.int8_t
local uint8_t  = ffi.uint8_t
local int16_t  = ffi.int16_t
local uint16_t = ffi.uint16_t
local int32_t  = ffi.int32_t
local uint32_t = ffi.uint32_t
local int64_t  = ffi.int64_t
local uint64_t = ffi.uint64_t
local float    = ffi.float
local double   = ffi.double

--------------------------------------------------------------------------------
-- TESTS                                                                      --
--------------------------------------------------------------------------------

local POINTER_SIZE = sizeof(pointer)

-- Test pointer size against architecture
local Arch = getparam("ARCH")
if (Arch == "x86_64") then
  assert((POINTER_SIZE == 8), format("pointer size should be 8 on x86_64, got %d", POINTER_SIZE))
elseif (Arch == "x86") then
  assert((POINTER_SIZE == 4), format("pointer size should be 4 on x86, got %d", POINTER_SIZE))
end

-- Test structure with a single pointer field
local PointerStruct = ffi.newstructure("TestStruct",
  pointer, "Pointer"
)
local StructSize = sizeof(PointerStruct)
assert((StructSize == POINTER_SIZE), format("struct with one pointer should be %d bytes, got %d", POINTER_SIZE, StructSize))

-- Test primitive type sizes
assert((sizeof(int8_t)   == 1))
assert((sizeof(uint8_t)  == 1))
assert((sizeof(int16_t)  == 2))
assert((sizeof(uint16_t) == 2))
assert((sizeof(int32_t)  == 4))
assert((sizeof(uint32_t) == 4))
assert((sizeof(int64_t)  == 8))
assert((sizeof(uint64_t) == 8))
assert((sizeof(float)    == 4))
assert((sizeof(double)   == 8))

-- Test cstring resolves to pointer size
assert((sizeof(cstring) == POINTER_SIZE))

-- libffi actually sets the size of void to 1
assert((sizeof(ffi.void) == 1))

print("OK")
