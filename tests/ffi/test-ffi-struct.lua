--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.raw.libffi")
local libtcc = require("com.raw.libtcc")
local ffi    = require("com.ffi")

assert(libffi)
assert(libtcc)
assert(ffi)
assert(ffi.int32_t)
assert(libffi.newstruct)

local int32_t = ffi.int32_t
local pointer = ffi.pointer
local NULL    = ffi.NULL

local newinstance = ffi.newinstance

--------------------------------------------------------------------------------
-- STRUCT BY VALUE [ARGUMENTS + RETURNS]                                      --
--------------------------------------------------------------------------------

local PairStruct, PairTypeError = ffi.newstructure("Pair",
                                                   int32_t,  "First",
                                                   int32_t, "Second")
assert(PairStruct, PairTypeError)
assert(PairStruct.getsizeinbytes)
assert(PairStruct.getalignment)
assert(PairStruct.getoffsets)

local PairSize      = PairStruct:getsizeinbytes()
local PairAlignment = PairStruct:getalignment()
assert(PairSize, PairAlignment)
print("Pair struct size:", PairSize)
print("Pair struct alignment:", PairAlignment)
assert(PairSize == 8)
assert(PairAlignment >= 4)

local PairOffsets = PairStruct:getoffsets()
assert(PairOffsets[1] == 0)
assert(PairOffsets[2] == 4)

local tcc_new             = libtcc.tcc_new
local tcc_set_output_type = libtcc.tcc_set_output_type
local tcc_compile_string  = libtcc.tcc_compile_string
local tcc_relocate        = libtcc.tcc_relocate
local tcc_get_symbol      = libtcc.tcc_get_symbol
local tcc_delete          = libtcc.tcc_delete

local StructProgram = [[typedef struct PairTag {
  int Left;
  int Right;

} Pair;

Pair MakePair (int Left, int Right)
{
  Pair NewPair;
  NewPair.Left  = Left;
  NewPair.Right = Right;
  return NewPair;
}

int SumPair (Pair Input)
{
  return (Input.Left + Input.Right);
}

typedef Pair (*PairTransformCallback)(Pair Input);

int CallPairAndSum (PairTransformCallback Callback, int Left, int Right)
{
  Pair Input;
  Pair Output;
  Input.Left  = Left;
  Input.Right = Right;
  Output = Callback(Input);
  return (Output.Left + Output.Right);
}
]]

local TccState = tcc_new()
assert(TccState ~= NULL)
assert((tcc_set_output_type(TccState, "memory") == 0))
assert((tcc_compile_string(TccState, StructProgram) == 0))
assert((tcc_relocate(TccState) == 0))

local MakePairAddress       = tcc_get_symbol(TccState, "MakePair")
local SumPairAddress        = tcc_get_symbol(TccState, "SumPair")
local CallPairAndSumAddress = tcc_get_symbol(TccState, "CallPairAndSum")
assert(MakePairAddress       ~= NULL)
assert(SumPairAddress        ~= NULL)
assert(CallPairAndSumAddress ~= NULL)

local MakePair, MakePairPrivate             = ffi.importfunction(MakePairAddress, PairStruct, int32_t, int32_t)
local SumPair, SumPairPrivate               = ffi.importfunction(SumPairAddress, int32_t, PairStruct)
local CallPairAndSum, CallPairAndSumPrivate = ffi.importfunction(CallPairAndSumAddress, int32_t, pointer, int32_t, int32_t)
assert(MakePair)
assert(SumPair)
assert(CallPairAndSum)

local PairValueA = MakePair(11, 31)
assert((type(PairValueA) == "table"))
assert((PairValueA:getfield("First") == 11))
assert((PairValueA:getfield("Second") == 31))

local PairValueB = MakePair(7, 5)
assert((PairValueA == PairValueB))
assert((PairValueB:getfield("First") == 7))
assert((PairValueB:getfield("Second") == 5))

local UserPair = newinstance(PairStruct)
UserPair:set(1, 40)
UserPair:setfield("Second", 2)

local PairSum = SumPair(UserPair)
assert((PairSum == 42))

local PairArray = ffi.newarray(PairStruct, 2)
assert((#PairArray == 2))
local PairFirst  = PairArray:get(1)
local PairSecond = PairArray:get(2)
PairFirst:setfield("First", 1)
PairFirst:setfield("Second", 2)
PairSecond:setfield("First", 3)
PairSecond:setfield("Second", 4)
assert((PairFirst:getfield("First") == 1))
assert((PairSecond:getfield("Second") == 4))

UserPair  = nil
PairArray = nil
collectgarbage()
collectgarbage()

libffi.freecallcontext(MakePairPrivate[2])
libffi.freecif(MakePairPrivate[1])
libffi.freecallcontext(SumPairPrivate[2])
libffi.freecif(SumPairPrivate[1])

--------------------------------------------------------------------------------
-- STRUCT CALLBACK                                                            --
--------------------------------------------------------------------------------

local PairTransformCallbackCalled = false

local function PairTransformCallback (InputPair)
  assert((type(InputPair) == "table"))
  assert((type(InputPair.getfield) == "function"))
  PairTransformCallbackCalled = true
  local Left       = InputPair:getfield("First")
  local Right      = InputPair:getfield("Second")
  local OutputPair = newinstance(PairStruct)
  OutputPair:setfield("First",  (Left  + 10))
  OutputPair:setfield("Second", (Right + 20))
  return OutputPair
end

local PairCallback        = ffi.newcallback(PairTransformCallback, PairStruct, PairStruct)
local PairCallbackPointer = PairCallback:getpointer()

assert(PairCallback)
assert(PairCallbackPointer ~= NULL)

local CallbackSum = CallPairAndSum(PairCallbackPointer, 1, 2)
assert((CallbackSum == 33))
assert(PairTransformCallbackCalled)

PairCallback = nil
collectgarbage()
collectgarbage()

libffi.freecallcontext(CallPairAndSumPrivate[2])
libffi.freecif(CallPairAndSumPrivate[1])
tcc_delete(TccState)

collectgarbage()
