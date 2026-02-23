--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local RawCom  = require("com.raw.win32.com")
local ffi     = require("com.ffi")
local Runtime = require("com.runtime")
local Win32   = require("com.win32")

local format        = string.format
local insert        = table.insert
local tointeger     = math.tointeger
local floor         = math.floor
local newbuffer     = Runtime.newbuffer
local newidprovider = Runtime.newidprovider
local utf8to16      = Win32.utf8to16
local NULL          = ffi.NULL

-- CLSID/IID
local newclsid = RawCom.newclsid
local newiid   = RawCom.newiid

-- VARIANT
local VARIANT_SIZE      = RawCom.variant_getsize()
local variant_init      = RawCom.variant_init
local variant_clear     = RawCom.variant_clear
local variant_set       = RawCom.variant_set
local variant_get       = RawCom.variant_get

-- SAFEARRAY
local safearray_create       = RawCom.safearray_create
local safearray_destroy      = RawCom.safearray_destroy
local safearray_getdim       = RawCom.safearray_getdim
local safearray_getlbound    = RawCom.safearray_getlbound
local safearray_getubound    = RawCom.safearray_getubound
local safearray_accessdata   = RawCom.safearray_accessdata
local safearray_unaccessdata = RawCom.safearray_unaccessdata
local safearray_getelemsize  = RawCom.safearray_getelemsize
local safearray_getvartype   = RawCom.safearray_getvartype
local safearray_readdata     = RawCom.safearray_readdata
local safearray_writedata    = RawCom.safearray_writedata

-- EnumVARIANT
local enumvariant_clone = RawCom.enumvariant_clone
local enumvariant_next  = RawCom.enumvariant_next
local enumvariant_reset = RawCom.enumvariant_reset
local enumvariant_skip  = RawCom.enumvariant_skip

-- IUnknown
local iunknown_addref         = RawCom.iunknown_addref
local iunknown_release        = RawCom.iunknown_release
local iunknown_queryinterface = RawCom.iunknown_queryinterface

-- DISPATCH
local create        = RawCom.idispatch_create
local getidofname   = RawCom.idispatch_getidofname
local invoke        = RawCom.idispatch_invoke
local members       = RawCom.idispatch_members
local getobjecttype = RawCom.idispatch_gettype

-- Pre-declaration, implemented in COM_VariantToLuaImpl. We need to pre-declare
-- that because it is used quite early in UNKNOWN_NewIEnumVARIANT, but at that
-- time COM_NewDispatch is not implemented yet (and so is COM_VariantToLua).
local COM_VariantToLua

-- For similar reasons, we need to pre-declare DISPATCH metatable
-- Implemented in DISPATCH_MetatableImpl
local DISPATCH_Metatable

--------------------------------------------------------------------------------
-- ADDONS                                                                     --
--------------------------------------------------------------------------------

local function HRESULT_SUCCEEDED (HResult)
  return (HResult >= 0)
end

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

-- Dict NameString->ValueInteger
local VARIANT_TYPE_VALUES = {
  VT_EMPTY            = 0,
  VT_NULL             = 1,
  VT_I2               = 2,
  VT_I4               = 3,
  VT_R4               = 4,
  VT_R8               = 5,
  VT_CY               = 6,
  VT_DATE             = 7,
  VT_BSTR             = 8,
  VT_DISPATCH         = 9,
  VT_ERROR            = 10,
  VT_BOOL             = 11,
  VT_VARIANT          = 12,
  VT_UNKNOWN          = 13,
  VT_DECIMAL          = 14,
  VT_I1               = 16,
  VT_UI1              = 17,
  VT_UI2              = 18,
  VT_UI4              = 19,
  VT_I8               = 20,
  VT_UI8              = 21,
  VT_INT              = 22,
  VT_UINT             = 23,
  VT_VOID             = 24,
  VT_HRESULT          = 25,
  VT_PTR              = 26,
  VT_SAFEARRAY        = 27,
  VT_CARRAY           = 28,
  VT_USERDEFINED      = 29,
  VT_LPSTR            = 30,
  VT_LPWSTR           = 31,
  VT_RECORD           = 36,
  VT_INT_PTR          = 37,
  VT_UINT_PTR         = 38,
  VT_FILETIME         = 64,
  VT_BLOB             = 65,
  VT_STREAM           = 66,
  VT_STORAGE          = 67,
  VT_STREAMED_OBJECT  = 68,
  VT_STORED_OBJECT    = 69,
  VT_BLOB_OBJECT      = 70,
  VT_CF               = 71,
  VT_CLSID            = 72,
  VT_VERSIONED_STREAM = 73,
  VT_BSTR_BLOB        = 0xfff,
  VT_VECTOR           = 0x1000,
  VT_ARRAY            = 0x2000,
  VT_BYREF            = 0x4000,
  VT_RESERVED         = 0x8000,
  VT_ILLEGAL          = 0xffff,
  VT_ILLEGALMASKED    = 0xfff,
  VT_TYPEMASK         = 0xff,
}

-- Register the DICT[IntegerValue->StringName] for a simple high-level API: the
-- returned types will be strings such as "VT_DISPATCH"
local VARIANT_TYPES_NAMES = {}
for TypeName, TypeValue in pairs(VARIANT_TYPE_VALUES) do
  VARIANT_TYPES_NAMES[TypeValue] = TypeName
end

-- Those types are used below in the implementation
local VT_UNKNOWN  = VARIANT_TYPE_VALUES["VT_UNKNOWN"]
local VT_DISPATCH = VARIANT_TYPE_VALUES["VT_DISPATCH"]
local VT_NULL     = VARIANT_TYPE_VALUES["VT_NULL"]
local VT_I4       = VARIANT_TYPE_VALUES["VT_I4"]
local VT_R8       = VARIANT_TYPE_VALUES["VT_R8"]
local VT_BOOL     = VARIANT_TYPE_VALUES["VT_BOOL"]
local VT_BSTR     = VARIANT_TYPE_VALUES["VT_BSTR"]
local VT_VARIANT  = VARIANT_TYPE_VALUES["VT_VARIANT"]
local VT_VECTOR   = VARIANT_TYPE_VALUES["VT_VECTOR"]
local VT_ARRAY    = VARIANT_TYPE_VALUES["VT_ARRAY"]
local VT_BYREF    = VARIANT_TYPE_VALUES["VT_BYREF"]

-- Return the type string such as "VT_DISPATCH" or "VT_ARRAY|VT_VARIANT"
local function VARIANT_GetTypeName (TypeValue)
  local TypeName = VARIANT_TYPES_NAMES[TypeValue]
  if (TypeName == nil) then
    local CollectionType
    local ItemValue
    if ((TypeValue & VT_VECTOR) == VT_VECTOR) then
      CollectionType = "VT_VECTOR"
      ItemValue      = (TypeValue & (~VT_VECTOR))
    elseif ((TypeValue & VT_ARRAY) == VT_ARRAY) then
      CollectionType = "VT_ARRAY"
      ItemValue      = (TypeValue & (~VT_ARRAY))
    elseif ((TypeValue & VT_BYREF) == VT_BYREF) then
      CollectionType = "VT_BYREF"
      ItemValue      = (TypeValue & (~VT_BYREF))
    end
    if CollectionType then
      local RealTypeName = VARIANT_TYPES_NAMES[ItemValue]
      if (RealTypeName == nil) then
        RealTypeName = format("VT_%d_%x", ItemValue, ItemValue)
      end
      TypeName = format("%s|%s", CollectionType, RealTypeName)
    else
      TypeName = format("VT_%d_%x", TypeValue, TypeValue)
    end
  end
  return TypeName
end

-- DISPATCH flags from oleauto.h
local DISPATCH_METHOD         = 0x1
local DISPATCH_PROPERTYGET    = 0x2
local DISPATCH_PROPERTYPUT    = 0x4
local DISPATCH_PROPERTYPUTREF = 0x8

--------------------------------------------------------------------------------
-- TYPE: COM DATE                                                             --
--------------------------------------------------------------------------------

-- To simplify date calculations, we use Julian Day Number which represent how
-- many days since January 1st, 4713 BC (noon time, -4712)
--
-- Convert a date to Julian Day Number (JDN).
local function DateToJulianDay (Year, Month, Day)
  local a = floor((14 - Month) / 12)
  local y = Year + 4800 - a
  local m = Month + 12 * a - 3
  local JulianDay = Day + floor((153 * m + 2) / 5) + 365 * y + floor(y / 4) - floor(y / 100) + floor(y / 400) - 32045
  return JulianDay
end

-- Parse ISO date string (format: "YYYY-MM-DD" or "YYYY-MM-DD HH:MM:SS")
local function COM_NewDateFromIso (IsoDateString)
  local Year, Month, Day, Hour, Minute, Second = IsoDateString:match("(%d+)-(%d+)-(%d+)%s*(%d*):?(%d*):?(%d*)")
  -- Convert strings to numbers
  Year  = tonumber(Year)
  Month = tonumber(Month)
  Day   = tonumber(Day)
  -- Validate inputs
  local ErrorMessage = "Invalid date format. Expected YYYY-MM-DD or YYYY-MM-DD HH:MM:SS"
  assert(Year,  ErrorMessage)
  assert(Month, ErrorMessage)
  assert(Day,   ErrorMessage)
  -- Optional
  Hour   = tonumber(Hour)   or 0
  Minute = tonumber(Minute) or 0
  Second = tonumber(Second) or 0
  -- Excel base date is December 30, 1899
  -- Base Julian Day for 1899-12-30
  local BaseJulianDay = DateToJulianDay(1899, 12, 30)
  local DateJulianDay = DateToJulianDay(Year, Month, Day)
  local TotalDays     = (DateJulianDay - BaseJulianDay)
  -- Add time fraction (hours/minutes/seconds)
  local SecondPerDay = (60 * 60 * 24)
  local TimeFraction = ((Hour * 3600 + Minute * 60 + Second) / SecondPerDay)
  -- Return combined value for Excel
  return TotalDays + TimeFraction
end

--------------------------------------------------------------------------------
-- VARIANT ELEMENT: PART OF VARIANT ARRAY                                     --
--------------------------------------------------------------------------------

-- Variants need to be declared/implemented early because they are needed for
-- IEnumVARIANT

local function VARIANT_MethodGetPointer (Variant)
  -- Retrieve data
  local Buffer = Variant.Buffer
  local Offset = Variant.Offset
  -- Return pointer
  return Buffer:getpointer(Offset)
end

local function VARIANT_MethodInit (Variant)
  local Pointer = Variant:getpointer()
  variant_init(Pointer)
end

local function VARIANT_MethodClear (Variant)
  local Pointer = Variant:getpointer()
  variant_clear(Pointer)
end

local function VARIANT_MethodGet (Variant)
  local Pointer = Variant:getpointer()
  local Value, VariantType, ErrorMessage = variant_get(Pointer)
  return Value, VariantType, ErrorMessage
end

local function VARIANT_MethodSet (Variant, Type, Value)
  local Pointer = Variant:getpointer()
  local Success = variant_set(Pointer, Type, Value)
  return Success
end

local VARIANT_Metatable = {
  -- Custom methods
  __index = {
    getpointer = VARIANT_MethodGetPointer,
    init       = VARIANT_MethodInit,
    clear      = VARIANT_MethodClear,
    get        = VARIANT_MethodGet,
    set        = VARIANT_MethodSet,
  }
}

-- The VARIANT is created by VA_MethodGetVariant

--------------------------------------------------------------------------------
-- VARIANT ARRAY                                                              --
--------------------------------------------------------------------------------

local function VA_MethodGarbage (VariantArray)
  -- No action: buffer will be freed by BUFFER_MethodGarbage
end

-- This method was initially intended for IEnumVARIANT:Next (in the function
-- UNKNOWN_NewIEnumVARIANT), to read as much as possible according to the
-- current capacity.
local function VA_GetItemCapacity (VariantArray)
  -- Retrieve data
  local Buffer = VariantArray.Buffer
  -- Get item capacity
  local CapacityInBytes = Buffer:getcapacity()
  local ItemCapacity    = (CapacityInBytes // VARIANT_SIZE)
  -- Return value
  return ItemCapacity
end

-- NOTE: update VariantArray.ItemCapacity
local function VA_MethodEnsureCapacity (VariantArray, VariantCount)
  -- Ensure the buffer capacity for the required number of variants
  local SizeInBytes = (VariantCount * VARIANT_SIZE)
  -- Retrieve data
  local Buffer          = VariantArray.Buffer
  local OldItemCapacity = VariantArray.ItemCapacity
  -- Resize buffer if needed
  Buffer:ensurecapacity(SizeInBytes)
  -- Initialize newly-added variants
  local NewItemCapacity = VA_GetItemCapacity(VariantArray)
  if (NewItemCapacity > OldItemCapacity) then
    for Index = (OldItemCapacity + 1), NewItemCapacity do
      local Variant = VariantArray:GetVariant(Index)
      Variant:init()
      VariantArray.InitDone[Index] = true
    end
  end
  -- Update data
  VariantArray.ItemCapacity = NewItemCapacity
end

-- Variant.Offset is fixed, while the underlying Buffer.RawBuffer will change when
-- the buffer size increases
local function VA_MethodGetVariant (VariantArray, Index)
  -- Retrieve data
  local Buffer = VariantArray.Buffer
  -- Calculate offset
  local Offset = ((Index - 1) * VARIANT_SIZE)
  -- Create new Variant object
  local NewVariantObject = {
    Buffer = Buffer,
    Offset = Offset,
  }
  -- Attach methods
  setmetatable(NewVariantObject, VARIANT_Metatable)
  -- Return the new variant object
  return NewVariantObject
end

local VA_Metatables = {
  -- General methods
   __gc = VA_MethodGarbage,
  -- Custom methods
  __index = {
    EnsureCapacity = VA_MethodEnsureCapacity,
    GetVariant     = VA_MethodGetVariant
  }
}

local function NewVariantArray (ItemCount)
  -- Validate inputs
  assert(type(ItemCount) == "number", "ItemCount must be a number")
  -- Calculate things
  local SizeInBytes = (ItemCount * VARIANT_SIZE)
  local NewBuffer    = newbuffer(SizeInBytes)
  local InitDone     = {}
  -- New VariantArray object
  local NewVariantArrayObject = {
    Buffer   = NewBuffer,
    InitDone = InitDone
  }
  -- Attach methods
  setmetatable(NewVariantArrayObject, VA_Metatables)
  -- Initialize the variants
  local ItemCapacity = VA_GetItemCapacity(NewVariantArrayObject)
  -- Trivially initialize each variant
  for Index = 1, ItemCapacity do
    local Variant = NewVariantArrayObject:GetVariant(Index)
    Variant:init()
    InitDone[Index] = true
  end
  -- Update data
  NewVariantArrayObject.ItemCapacity = ItemCapacity
  -- Return new array
  return NewVariantArrayObject
end

--------------------------------------------------------------------------------
-- GLOBAL VARIANT ARRAY                                                       --
--------------------------------------------------------------------------------

-- For simplicity, we just have a global variant array that will be used for
-- the IEnumVARIANT below and Dispatch::invoke (DISPATCH_Invoke)
--
-- The caller need to use GLOBAL_VariantArray:ensurecapacity() to grow the
-- underlying buffer.

local GLOBAL_VariantArray = NewVariantArray(16)

--------------------------------------------------------------------------------
-- KNOWN INTERFACES (RAW, NON-LATE BINDINGS) FOR IUNKNOWN                     --
--------------------------------------------------------------------------------

local function UNKNOWN_NewIEnumVARIANT (InterfacePointer)
  local function MethodClone (EnumVariantObject)
    -- Retrieve data
    local EnumVariantPointer = EnumVariantObject.Pointer
    -- Call the API
    local Result, NewPointer = enumvariant_clone(EnumVariantPointer)
    local NewIEnumVariant
    local ErrorString
    -- Return value
    if HRESULT_SUCCEEDED(Result) then
      NewIEnumVariant = UNKNOWN_NewIEnumVARIANT(NewPointer)
    else
      ErrorString = format("IEnumVARIANT:Clone failed: 0x%8.8X", Result)
    end
    -- Return value
    return NewIEnumVariant, ErrorString
  end
  local function MethodNext (EnumVariantObject)
    -- Retrieve data
    local EnumVariantPointer = EnumVariantObject.Pointer
    local NextVariant        = GLOBAL_VariantArray:GetVariant(1)
    -- Ensure we don't leak previous value held in the slot
    NextVariant:clear()
    NextVariant:init()
    local NextPointer = NextVariant:getpointer()
    local Result, Fetched = enumvariant_next(EnumVariantPointer, 1, NextPointer)
    local ReturnValue
    local ReturnError
    local ReturnTypeName
    if HRESULT_SUCCEEDED(Result) then
      if (Fetched == 1) then
        ReturnValue, ReturnTypeName, ReturnError = COM_VariantToLua(NextPointer)
      elseif (Fetched == 0) then
        ReturnValue    = nil
        ReturnError    = nil
        ReturnTypeName = nil
      else
        ReturnValue    = nil
        ReturnError    = "Unexpected number of items fetched"
        ReturnTypeName = nil
      end
    else
      ReturnValue    = nil
      ReturnError    = format("IEnumVARIANT:Next failed: %8.8X", Result)
      ReturnTypeName = nil
    end
    -- In COM_VariantToLua, implemented in COM_VariantToLuaImpl, the very first
    -- action is variant_get, in the C function VARIANT_Get the reference is
    -- added lpVtbl->AddRef(), we are going to give the ownership to the Lua
    -- caller, so we can now release the reference with Clear().
    NextVariant:clear()
    NextVariant:init()
    -- Return: ValueOrNil, TypeNameOrNil, ErrorMessageOrNil
    return ReturnValue, ReturnTypeName, ReturnError
  end
  local function MethodReset (EnumVariantObject)
    -- Retrieve data
    local EnumVariantPointer = EnumVariantObject.Pointer
    -- Call the API
    local Result  = enumvariant_reset(EnumVariantPointer)
    local Success = HRESULT_SUCCEEDED(Result)
    -- Return value
    return Success
  end
  local function MethodSkip (EnumVariantObject, Count)
    -- Retrieve data
    local EnumVariantPointer = EnumVariantObject.Pointer
    -- Call the API
    local Result  = enumvariant_skip(EnumVariantPointer, Count)
    local Success = HRESULT_SUCCEEDED(Result)
    -- Return value
    return Success
  end
  local function MethodRelease (EnumVariantObject)
    -- Retrieve data
    local EnumVariantPointer = EnumVariantObject.Pointer
    -- Call the API
    local ReferenceCount
    if EnumVariantPointer then
      ReferenceCount = iunknown_release(EnumVariantPointer)
      EnumVariantObject.Pointer = nil
    end
    -- Return value
    return ReferenceCount
  end
  local function MethodGarbage (EnumVariantObject)
    MethodRelease(EnumVariantObject)
  end
  -- Metatable
  local EnumMetatable = {
    -- Generic methods
    __gc = MethodGarbage,
    -- Custom methods
    __index = {
      clone   = MethodClone,
      next    = MethodNext,
      reset   = MethodReset,
      skip    = MethodSkip,
      release = MethodRelease,
    }
  }
  -- Create a new object
  local NewObject = {
    Pointer = InterfacePointer
  }
  setmetatable(NewObject, EnumMetatable)
  -- Return value
  return NewObject
end

local function COM_CastUnknown (Unknown, IidUtf8)
  -- Retrieve data
  local Pointer = Unknown.Pointer
  -- Create the new Lua object
  local NewInterface
  if (IidUtf8 == "IEnumVARIANT") then
    NewInterface = UNKNOWN_NewIEnumVARIANT(Pointer)
  else
    NewInterface = Pointer
  end
  -- Return object
  return NewInterface
end

--------------------------------------------------------------------------------
-- IUNKNOWN                                                                   --
--------------------------------------------------------------------------------

local function UNKNOWN_MethodAddRef (Unknown)
  -- Retrieve data
  local Pointer = Unknown.Pointer
  -- Call the C API
  local ReferenceCount = iunknown_addref(Pointer)
  -- Return value
  return ReferenceCount
end

local function UNKNOWN_MethodQueryInterface (Unknown, IidUtf8)
  -- Retrieve data
  local Pointer = Unknown.Pointer
  -- Get the IID
  local IidUf16 = utf8to16(IidUtf8)
  local Iid     = newiid(IidUf16)
  -- Call the C API
  local Result, NewInterfacePointer = iunknown_queryinterface(Pointer, Iid)
  local ReturnInterface
  if HRESULT_SUCCEEDED(Result) then
    ReturnInterface = NewInterfacePointer
  else
    ReturnInterface = nil
  end
  -- Return value
  return ReturnInterface
end

local function UNKNOWN_MethodRelease (Unknown)
  -- Retrieve data
  local Pointer = Unknown.Pointer
  -- Call the C API
  local ReferenceCount
  if Pointer then
    ReferenceCount  = iunknown_release(Pointer)
    Unknown.Pointer = nil
  end
  -- Return value
  return ReferenceCount
end

local function UNKNOWN_MethodGarbage (Unknown)
  Unknown:release()
end

local UNKNOWN_Metatable = {
  -- Generic method
  __gc = UNKNOWN_MethodGarbage,
  -- Custom methods
  __index = {
    addref         = UNKNOWN_MethodAddRef,
    queryinterface = UNKNOWN_MethodQueryInterface,
    release        = UNKNOWN_MethodRelease
  }
}

local function COM_NewUnknown (UnknownPointer)
  -- Validate inputs
  assert(UnknownPointer)
  assert(UnknownPointer ~= NULL)
  -- Create the new Lua object
  local NewUnknownObject = {
    Pointer = UnknownPointer
  }
  -- Attach methods
  setmetatable(NewUnknownObject, UNKNOWN_Metatable)
  -- Add reference
  NewUnknownObject:addref()
  -- Return value
  return NewUnknownObject
end

--------------------------------------------------------------------------------
-- SAFEARRAY                                                                  --
--------------------------------------------------------------------------------

local function SAFEARRAY_EvaluateCount (Pointer)
  -- Get the number of dimensions
  local DimensionCount = safearray_getdim(Pointer)
  -- Variable to store the total element count
  local ElementCount = 1
  -- Loop over the dimensions
  for Dimension = 1, DimensionCount do
    local Result1, LowerBound = safearray_getlbound(Pointer, Dimension)
    assert(HRESULT_SUCCEEDED(Result1), format("Failed to get lower bound: 0x%08X", Result1))
    local Result2, UpperBound = safearray_getubound(Pointer, Dimension)
    assert(HRESULT_SUCCEEDED(Result2), format("Failed to get upper bound: 0x%08X", Result2))
    assert(LowerBound)
    assert(UpperBound)
    local Count = ((UpperBound - LowerBound) + 1)
    assert(Count > 0)
    ElementCount = (ElementCount * Count)
  end
  -- Return value
  return ElementCount
end

local function SAFEARRAY_MethodLock (SafeArrayObject)
  -- Retrieve data
  local SafeArrayPointer = SafeArrayObject.SafeArrayPointer
  -- Call C API
  local Result, DataPointer = safearray_accessdata(SafeArrayPointer)
  assert(HRESULT_SUCCEEDED(Result), format("Failed to access data: 0x%08X", Result))
  -- Return value
  return DataPointer
end

local function SAFEARRAY_MethodUnlock (SafeArrayObject)
  -- Retrieve data
  local SafeArrayPointer = SafeArrayObject.SafeArrayPointer
  -- Call C API
  local Result  = safearray_unaccessdata(SafeArrayPointer)
  local Success = HRESULT_SUCCEEDED(Result)
  -- Return value
  return Success
end

local function SAFEARRAY_MethodWrite (SafeArrayObject, Data)
  -- Validate inputs
  assert(type(Data) == "table", "Data must be a table")
  local ProvidedCount = #Data
  local Capacity      = SafeArrayObject.ElementCount
  assert((ProvidedCount <= Capacity), format("SAFEARRAY write overflow: provided %d elements, capacity is %d", ProvidedCount, Capacity))
  -- Retrieve data
  local SafeArrayPointer = SafeArrayObject.SafeArrayPointer
  -- Lock, write, unlock
  local Result1, DataPointer = safearray_accessdata(SafeArrayPointer)
  assert(HRESULT_SUCCEEDED(Result1), format("Failed to access data: 0x%08X", Result1))
  assert(DataPointer, "Failed to access SAFEARRAY data")
  local WriteCount = safearray_writedata(SafeArrayPointer, DataPointer, Data)
  assert((WriteCount == ProvidedCount), format("Failed to write SAFEARRAY data: wrote %d elements, expected %d", WriteCount, ProvidedCount))
  local Result2 = safearray_unaccessdata(SafeArrayPointer)
  assert(HRESULT_SUCCEEDED(Result2), format("Failed to unlock SAFEARRAY data: 0x%08X", Result2))
  -- Return value
  return WriteCount
end

local function SAFEARRAY_GetCount (SafeArrayObject)
  -- Retrieve value
  local ElementCount = SafeArrayObject.ElementCount
  -- Return value
  return ElementCount
end

local function SAFEARRAY_GetDimensions (SafeArrayObject)
  -- Retrieve data
  local SafeArrayPointer = SafeArrayObject.SafeArrayPointer
  -- Get the number of dimensions
  local DimensionCount = safearray_getdim(SafeArrayPointer)
  -- Variable to store the dimensions
  local Dimensions = {}
  for Dimension = 1, DimensionCount do
    local Result, LowerBound = safearray_getlbound(SafeArrayPointer, Dimension)
    assert(HRESULT_SUCCEEDED(Result), format("Failed to get lower bound: 0x%08X", Result))
    local Result2, UpperBound = safearray_getubound(SafeArrayPointer, Dimension)
    assert(HRESULT_SUCCEEDED(Result2), format("Failed to get upper bound: 0x%08X", Result2))
    assert(LowerBound)
    assert(UpperBound)
    local Count        = ((UpperBound - LowerBound) + 1)
    local NewDimension = { LowerBound, UpperBound, Count }
    insert(Dimensions, NewDimension)
  end
  -- Return value
  return Dimensions
end

-- Simply create a new Lua table with the right dimensions
local function SAFEARRAY_NewTable (SafeArrayObject)
  -- Retrieve data
  local ElementCount = SafeArrayObject.ElementCount
  -- Create the new table
  local NewTable = {}
  -- Resize the table
  NewTable[ElementCount] = 0
  -- Ensure #NewTable will return ElementCount
  for Index = 1, ElementCount do
    NewTable[Index] = 0
  end
  -- Return value
  return NewTable
end

local function SAFEARRAY_MethodRead (SafeArrayObject, Data)
  -- Validate inputs
  assert(type(Data) == "table", format("Data must be a table but got %s", type(Data)))
  -- Retrieve data
  local SafeArrayPointer = SafeArrayObject.SafeArrayPointer
  -- Lock data
  local Result, DataPointer = safearray_accessdata(SafeArrayPointer)
  assert(HRESULT_SUCCEEDED(Result), format("Failed to access data: 0x%08X", Result))
  assert(DataPointer, format("Failed to access SAFEARRAY data %s", SafeArrayPointer))
  -- Read data
  local ReadCount = safearray_readdata(SafeArrayPointer, DataPointer, Data)
  -- Unlock data
  safearray_unaccessdata(SafeArrayPointer)
  -- Return value
  return ReadCount
end

local function SAFEARRAY_MethodGetVarType (SafeArrayObject)
  -- Retrieve data
  local SafeArrayPointer = SafeArrayObject.SafeArrayPointer
  -- Call C API
  local Result, VarType = safearray_getvartype(SafeArrayPointer)
  assert(HRESULT_SUCCEEDED(Result), format("Failed to get vartype: 0x%08X", Result))
  local TypeName = VARIANT_GetTypeName(VarType)
  -- Return value
  return TypeName
end

local function SAFEARRAY_MethodGetElemSize (SafeArrayObject)
  -- Retrieve data
  local SafeArrayPointer = SafeArrayObject.SafeArrayPointer
  -- Call C API
  local SizeInBytes = safearray_getelemsize(SafeArrayPointer)
  -- Return value
  return SizeInBytes
end

local function SAFEARRAY_MethodGarbage (SafeArrayObject)
  -- Retrieve data
  local SafeArrayPointer = SafeArrayObject.SafeArrayPointer
  -- Only destroy if this wrapper still owns it; ownership is transferred
  -- (SafeArrayPointer set to nil) when passed into a VARIANT parameter.
  if SafeArrayPointer then
    safearray_destroy(SafeArrayPointer)
    SafeArrayObject.SafeArrayPointer = nil
  end
end

local SAFEARRAY_Metatable = {
  -- Generic methods
  __gc = SAFEARRAY_MethodGarbage,
  -- Custom methods
  __index = {
    getelemtype   = SAFEARRAY_MethodGetVarType,
    getelemsize   = SAFEARRAY_MethodGetElemSize,
    getcount      = SAFEARRAY_GetCount,
    getdimensions = SAFEARRAY_GetDimensions,
    newtable      = SAFEARRAY_NewTable,
    lock          = SAFEARRAY_MethodLock,
    unlock        = SAFEARRAY_MethodUnlock,
    write         = SAFEARRAY_MethodWrite,
    read          = SAFEARRAY_MethodRead,
  }
}

-- "..." is a list of pairs: (LowerBound, ElementCount)
local function SAFEARRAY_GetElementCount (...)
  -- Validate and compute dimensions and total element count
  local ArgumentCount = select("#", ...)
  assert(((ArgumentCount % 2) == 0), "dimensions must be pairs of (lower-bound, count), at least one dimension")
  assert((ArgumentCount >= 2),       "SAFEARRAY needs at least one dimension")
  local Dimensions   = (ArgumentCount // 2)
  local ElementCount = 1
  for Index = 1, Dimensions do
    local Offset     = (Index - 1)
    local LowerBound = select((Offset * 2) + 1, ...)
    local Count      = select((Offset * 2) + 2, ...)
    assert(type(LowerBound) == "number", "(lower-bound, count) must be numbers")
    assert(type(Count)      == "number", "(lower-bound, count) must be numbers")
    assert(Count > 0, "count must be > 0")
    ElementCount = (ElementCount * Count)
  end
  -- Return values
  return Dimensions, ElementCount
end

-- "..." is a list of pairs: (LowerBound, ElementCount)
--
-- Examples:
--   1D array 0-based with 10 elements: SAFEARRAY_Create("VT_VARIANT", 0, 10)
--   1D array 1-based with 10 elements: SAFEARRAY_Create("VT_VARIANT", 1, 10)
--   2D array 1-based 4x4:              SAFEARRAY_Create("VT_VARIANT", 1, 4, 1, 4)
local function SAFEARRAY_Create (TypeString, ...)
  -- Retrieve arguments
  local Type = VARIANT_TYPE_VALUES[TypeString]
  -- Validate inputs
  assert(Type, format("Unsupported type '%s' for SAFEARRAY", TypeString))
  -- Compute dimensions and total elements
  local Dimensions, ElementCount = SAFEARRAY_GetElementCount(...)
  -- Call C API
  local SafeArray = safearray_create(Type, ...)
  assert(SafeArray, "Failed to create SAFEARRAY")
  -- Create a new Lua object
  local NewSafeArrayObject = {
    SafeArrayPointer = SafeArray,
    Type             = TypeString,
    Dimensions       = Dimensions,
    ElementCount     = ElementCount
  }
  -- Attach methods
  setmetatable(NewSafeArrayObject, SAFEARRAY_Metatable)
  -- Return new SAFEARRAY object
  return NewSafeArrayObject
end

--------------------------------------------------------------------------------
-- COM OBJECT "EasyCom"                                                       --
--------------------------------------------------------------------------------

local DISPATCH_IdProvider = newidprovider()

local function DISPATCH_NewObject (Clsidutf8, Dispatch)
  -- Handle default values
  local RealClsidutf8 = (Clsidutf8 or "Auto")
  -- Create new object
  local NewObject = {
    UserId    = DISPATCH_IdProvider:new(),
    ClsidUtf8 = RealClsidutf8,
    Dispatch  = Dispatch,
    IdCache   = {}
  }
  -- Debug trace
  -- NOTE: We purposefully AddRef when creating the Lua wrapper so that
  -- every wrapper owns its reference explicitly; final Release happens
  -- in explicit release() or GC if still alive. This helps catch
  -- double-release scenarios earlier (RefCount underflow in debugger).
  pcall(iunknown_addref, Dispatch)
  -- Return value
  return NewObject
end

local function DISPATCH_MethodName (DispatchObject)
  -- Retrieve data
  local UserId    = DispatchObject.UserId
  local ClsidUtf8 = DispatchObject.ClsidUtf8
  -- Format the name
  local Name = format("%s-%4.4d", ClsidUtf8, UserId)
  -- Return the name
  return Name
end

-- Explicit release method to avoid leaks; __gc stays conservative to avoid
-- releasing after COM uninitialization.
local function DISPATCH_MethodRelease (DispatchObject)
  -- Retrieve data
  local Dispatch = DispatchObject.Dispatch
  -- Call C API
  if Dispatch then
    iunknown_release(Dispatch)
    DispatchObject.Dispatch = nil
  end
  return true
end

local function DISPATCH_MethodGarbage (DispatchObject)
  -- Retrieve data
  local UserId  = DispatchObject.UserId
  -- Release the COM object
  DISPATCH_IdProvider:release(UserId)
  DISPATCH_MethodRelease(DispatchObject)
end

local function DISPATCH_GetType (DispatchObject)
  -- Retrieve data
  local Dispatch = DispatchObject.Dispatch
  -- Call C API
  local TypeString = getobjecttype(Dispatch)
  -- Return value
  return TypeString
end

local function DISPATCH_GetMembers (DispatchObject)
  -- Retrieve data
  local Dispatch = DispatchObject.Dispatch
  -- Call C API
  local Members = members(Dispatch)
  -- Return value
  return Members
end

local function COM_ConvertType (TypeString)
  local TypeInteger
  if (TypeString == "method") then
    TypeInteger = DISPATCH_METHOD
  elseif (TypeString == "propertyget") then
    TypeInteger = DISPATCH_PROPERTYGET
  elseif (TypeString == "propertyput") then
    TypeInteger = DISPATCH_PROPERTYPUT
  elseif (TypeString == "propertyputref") then
    TypeInteger = DISPATCH_PROPERTYPUTREF
  end
  return TypeInteger
end

local function COM_VariantSetManual (Variant, LuaValue, TypeString)
  -- Retrieve variant type
  local VariantType = VARIANT_TYPE_VALUES[TypeString]
  assert(VariantType, format("Unsupported type '%s' for VARIANT %q", TypeString, LuaValue))
  -- Restrictions
  -- VT_ARRAY would need to support types string like "VT_ARRAY|VT_VARIANT"
  assert((VariantType ~= VT_ARRAY), "VT_ARRAY not supported yet, please use COM_VariantSetAuto")
  -- Convert if necessary
  local UsedLuaValue
  if (VariantType == VT_BSTR) then
  UsedLuaValue = utf8to16(LuaValue)
  elseif ((VariantType == VT_UNKNOWN) or (VariantType == VT_DISPATCH)) then
    -- When passing IUnknown*/IDispatch*, take a reference so VariantClear can
    -- safely release later
    assert(type(LuaValue) == "userdata")
    iunknown_addref(LuaValue)
    UsedLuaValue = LuaValue
  else
    UsedLuaValue = LuaValue
  end
  -- Set the variant
  local Success = Variant:set(VariantType, UsedLuaValue)
  assert(Success, "Failed to set VARIANT parameter value")
end

local function COM_VariantSetAuto (Variant, LuaObject)
  -- Detect Lua type and map to VARIANT type
  local LuaType = type(LuaObject)
  local ComType
  local ComValue
  if (LuaObject == nil) then
    ComType  = VT_NULL
    ComValue = nil
  elseif (LuaType == "number") then
    local Integer = tointeger(LuaObject)
    if Integer then
      ComType = VT_I4
    else
      ComType = VT_R8
    end
    ComValue = LuaObject
  elseif (LuaType == "boolean") then
    ComType  = VT_BOOL
    ComValue = LuaObject
  elseif (LuaType == "string") then
    ComType  = VT_BSTR
  ComValue = utf8to16(LuaObject)
  elseif (LuaType == "userdata") then
    -- Passing raw IUnknown*/IDispatch* as lightuserdata. C side (variant_set)
    -- performs the AddRef; no Lua-side AddRef to avoid leaking a ref.
    ComType  = VT_UNKNOWN
    ComValue = LuaObject
  elseif (LuaType == "table") then
    if LuaObject.Dispatch then
      ComType  = VT_DISPATCH
      ComValue = LuaObject.Dispatch
      -- C side (variant_set) AddRefs; omit Lua-side AddRef to prevent leaks.
    elseif LuaObject.SafeArrayPointer then
      -- Expecting a SAFEARRAY of VARIANT elements
      ComType  = (VT_ARRAY | VT_VARIANT)
      ComValue = LuaObject.SafeArrayPointer
      -- Ownership is now with the VARIANT; avoid destroying in __gc by
      -- clearing our pointer.
      LuaObject.SafeArrayPointer = nil
    else
      ComType  = VT_UNKNOWN
      ComValue = LuaObject
    end
  else
    ComType  = VT_UNKNOWN
    ComValue = LuaObject
  end
  local Success = Variant:set(ComType, ComValue)
  assert(Success, "Failed to set VARIANT parameter value")
end

local function COM_VariantToLuaImpl (VariantPointer)
  -- Get the VARIANT value
  local ResultValue, ResultType, ReturnError = variant_get(VariantPointer)
  -- Automatic promotion of raw value to complex Lua object
  if (ResultType == VT_UNKNOWN) then
    local Unknown = COM_NewUnknown(ResultValue)
    ResultValue = Unknown
  elseif (ResultType == VT_DISPATCH) then
    local Dispatch    = ResultValue
    local NewDispatch = DISPATCH_NewObject(nil, Dispatch)
    setmetatable(NewDispatch, DISPATCH_Metatable)
    ResultValue = NewDispatch
  elseif ((ResultType & VT_ARRAY) == VT_ARRAY) then
    -- Determine dimensions and element count now for convenience
    local NewSafeArrayObject = {
      SafeArrayPointer = ResultValue,
      Type             = VARIANT_GetTypeName(ResultType),
      ElementCount     = SAFEARRAY_EvaluateCount(ResultValue)
    }
    -- Attach methods
    setmetatable(NewSafeArrayObject, SAFEARRAY_Metatable)
    ResultValue = NewSafeArrayObject
  end
  -- API: provide the "VT_XXX" as a string
  local TypeName = VARIANT_GetTypeName(ResultType)
  -- Return values
  return ResultValue, TypeName, ReturnError
end
COM_VariantToLua = COM_VariantToLuaImpl

local function DISPATCH_Invoke (Object, TypeString, NameUtf8, ...)
  -- Validate inputs
  local Type = COM_ConvertType(TypeString)
  assert(Type, format("Wrong type, got '%s', expected: 'method', 'propertyget', 'propertyput' or 'propertyputref'", TypeString))
  assert(NameUtf8)
  -- Retrieve data
  local Dispatch = Object.Dispatch
  -- Fetch IdOfName from cache
  local IdCache  = Object.IdCache
  local IdOfName = IdCache[NameUtf8]
  -- Populate cache
  if (IdOfName == nil) then
    local NameUtf16 = utf8to16(NameUtf8)
    local Result, Id = getidofname(Dispatch, NameUtf16)
    if HRESULT_SUCCEEDED(Result) then
      -- Update cache
      IdCache[NameUtf8] = Id
      -- Update local
      IdOfName = Id
    else
      error(format("Failed to get DISPID for '%s'", NameUtf8))
    end
  end
  -- Initialize VARIANTs
  local VariantArray = GLOBAL_VariantArray
  local ArgCount     = select("#", ...)
  -- Ensure capacity for all needed variants (result + parameters)
  VariantArray:EnsureCapacity(1 + ArgCount)
  -- Clear then initialize all variants (result + parameters) to avoid leaks
  for Index = 1, (1 + ArgCount) do
    local Variant = VariantArray:GetVariant(Index)
    -- If this slot was previously initialized, clear it first
    if VariantArray.InitDone[Index] then
      Variant:clear()
    end
    Variant:init()
  end
  -- Set parameter values in VARIANTs (reverse order for COM)
  for Index = 1, ArgCount do
    -- COM expects arguments in reverse order: rgvarg[0] is last argument
    local LuaValue = select((ArgCount - Index) + 1, ...)
    local Variant  = VariantArray:GetVariant(1 + Index)
    -- Choose type detection versus manual type
    if (type(LuaValue) == "table") then
      local Metatable = getmetatable(LuaValue)
      if ((Metatable == UNKNOWN_Metatable)
        or (Metatable == DISPATCH_Metatable)
        or (Metatable == SAFEARRAY_Metatable))
      then
        COM_VariantSetAuto(Variant, LuaValue)
      else
        local Value      = LuaValue[1]
        local TypeString = LuaValue[2]
        COM_VariantSetManual(Variant, Value, TypeString)
      end
    else
      COM_VariantSetAuto(Variant, LuaValue)
    end
  end
  -- Prepare Result and Parameters
  local VariantResult        = VariantArray:GetVariant(1)
  local VariantResultPointer = VariantResult:getpointer()
  local VariantParametersPointer
  if (ArgCount > 0) then
    local VariantParameters  = VariantArray:GetVariant(2)
    VariantParametersPointer = VariantParameters:getpointer()
  else
    VariantParametersPointer = NULL
  end
  -- Invoke
  --print("INVOKE", Object, Type, format("%8.8X", IdOfName), VariantResultPointer, VariantParametersPointer, ArgCount)
  local Result = invoke(Dispatch, Type, IdOfName, VariantResultPointer, VariantParametersPointer, ArgCount)
  -- Prepare results using COM_VariantToLua
  local ReturnValue
  local ReturnType
  local ErrorMessage
  if HRESULT_SUCCEEDED(Result) then
    ReturnValue, ReturnType, ErrorMessage = COM_VariantToLua(VariantResultPointer)
    -- Release result and parameter variants immediately to avoid holding refs
    VariantResult:clear()
    VariantResult:init()
    for Index = 1, ArgCount do
      local ParamVariant = VariantArray:GetVariant(1 + Index)
      ParamVariant:clear()
      ParamVariant:init()
    end
  else
    ReturnValue  = false
    ErrorMessage = format("Invoke failed with HRESULT 0x%08X", Result)
  end
  -- Return values
  return ReturnValue, ReturnType, ErrorMessage
end

-- High-level interface
local function DISPATCH_MethodCall (DispatchObject, ...)
  return DISPATCH_Invoke(DispatchObject, "method", ...)
end

local function DISPATCH_MethodGet (DispatchObject, ...)
  return DISPATCH_Invoke(DispatchObject, "propertyget", ...)
end

local function DISPATCH_MethodPut (DispatchObject, ...)
  return DISPATCH_Invoke(DispatchObject, "propertyput", ...)
end

local DISPATCH_MetatableImpl = {
  -- Generic methods
  __tostring = DISPATCH_MethodName,
  __gc       = DISPATCH_MethodGarbage,
  -- Custom methods
  __index = {
    invoke  = DISPATCH_Invoke,
    call    = DISPATCH_MethodCall,
    get     = DISPATCH_MethodGet,
    set     = DISPATCH_MethodPut,
    gettype = DISPATCH_GetType,
    members = DISPATCH_GetMembers,
    release = DISPATCH_MethodRelease,
  }
}
DISPATCH_Metatable = DISPATCH_MetatableImpl

-- ClsidUtf8: names like "Scripting.FileSystemObject"
local function COM_NewDispatch (ClsidUtf8)
  -- Local variables
  local NewDispatchPointer
  local NewDispatchObject
  -- Case where ClsidUtf8 is nil
  if ClsidUtf8 then
    local ClsidUtf16 = utf8to16(ClsidUtf8)
    local Clsid      = newclsid(ClsidUtf16)
    -- New dispatch
    if Clsid then
      local Result, Pointer = create(Clsid)
      if HRESULT_SUCCEEDED(Result) then
        NewDispatchPointer = Pointer
      else
        NewDispatchPointer = nil
      end
    end
  end
  -- Create the new Lua object
  if NewDispatchPointer then
    NewDispatchObject = DISPATCH_NewObject(ClsidUtf8, NewDispatchPointer)
    -- attach methods
    setmetatable(NewDispatchObject, DISPATCH_Metatable)
  end
  -- Return the created object
  return NewDispatchObject
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  newobject    = COM_NewDispatch,
  castunknown  = COM_CastUnknown,
  newdate      = COM_NewDateFromIso,
  newsafearray = SAFEARRAY_Create
}

return PUBLIC_API
