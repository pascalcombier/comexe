--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.raw.libffi")
assert(libffi)

local Libc = libffi.loadlib("msvcrt.dll")
assert(Libc)

local NULL = libffi.NULL

--------------------------------------------------------------------------------
-- CALL C FROM LUA [PUTS]                                                     --
--------------------------------------------------------------------------------

local PutsAddress = libffi.getproc(Libc, "puts")
assert(PutsAddress)

local PutsCif = libffi.newcif("sint32", "string")
assert(PutsCif)
local PutsCallContext = libffi.newcallcontext(PutsCif)
assert(PutsCallContext)
local PutsReturnValue = libffi.call(PutsCallContext, PutsAddress, "CALL-LIBC-PUTS")
assert(not(PutsReturnValue < 0))
libffi.freecallcontext(PutsCallContext)
libffi.freecif(PutsCif)

--------------------------------------------------------------------------------
-- SNPRINTF                                                                   --
--------------------------------------------------------------------------------

local SprintfAddress = libffi.getproc(Libc, "sprintf")
assert(SprintfAddress ~= NULL)

local SprintfCif = libffi.newcif("sint32", "pointer", "string", "string", "sint32", "double")
assert(SprintfCif)
local SprintfCallContext = libffi.newcallcontext(SprintfCif)
assert(SprintfCallContext)
local BufferSize = 128
local Buffer     = libffi.malloc(BufferSize)
assert(Buffer ~= NULL)
local FormatString = "%s %d %f"
local StringArg    = "Hello"
local IntArg       = 42
local FloatArg     = 3.14
local SprintfReturnValue = libffi.call(SprintfCallContext, SprintfAddress, Buffer, FormatString, StringArg, IntArg, FloatArg)
assert(SprintfReturnValue > 0)
local ResultString = libffi.readpointer(Buffer, 0, SprintfReturnValue)
local ExpectedString = string.format(FormatString, StringArg, IntArg, FloatArg)
assert(ResultString == ExpectedString)
libffi.free(Buffer)
libffi.freecallcontext(SprintfCallContext)
libffi.freecif(SprintfCif)

--------------------------------------------------------------------------------
-- UTILITIES                                                                  --
--------------------------------------------------------------------------------

local MemcpyAddress = libffi.getproc(Libc, "memcpy")
assert(MemcpyAddress ~= NULL)

local MemcpyCif = libffi.newcif("pointer", "pointer", "pointer", "sint32")
assert(MemcpyCif)

local function LuaArrayToC(Array, UserIntegerSizeInBytes)
  local IntegerSizeInBytes = (UserIntegerSizeInBytes or 4)
  local ArrayLength = #Array
  local SizeInBytes = ArrayLength * IntegerSizeInBytes
  local ArrayPointer = libffi.malloc(SizeInBytes)
  assert(ArrayPointer)
  for Index = 1, ArrayLength do
    local Offset = ((Index - 1) * IntegerSizeInBytes)
    local String = string.pack("i", Array[Index])
    local Pointer = libffi.pointeroffset(ArrayPointer, Offset)
    local MemcpyCallContext = libffi.newcallcontext(MemcpyCif)
    assert(MemcpyCallContext)
    libffi.call(MemcpyCallContext, MemcpyAddress, Pointer, String, IntegerSizeInBytes)
    libffi.freecallcontext(MemcpyCallContext)
  end
  return ArrayPointer, ArrayLength
end

local function CArrayToLua(Array, Length, UserIntegerSizeInBytes)
  -- Default value
  local IntegerSizeInBytes = (UserIntegerSizeInBytes or 4)
  -- Conversion
  local Result = {}
  for Index = 1, Length do
    local Offset = ((Index - 1) * IntegerSizeInBytes)
    local Bytes = libffi.readpointer(Array, Offset, IntegerSizeInBytes)
    local Value = string.unpack("i", Bytes)
    Result[Index] = Value
  end
  return Result
end

--------------------------------------------------------------------------------
-- CALL LUA FROM C                                                            --
--------------------------------------------------------------------------------

local QsortAddress = libffi.getproc(Libc, "qsort")
assert(QsortAddress ~= NULL)

local QsortCif = libffi.newcif("void", "pointer", "sint32", "sint32", "pointer")
assert(QsortCif)

local function LuaCompareFunction(PointerA, PointerB)
  local PointerStringA = libffi.readpointer(PointerA, 0, 4)
  local PointerStringB = libffi.readpointer(PointerB, 0, 4)
  local IntegerA = string.unpack("i", PointerStringA)
  local IntegerB = string.unpack("i", PointerStringB)
  return (IntegerA - IntegerB)
end

local QsortCallContext = libffi.newcallcontext(QsortCif)
assert(QsortCallContext)

local CompareCif = libffi.newcif("sint32", "pointer", "pointer")
assert(CompareCif)

local CompareClosure, CompareAddress = libffi.newclosure(CompareCif, LuaCompareFunction)
assert(CompareClosure)
assert(CompareAddress ~= NULL)

local ArrayInput = { 5, 2, 9, 1, 7 }

local ArrayC, ArrayLen = LuaArrayToC(ArrayInput)
libffi.call(QsortCallContext, QsortAddress, ArrayC, ArrayLen, 4, CompareAddress)
libffi.freecallcontext(QsortCallContext)

local ArrayOutput = CArrayToLua(ArrayC, ArrayLen)

assert(ArrayOutput[1] == 1)
assert(ArrayOutput[2] == 2)
assert(ArrayOutput[3] == 5)
assert(ArrayOutput[4] == 7)
assert(ArrayOutput[5] == 9)

libffi.freeclosure(CompareClosure)
libffi.freecif(CompareCif)
libffi.freecif(QsortCif)
libffi.free(ArrayC)
libffi.freecif(MemcpyCif)

--------------------------------------------------------------------------------
-- STDCALL                                                                    --
--------------------------------------------------------------------------------

-- Most of C functions from mscvrt.dll should use "cdecl"
-- Functions from winapi should be "stdcall".
--
-- To test that and see stack-related crashes we should test a function stdcall
-- with at least 1 parameter. Without parameter, there is no much difference
-- between stdcall and cdecl. GetCurrentProcessId, GetVersion are not suitable
-- to highlight those behaviour differences, but GetModuleHandle might.
--
-- On Windows x64 the convention seems to be fastcall-like, so it works well.
-- To test conventions on Windows we need 32 bits version of Windows. On Linux
-- it's the same as Windows, fastcall-like call convention on 64-bits.
--
-- TLDR: should crash on X86 and work on X86-64

local Kernel32 = libffi.loadlib("kernel32.dll")
assert(Kernel32)

local GetModuleHandleAddress = libffi.getproc(Kernel32, "GetModuleHandleA")
assert(GetModuleHandleAddress ~= NULL)

local GetModuleHandleACif, ErrorMessage = libffi.newcif("pointer", "pointer")
assert(GetModuleHandleACif, ErrorMessage)
local GetModuleHandleCallContext = libffi.newcallcontext(GetModuleHandleACif)
assert(GetModuleHandleCallContext)

local SprintfAddress = libffi.getproc(Libc, "sprintf")
assert(SprintfAddress ~= NULL)

local SprintfCif = libffi.newcif("sint32", "pointer", "string", "pointer", "sint32")
assert(SprintfCif)
local SprintfCallContext = libffi.newcallcontext(SprintfCif)
assert(SprintfCallContext)

local Buffer = libffi.malloc(1024)
assert(Buffer ~= NULL)

for Index = 1, 10000 do
  local Handle = libffi.call(GetModuleHandleCallContext, GetModuleHandleAddress, NULL)
  assert(Handle ~= NULL)
  local SprintfFormat = "Module Handle: %p %d\n"
  local SprintfReturn = libffi.call(SprintfCallContext, SprintfAddress, Buffer, SprintfFormat, Handle, Index)
  assert(SprintfReturn > 0)
end

libffi.free(Buffer)
libffi.freecallcontext(GetModuleHandleCallContext)
libffi.freecif(GetModuleHandleACif)
libffi.freecallcontext(SprintfCallContext)
libffi.freecif(SprintfCif)
