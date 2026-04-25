--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.ffi")

assert(libffi)
assert(libffi.loadlib)
assert(libffi.sint32)
assert(libffi.pointer)

local sint32  = libffi.sint32
local uint64  = libffi.uint64
local pointer = libffi.pointer
local NULL    = libffi.NULL

local Libc = libffi.loadlib("msvcrt.dll")
assert(Libc)

--------------------------------------------------------------------------------
-- BASIC VARIADIC CALLS                                                       --
--------------------------------------------------------------------------------

local BufferSize = 256
local Buffer = libffi.malloc(BufferSize)
assert(Buffer ~= NULL)

local Sprintf = Libc:getvariadic(sint32, "sprintf", pointer)
assert(Sprintf)

local SprintfS = Libc:getvariadic(sint32, "sprintf_s", pointer, uint64, pointer)
assert(SprintfS)

local function CheckSprintf (Expected, FormatString, ...)
  local Length = Sprintf(Buffer, FormatString, ...)
  assert((Length > 0))
  local Result = libffi.readmemory(Buffer, 0, Length)
  assert((Result == Expected))
end

CheckSprintf(string.format("%s %d", "flag", 1),       "%s %d", "flag", true)
CheckSprintf(string.format("%s %d", "flag", 0),       "%s %d", "flag", false)
CheckSprintf(string.format("%s %.2f", "value", 3.25), "%s %.2f", "value", 3.25)
CheckSprintf(string.format("%s %s %.2f", "left", "right", 1.5), "%s %s %.2f", "left", "right", 1.5)

--------------------------------------------------------------------------------
-- SECOND FUNCTION NAME                                                       --
--------------------------------------------------------------------------------

local Length = SprintfS(Buffer, BufferSize, "%s %d", "flag", true)
assert((Length > 0))
local Result = libffi.readmemory(Buffer, 0, Length)
assert((Result == string.format("%s %d", "flag", 1)))

--------------------------------------------------------------------------------
-- CACHE REUSE                                                                --
--------------------------------------------------------------------------------

CheckSprintf(string.format("%s %d", "flag", 1), "%s %d", "flag", true)

libffi.free(Buffer)