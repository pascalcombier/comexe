--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.raw.libffi")
local libtcc = require("com.raw.libtcc")
local ffi    = require("com.ffi")

assert(libffi)
assert(libtcc)
assert(ffi)
assert(libffi.sint32)
assert(libffi.newstructtype)

local sint32 = libffi.sint32
local NULL   = libffi.NULL

--------------------------------------------------------------------------------
-- STRUCT BY VALUE [ARGUMENTS + RETURNS]                                      --
--------------------------------------------------------------------------------

local PairStruct, PairTypeError = ffi.newstructtype("Pair", "First",  sint32,
                                                    "Second", sint32)
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

local StructProgram = [[
typedef struct PairTag
{
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
]]

local TccState = tcc_new()
assert(TccState ~= NULL)
assert((tcc_set_output_type(TccState, "memory") == 0))
assert((tcc_compile_string(TccState, StructProgram) == 0))
assert((tcc_relocate(TccState) == 0))

local MakePairAddress = tcc_get_symbol(TccState, "MakePair")
local SumPairAddress  = tcc_get_symbol(TccState, "SumPair")
assert(MakePairAddress ~= NULL)
assert(SumPairAddress ~= NULL)

local MakePair, MakePairPrivate = ffi.newluafunction(MakePairAddress, PairStruct, sint32, sint32)
local SumPair, SumPairPrivate = ffi.newluafunction(SumPairAddress, sint32, PairStruct)
assert(MakePair)
assert(SumPair)

local PairValueA = MakePair(11, 31)
assert((type(PairValueA) == "table"))
assert((PairValueA:getfield("First") == 11))
assert((PairValueA:getfield("Second") == 31))

local PairValueB = MakePair(7, 5)
assert((PairValueA == PairValueB))
assert((PairValueB:getfield("First") == 7))
assert((PairValueB:getfield("Second") == 5))

local UserPair = PairStruct:newinstance()
UserPair:set(1, 40)
UserPair:setfield("Second", 2)

local PairSum = SumPair(UserPair)
assert((PairSum == 42))

local PairArray = PairStruct:newarray(2)
assert((#PairArray == 2))
local PairFirst = PairArray[1]
local PairSecond = PairArray[2]
PairFirst:setfield("First", 1)
PairFirst:setfield("Second", 2)
PairSecond:setfield("First", 3)
PairSecond:setfield("Second", 4)
assert((PairFirst:getfield("First") == 1))
assert((PairSecond:getfield("Second") == 4))

UserPair = nil
PairArray = nil
collectgarbage()
collectgarbage()

libffi.freecallcontext(MakePairPrivate[2])
libffi.freecif(MakePairPrivate[1])
libffi.freecallcontext(SumPairPrivate[2])
libffi.freecif(SumPairPrivate[1])

--------------------------------------------------------------------------------
-- STRUCT LIMITATION [CLOSURES]                                              --
--------------------------------------------------------------------------------

local StructClosureCif, StructClosureCifError = libffi.newcif({ sint32, PairStruct:getffitype() })
assert(StructClosureCif, StructClosureCifError)

local SuccessClosure, ClosureError = pcall(function ()
    libffi.newclosure(StructClosureCif, function ()
                        return 0
    end)
end)

local ClosureErrorMessage = tostring(ClosureError)

assert((SuccessClosure == false))
assert(string.find(ClosureErrorMessage, "Struct%-by%-value is not supported for closures yet", 1, false))

libffi.freecif(StructClosureCif)
tcc_delete(TccState)


collectgarbage()
