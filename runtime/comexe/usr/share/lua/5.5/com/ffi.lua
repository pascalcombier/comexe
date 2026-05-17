--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- High level interface:
-- local libc   = LibFFI.LoadLibrary("msvcrt.dll")
-- local malloc = libc:GetFunction(LibFFI.pointer, "malloc", LibFFI.uint64)
-- local free   = libc:GetFunction(LibFFI.void,    "free",   LibFFI.pointer)
-- local memset = libc:GetFunction(LibFFI.pointer, "memset", LibFFI.pointer, LibFFI.sint32, LibFFI.uint64)
-- local strlen = libc:GetFunction(LibFFI.uint64,  "strlen", LibFFI.pointer)

-- Or with type aliases:
-- local libc   = LibFFI.LoadLibrary("msvcrt.dll")
-- local malloc = libc:GetFunction(pointer, "malloc", uint64)
-- local free   = libc:GetFunction(void,    "free",   pointer)
-- local memset = libc:GetFunction(pointer, "memset", pointer, sint32, uint64)
-- local strlen = libc:GetFunction(uint64,  "strlen", pointer)

-- Types
--   newcstring return a garbage-collected C-string

-- Supported
--   ReturnCString
--   CallStructureByValue
--   ReturnStructureByValue
--   NestedStructure are supported

-- Limitations
-- * Does not support 32 bits (cdecl vs stdcall)
-- * Does not support nested/recursive callbacks
-- * Structure fields does not support C-strings

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi    = require("com.raw.libffi")
local StructFFI = require("com.ffi-structure")

local append     = table.insert
local format     = string.format
local concat     = table.concat
local unpack     = table.unpack
local numbertype = math.type

local fficall             = libffi.call
local loadlib             = libffi.loadlib
local getproc             = libffi.getproc
local newcif              = libffi.newcif
local newcallcontext      = libffi.newcallcontext
local getcifreturnpointer = libffi.getcifreturnpointer
local newclosure          = libffi.newclosure
local freecallcontext     = libffi.freecallcontext
local freecif             = libffi.freecif
local freelib             = libffi.freelib
local freeclosure         = libffi.freeclosure
local allocstring         = libffi.allocstring
local readstring          = libffi.readstring
local free                = libffi.free

local newarray        = libffi.newarray
local getarraypointer = libffi.getarraypointer
local arraygetvalue   = libffi.arraygetvalue
local arraysetvalue   = libffi.arraysetvalue
local arraygetvalues  = libffi.arraygetvalues
local arraysetvalues  = libffi.arraysetvalues
local arrayresize     = libffi.arrayresize
local arraycount      = libffi.arraycount
local freearray       = libffi.freearray

local void    = libffi.void
local uint8   = libffi.uint8
local sint8   = libffi.sint8
local uint16  = libffi.uint16
local sint16  = libffi.sint16
local uint32  = libffi.uint32
local sint32  = libffi.sint32
local uint64  = libffi.uint64
local sint64  = libffi.sint64
local float   = libffi.float
local double  = libffi.double
local pointer = libffi.pointer

-- Special type for automatic conversion between C strings and Lua strings
local CSTRING = {}

-- Those types might not be present at runtime
local complex_float  = libffi.complex_float
local complex_double = libffi.complex_double

-- Note that it also map Lua objects created with NewStructType to their
-- corresponding luaffi type (lightuserdata)
local FFI_TYPES = {
  [void]    = void,
  [uint8]   = uint8,
  [sint8]   = sint8,
  [uint16]  = uint16,
  [sint16]  = sint16,
  [uint32]  = uint32,
  [sint32]  = sint32,
  [uint64]  = uint64,
  [sint64]  = sint64,
  [float]   = float,
  [double]  = double,
  [pointer] = pointer,
  [CSTRING] = pointer,  -- cstring resolves to pointer for libffi
}

-- Note that it also map Lua objects created with NewStructType to their
-- corresponding name
local FFI_TYPE_NAME = {
  [void]    = "void",
  [uint8]   = "uint8",
  [sint8]   = "sint8",
  [uint16]  = "uint16",
  [sint16]  = "sint16",
  [uint32]  = "uint32",
  [sint32]  = "sint32",
  [uint64]  = "uint64",
  [sint64]  = "sint64",
  [float]   = "float",
  [double]  = "double",
  [pointer] = "pointer",
  [CSTRING] = "cstring",
}

-- Those types might not be present at runtime
if complex_float then
  FFI_TYPES[complex_float]     = complex_float
  FFI_TYPE_NAME[complex_float] = "complex_float"
end

if complex_double then
  FFI_TYPES[complex_double]     = complex_double
  FFI_TYPE_NAME[complex_double] = "complex_double"
end

-- FfiType -> LuaStructureObject
local FFI_STRUCT_TYPES = {
}

--------------------------------------------------------------------------------
-- TRIVIAL C-STRING                                                           --
--------------------------------------------------------------------------------

local function CSTRING_MethodGetPointer (Object)
  return Object.Pointer
end

local function CSTRING_MethodToString (Object)
  return readstring(Object.Pointer)
end

local function CSTRING_MethodFree (Object)
  free(Object.Pointer)
end

local CSTRING_Metatable = {
  -- METATABLE_LuaDefinedMethods
  __gc       = CSTRING_MethodFree,
  __tostring = CSTRING_MethodToString,
  -- METATABLE_UserDefinedMethods
  __index = {
    getpointer = CSTRING_MethodGetPointer,
  },
}

local function NewCString (LuaString)
  -- Allocate the string in the C side
  local Pointer = allocstring(LuaString)
  -- Create a new Lua wrapper
  local NewStringObject = {
    Pointer = Pointer,
  }
  -- Attach metatable
  setmetatable(NewStringObject, CSTRING_Metatable)
  -- Return value
  return NewStringObject
end

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function RegisterStructure (NewStructure)
  local FfiType  = NewStructure:getffitype()
  local TypeName = NewStructure:gettypename()
  -- Save type: LuaStructObject -> ffitype
  FFI_TYPES[NewStructure] = FfiType
  FFI_TYPES[FfiType]      = FfiType
  -- ffitype -> LuaStructObject
  FFI_STRUCT_TYPES[FfiType] = NewStructure
  -- Save name
  FFI_TYPE_NAME[NewStructure] = TypeName
  FFI_TYPE_NAME[FfiType]      = TypeName
end

-- newnamedstruct("MyPoint", LibFFI.uint32, "x", LibFFI.uint32, "y")
local function NewNamedStructure (...)
  local NewStructTypeObject, ErrorString = StructFFI.newnamedstruct(...)
  if NewStructTypeObject then
    RegisterStructure(NewStructTypeObject)
  end
  return NewStructTypeObject, ErrorString
end

-- newanonymousstruct(LibFFI.uint32, LibFFI.uint32)
local function NewAnonymousStructure (...)
  local NewStructTypeObject, ErrorString = StructFFI.newanonymousstruct(...)
  if NewStructTypeObject then
    RegisterStructure(NewStructTypeObject)
  end
  return NewStructTypeObject, ErrorString
end

-- "..." is composed of ReturnType and ParameterTypes
local function BuildSignature (...)
  local ElementCount = select("#", ...)
  local NewSignature = {}
  for Index = 1, ElementCount do
    local UserType = select(Index, ...)
    local FfiType  = FFI_TYPES[UserType]
    assert(FfiType, format("Invalid FFI type: %s [%q]", tostring(UserType), FFI_TYPE_NAME[UserType]))
    append(NewSignature, FfiType)
  end
  return NewSignature
end

--------------------------------------------------------------------------------
-- C ARRAYS: SUPPORT PRIMITIVE TYPES AND STRUCTURES                           --
--------------------------------------------------------------------------------

local function ARRAY_ConvertWriteValue (Array, Value)
  -- Identify array of structures
  local FfiType    = Array.FfiType
  local StructType = FFI_STRUCT_TYPES[FfiType]
  local ConvertedValue
  -- Case: structures
  if StructType then
    -- If value is nil, it will reset the memory to 0 (FFI_CopyLuaValueToCif)
    if Value then
      ConvertedValue = Value:getpointer()
    end
  -- Case: pointers
  elseif (FfiType == pointer) then
    local ValueType = type(Value)
    if (Value == nil) then
      ConvertedValue = nil
    elseif (ValueType == "userdata") then
      ConvertedValue = Value
    elseif (ValueType == "table") then
      if (type(Value.getpointer) ~= "function") then
        error(format("pointer array expects nil, userdata, or object with getpointer() method, got %s", ValueType))
      end
      ConvertedValue = Value:getpointer()
    elseif (ValueType == "string") then
      error("pointer array expects nil, userdata, or object with getpointer() method; use newcstring() for Lua strings")
    else
      error(format("pointer array expects nil, userdata, or object with getpointer() method, got %s", ValueType))
    end
  -- Case: primitive types
  else
    ConvertedValue = Value
  end
  -- Return value
  return ConvertedValue
end

local function ARRAY_ConvertReadValue (Array, Value)
  -- Identify array of structures
  local FfiType    = Array.FfiType
  local StructType = FFI_STRUCT_TYPES[FfiType]
  local ConvertedValue
  if StructType then
    -- Return a real structure instance
    ConvertedValue = StructType:frompointer(Value)
  else
    -- Pointer arrays intentionally expose pointers/lightuserdata
    ConvertedValue = Value
  end
  -- Return value
  return ConvertedValue
end

local function ARRAY_ToLua (Array)
  -- Retrieve data
  local Handle     = Array.Handle
  local ArrayCount = Array.Count
  -- Create a new array
  local NewValues  = {}
  -- Collect the values from the C side
  arraygetvalues(Handle, NewValues)
  -- Convert back structures from pointers
  for Index = 1, ArrayCount do
    local Value = NewValues[Index]
    NewValues[Index] = ARRAY_ConvertReadValue(Array, Value)
  end
  -- Return value
  return NewValues
end

local function ARRAY_FromLua (Array, LuaTable)
  -- Validate inputs
  assert((type(LuaTable) == "table"), "array fromlua expects a table")
  -- Retrieve data
  local Handle   = Array.Handle
  local Count    = Array.Count
  local NewCount = #LuaTable
  assert((NewCount >= 1), "array fromlua expects at least 1 element")
  -- Resize C side if needed
  if (NewCount ~= Count) then
    -- Extend the array on the C side
    arrayresize(Handle, NewCount)
    -- Update
    Array.Pointer = getarraypointer(Handle)
    Array.Count   = arraycount(Handle)
  end
  -- Create a temporary array with converted values (structures)
  local NewValues = {}
  for Index = 1, NewCount do
    local ComplexValue = LuaTable[Index]
    local SimpleValue  = ARRAY_ConvertWriteValue(Array, ComplexValue)
    NewValues[Index] = SimpleValue
  end
  -- Set the values
  arraysetvalues(Handle, NewValues)
end

local function ARRAY_GetPointer (Array)
  -- Retrieve data
  local Handle = Array.Handle
  -- Get pointer
  local NewPointer = getarraypointer(Handle)
  -- Update pointer
  Array.Pointer = NewPointer
  -- Return value
  return NewPointer
end

local function ARRAY_GetCount (Array)
  -- Retrieve data
  local Count = Array.Count
  -- Return value
  return Count
end

local function ARRAY_GetValue (Array, Index)
  -- Validate inputs
  assert((Index >= 1) and (Index <= Array.Count), format("array index out of bounds: %d [%d-%d]", Index, 1, Array.Count))
  -- Read a single value from the C side
  local Handle      = Array.Handle
  local SimpleValue = arraygetvalue(Handle, Index)
  -- Convert pointers to high-level structures if needed
  local ConvertedValue = ARRAY_ConvertReadValue(Array, SimpleValue)
  -- Return value
  return ConvertedValue
end

local function ARRAY_SetValue (Array, Index, Value)
  -- Validate inputs
  assert((Index >= 1), format("index must be positive: %d", Index))
  -- Retrieve data
  local Handle = Array.Handle
  local Count  = Array.Count
  -- Resize C side array if needed
  if (Index > Count) then
    -- Resize buffer
    arrayresize(Handle, Index)
    -- Update data
    Array.Pointer = getarraypointer(Handle)
    Array.Count   = arraycount(Handle)
  end
  -- Convert high-level structures to pointers if needed
  local SimpleValue = ARRAY_ConvertWriteValue(Array, Value)
  -- Writes the value on the C side
  arraysetvalue(Handle, Index, SimpleValue)
end

local function ARRAY_Length (Array)
  -- Retrieve data
  local Count = Array.Count
  -- Return value
  return Count
end

local function ARRAY_CollectGarbage (Array)
  local ArrayHandle = Array.Handle
  if (ArrayHandle) then
    -- Free resources
    freearray(ArrayHandle)
    Array.Handle  = nil
    Array.Pointer = nil
    Array.Count   = nil
  end
end

local ARRAY_METATABLE = {
  -- METATABLE_UserDefinedMethods
  __index = {
    getpointer = ARRAY_GetPointer,
    getcount   = ARRAY_GetCount,
    get        = ARRAY_GetValue,
    set        = ARRAY_SetValue,
    fromlua    = ARRAY_FromLua,
    tolua      = ARRAY_ToLua,
  },
  -- METATABLE_LuaDefinedMethods
  __len = ARRAY_Length,
  __gc  = ARRAY_CollectGarbage,
}

local function ARRAY_NewArray (ArrayType, ElementCount)
  -- Validate inputs
  local FfiType = FFI_TYPES[ArrayType]
  assert(FfiType, format("Invalid FFI type for newarray: %s", tostring(ArrayType)))
  assert((ElementCount >= 1), "newarray count should be >= 1")
  -- Create the array on the C side
  local NewArrayC = newarray(FfiType, ElementCount)
  -- Create a new array
  local NewArrayObject = {
    FfiType = FfiType,
    Handle  = NewArrayC,
    Pointer = getarraypointer(NewArrayC),
    Count   = arraycount(NewArrayC),
  }
  -- Attach metatable
  setmetatable(NewArrayObject, ARRAY_METATABLE)
  -- Return value
  return NewArrayObject
end

local function NewInstance (Type)
  -- Validate inputs
  local FfiType = FFI_TYPES[Type]
  assert(FfiType, format("Invalid type for newinstance: %s", tostring(Type)))
  -- Allocate as an array
  local NewArray = ARRAY_NewArray(Type, 1)
  local Result
  -- Primitives: return the array itself (has get/set/getpointer/GC)
  if (FFI_STRUCT_TYPES[FfiType] == nil) then
    Result = NewArray
  else
    -- Structures: return a StructureInstance anchored to the array
    Result = NewArray:get(1)
    -- Prevent garbage collection of the array
    Result.parentarray = NewArray
  end
  -- Return value
  return Result
end

--------------------------------------------------------------------------------
-- METATABLES                                                                 --
--------------------------------------------------------------------------------

local function LIBRARY_GarbageCollectMethod (Library)
  print(format("[GC] Releasing library resource: [%s]", Library.Filename))
  -- Clean up cached call contexts
  for CacheKey, CallContext in pairs(Library.ContextCache) do
    print(format("[GC] Releasing call context: [%s]", CacheKey))
    freecallcontext(CallContext)
  end
  -- Clean up cached Cif objects
  for CacheKey, Cif in pairs(Library.CifCache) do
    print(format("[GC] Releasing Cif: [%s]", CacheKey))
    freecif(Cif)
  end
  -- Clear all caches
  Library.SymbolCache   = nil
  Library.CifCache      = nil
  Library.ContextCache  = nil
  Library.VariadicCache = nil
  -- Free the library
  freelib(Library.Handle)
end

-- Return a string like "ReturnType-ParamType1-ParamType2-..."
local function MakeCacheKey (Signature)
  local ArgumentCount = #Signature
  local TypeNames     = {}
  for Index = 1, ArgumentCount do
    local Type     = Signature[Index]
    local TypeName = FFI_TYPE_NAME[Type]
    append(TypeNames, TypeName)
  end
  -- Concatenate tokens with separator
  local NewCacheKey = concat(TypeNames, "-")
  -- Return value
  return NewCacheKey
end

local function MakeCallableFunction (CallContext, FunctionPointer, Signature, DoReturnString)
  -- For CallStructureByValue we have a nice API allowing user to pass Lua
  -- high-level struct objects. To implement that, we need to check and replace
  -- every LuaObject by its underlying ffi_type. For that reason, we better use
  -- a table instead of vararg to call ffi_call: we reuse the same table for
  -- every call
  local ElementCount     = #Signature
  local ArgumentCount    = (ElementCount - 1)
  local FfiReturnType    = Signature[1]
  local ReturnStructType = FFI_STRUCT_TYPES[FfiReturnType]
  local HasStructReturn  = (ReturnStructType ~= nil)
  -- Determine if have at least 1 struct argument
  local HasStructArgument = false
  local ArgumentIndex     = 2
  while (not HasStructArgument) and (ArgumentIndex <= ElementCount) do
    local ArgType = Signature[ArgumentIndex]
    HasStructArgument = (FFI_STRUCT_TYPES[ArgType] ~= nil)
    ArgumentIndex     = (ArgumentIndex + 1)
  end
  -- Only for ReturnStructureByValue
  local ReturnStructInstance
  if HasStructReturn then
    local ReturnPointer = getcifreturnpointer(CallContext)
    ReturnStructInstance = ReturnStructType:frompointer(ReturnPointer)
  end
  -- Setup the function
  local Arguments = {}
  local Function
  if ((not HasStructArgument) and (not HasStructReturn) and (not DoReturnString)) then
    -- Simple calls with primitive types
    Function = function (...)
      -- Copy arguments without any conversion
      for Index = 1, ArgumentCount do
        Arguments[Index] = select(Index, ...)
      end
      -- Call the FFI
      return fficall(CallContext, FunctionPointer, Arguments)
    end
  else
    -- Complex calls: implement CallStructureByValue or cstring return
    Function = function (...)
      -- Convert structure StructureInstance into pointers
      for Index = 1, ArgumentCount do
        local Argument      = select(Index, ...)
        local ExpectedType  = Signature[Index + 1]
        local StructureType = FFI_STRUCT_TYPES[ExpectedType]
        if StructureType then
          Arguments[Index] = Argument:getpointer()
        else
          Arguments[Index] = Argument
        end
      end
      -- Call the FFI
      local CallResult = fficall(CallContext, FunctionPointer, Arguments)
      -- ReturnStructureByValue: Convert to an easy to use Lua object
      if HasStructReturn then
        CallResult = ReturnStructInstance
      end
      -- return a C-String: convert the pointer lightuserdata to Lua string
      -- NOTE: CallResult can be NULL
      if DoReturnString and CallResult then
        CallResult = readstring(CallResult)
      end
      return CallResult
    end
  end
  -- Return value
  return Function
end

-- Always create and return a new function
local function LIBRARY_MethodGetFunction (Library, ReturnType, FunctionName, ...)
  -- Extract arguments
  local Signature = BuildSignature(ReturnType, ...)
  local CifCache  = Library.CifCache
  local CacheKey  = MakeCacheKey(Signature)
  local Cif       = CifCache[CacheKey]
  -- Populate Cif cache if needed
  if (Cif == nil) then
    local NewCifValue = newcif(Signature)
    assert(NewCifValue, format("Failed to create new FFI cif [%s]", CacheKey))
    CifCache[CacheKey] = NewCifValue
    Cif = NewCifValue
  end
  -- Get function pointer
  local FunctionPointer = Library.SymbolCache[FunctionName]
  -- Populate symbol cache if needed
  if (FunctionPointer == nil) then
    FunctionPointer = getproc(Library.Handle, FunctionName)
    if FunctionPointer then
      Library.SymbolCache[FunctionName] = FunctionPointer
    else
      error(format("Failed to find function: [%s]", FunctionName))
    end
  end
  -- Get or create call context for this signature
  local CallContext = Library.ContextCache[CacheKey]
  -- Populate cache if needed
  if (CallContext == nil) then
    local NewCallContext, ErrorMessage = newcallcontext(Cif)
    assert(NewCallContext, ErrorMessage)
    Library.ContextCache[CacheKey] = NewCallContext
    -- Override
    CallContext = NewCallContext
  end
  local DoReturnString = (ReturnType == CSTRING)
  local Function       = MakeCallableFunction(CallContext, FunctionPointer, Signature, DoReturnString)
  -- Return value
  return Function
end

--------------------------------------------------------------------------------
-- FAKE VARIADICS ADDON (CONVENIENCE)                                         --
--------------------------------------------------------------------------------

-- This variadic wrapper is convenient but slower than functions created by
-- lib:getfunction.

-- Guess a FfiType based on Lua value
local function InferFfiType (Value)
  local ValueType = type(Value)
  local FfiType
  local ConvertedValue
  if (ValueType == "nil") then
    FfiType        = pointer
    ConvertedValue = nil
  elseif (ValueType == "string") then
    FfiType        = pointer
    ConvertedValue = Value
  elseif (ValueType == "boolean") then
    FfiType        = sint32
    ConvertedValue = (Value and 1 or 0)
  elseif (ValueType == "number") then
    if (numbertype(Value) == "integer") then
      FfiType        = sint32
      ConvertedValue = Value
    else
      FfiType        = double
      ConvertedValue = Value
    end
  elseif (ValueType == "table") then
    local Metatable = getmetatable(Value)
    assert(Metatable,            "Only objects created with newstructure can be infered properly (table)")
    assert(Metatable.getpointer, "Only objects created with newstructure can be infered properly (table)")
    FfiType        = pointer
    ConvertedValue = Value:getpointer()
  elseif (ValueType == "lightuserdata") then
    FfiType        = pointer
    ConvertedValue = Value
  else
    error(format("Unsupported variadic argument type: %s", ValueType))
  end
  return FfiType, ConvertedValue
end

local function LIBRARY_MethodGetVariadic (Library, ReturnType, FunctionName, ...)
  -- Fixed part: types declared by the user
  local FixedTypes     = { ... }
  local FixedCount     = #FixedTypes
  local FixedSignature = BuildSignature(ReturnType, unpack(FixedTypes, 1, FixedCount))
  -- Wrapper that will handle the variadic arguments
  local function VariadicWrapper (...)
    local TotalArgs = select("#", ...)
    if (TotalArgs < FixedCount) then
      error(format("Not enough arguments: expected at least %d", FixedCount))
    end
    -- Separate fixed arguments from variadic ones
    local VariadicCount  = (TotalArgs - FixedCount)
    local VariadicTypes  = {}
    local VariadicValues = {}
    -- Infer type for each variadic argument
    for VariadicIndex = 1, VariadicCount do
      -- Get the variadic argument
      local AbsoluteIndex    = (FixedCount + VariadicIndex)
      local VariadicArgument = select(AbsoluteIndex, ...)
      -- Infer the type and save the data
      local FfiType, ConvertedValue = InferFfiType(VariadicArgument)
      VariadicTypes[VariadicIndex]  = FfiType
      VariadicValues[VariadicIndex] = ConvertedValue
    end
    -- Build the full signature: fixed types + inferred variadic types
    local FullSignature = {}
    -- Copy fixed types
    for Index = 1, FixedCount do
      FullSignature[Index] = FixedSignature[Index]
    end
    -- Append variadic types
    for VariadicIndex = 1, VariadicCount do
      local VariadicType = VariadicTypes[VariadicIndex]
      append(FullSignature, VariadicType)
    end
    -- LIBRARY_MethodGetFunction will return a brand new function at each call
    -- So we want to cache that function and reuse it when possible
    -- Note the separator is different
    local VariadicCache  = Library.VariadicCache
    local CacheKey       = format("%s|%s", FunctionName, MakeCacheKey(FullSignature))
    local CachedFunction = VariadicCache[CacheKey]
    -- Build and cache the function if needed
    if (CachedFunction == nil) then
      -- Build argument list for LIBRARY_MethodGetFunction:
      -- { ReturnType, FunctionName, FixedTypes, VariadicTypes }
      local GetArgs = { ReturnType, FunctionName }
      for Index = 1, FixedCount do
        append(GetArgs, FixedTypes[Index])
      end
      for Index = 1, VariadicCount do
        append(GetArgs, VariadicTypes[Index])
      end
      CachedFunction = LIBRARY_MethodGetFunction(Library, unpack(GetArgs, 1, #GetArgs))
      VariadicCache[CacheKey] = CachedFunction
    end
    -- Prepare call arguments
    local CallArguments = {}
    for Index = 1, FixedCount do
      CallArguments[Index] = select(Index, ...)
    end
    for VariadicIndex = 1, VariadicCount do
      local AbsoluteIndex = (FixedCount + VariadicIndex)
      local VariadicValue = VariadicValues[VariadicIndex]
      CallArguments[AbsoluteIndex] = VariadicValue
    end
    -- Call and return
    return CachedFunction(unpack(CallArguments, 1, TotalArgs))
  end
  -- Return value
  return VariadicWrapper
end

--------------------------------------------------------------------------------
-- LIBRARY METATABLE                                                          --
--------------------------------------------------------------------------------

local LIBRARY_Metatable = {
  -- METATABLE_LuaDefinedMethods
  __gc = LIBRARY_GarbageCollectMethod,
  -- METATABLE_UserDefinedMethods
  __index = {
    getfunction = LIBRARY_MethodGetFunction,
    getvariadic = LIBRARY_MethodGetVariadic,
  }
}

local function LoadLibrary (DllFilename)
  local Handle = loadlib(DllFilename)
  local NewLibraryObject
  if Handle then
    -- Create a new library object
    NewLibraryObject = {
      Filename      = DllFilename,
      Handle        = Handle,
      SymbolCache   = {},
      CifCache      = {},
      ContextCache  = {},
      VariadicCache = {},
    }
    -- Attach methods
    setmetatable(NewLibraryObject, LIBRARY_Metatable)
  end
  -- Return value
  return NewLibraryObject
end

-- Wrap a C function pointer into a callable Lua function. Typical use is libtcc
-- functions.
--
-- The responsability to the caller to keep the context while necessary
local function WrapFunction (RawSymbol, ReturnType, ...)
  -- Validate inputs
  local Signature = BuildSignature(ReturnType, ...)
  -- Prepare the function and wrap it
  local Cif, ErrorString = newcif(Signature)
  assert(Cif, ErrorString)
  local CallContext    = newcallcontext(Cif)
  local DoStringReturn = (ReturnType == CSTRING)
  local CallFunction   = MakeCallableFunction(CallContext, RawSymbol, Signature, DoStringReturn)
  local NewPrivateContext = { Cif, CallContext }
  -- Return values
  return CallFunction, NewPrivateContext
end

local function CLOSURE_GarbageCollectMethod (ClosureObject)
  print(format("[GC] Releasing FFI closure resource"))
  -- Retrieve data
  local ClosureUserdata = ClosureObject.ClosureUserdata
  local Cif             = ClosureObject.Cif
  -- Release resources
  freeclosure(ClosureUserdata)
  freecif(Cif)
end

local CLOSURE_Metatable = {
  -- METATABLE_LuaDefinedMethods
  __gc = CLOSURE_GarbageCollectMethod
}

-- Wrapper to support StructureByValue in callbacks:
-- 1) Convert structure pointers into Lua structure objects
-- 2) Call user Lua function
-- 3) Convert a returned Lua structure object back into a pointer
local function BuildClosureWrapper (UserFunction, Signature)
  -- local data
  local ReturnFfiType    = Signature[1]
  local ReturnStructType = FFI_STRUCT_TYPES[ReturnFfiType]
  local ElementCount     = #Signature
  local ArgumentCount    = (ElementCount - 1)
  -- Map argument index to either nil (not struct) either StructureType
  local ArgumentStructMap = {}
  -- Identify arguments which are structures
  for Index = 1, ArgumentCount do
    local ArgType       = Signature[Index + 1]
    local ArgStructType = FFI_STRUCT_TYPES[ArgType]
    ArgumentStructMap[Index] = ArgStructType
  end
  -- Reuse over calls
  local ConvertedArguments = {}
  -- Wrapper: This function will be called by the C layer
  -- Wrapper: convert structure pointers into Lua objects
  local function WrappedFunction (...)
    for Index = 1, ArgumentCount do
      local Argument      = select(Index, ...)
      local StructureType = ArgumentStructMap[Index]
      if StructureType then
        assert((type(Argument) == "userdata"), format("Closure argument %d should be struct pointer", Index))
        -- Create a new Lua object
        ConvertedArguments[Index] = StructureType:frompointer(Argument)
      else
        ConvertedArguments[Index] = Argument
      end
    end
    -- Call the user function
    local CallResult = UserFunction(unpack(ConvertedArguments, 1, ArgumentCount))
    -- Evaluate result
    local Result
    if (ReturnStructType and type(CallResult) == "table") then
      assert((CallResult.StructType == ReturnStructType),
        format("Closure returned unexpected structure type, expected [%s]", ReturnStructType:gettypename()))
      -- The result is for the C layer
      Result = CallResult:getpointer()
    else
      -- Default: use CallResult directly to cover the cases
      --   No ReturnStructType
      --   ReturnStructType but CallResult is nil
      --   ReturnStructType but CallResult is userdata 
      Result = CallResult
    end
    -- Return value
    return Result
  end
  -- Return value
  return WrappedFunction
end

local function CreateClosure (UserFunction, ReturnType, ...)
  -- Validate inputs
  assert(type(UserFunction)=="function", "First argument must be a Lua function")
  local Signature = BuildSignature(ReturnType, ...)
  -- Check if the signature contains a structure
  local ReturnFfiType   = Signature[1]
  local HasStructType  = (FFI_STRUCT_TYPES[ReturnFfiType] ~= nil)
  local SignatureCount = #Signature
  local SignatureIndex = 2
  while ((not HasStructType) and (SignatureIndex <= SignatureCount)) do
    local ArgumentType = Signature[SignatureIndex]
    HasStructType  = (FFI_STRUCT_TYPES[ArgumentType] ~= nil)
    SignatureIndex = (SignatureIndex + 1)
  end
  -- Choose the right wrapper
  local WrappedFunction
  if HasStructType then
    -- Call a wrapper that convert structure pointers
    WrappedFunction = BuildClosureWrapper(UserFunction, Signature)
  else
    -- Directly call the user function
    WrappedFunction = UserFunction
  end
  -- Create the Call Interface
  local Cif = newcif(Signature)
  assert(Cif, "Failed to create ffi cif for closure")
  local ClosureUserdata, ClosurePointer = newclosure(Cif, WrappedFunction)
  local NewClosureObject = {
    Cif             = Cif,
    ClosureUserdata = ClosureUserdata,
    ClosurePointer  = ClosurePointer,
  }
  -- Attach metatable with garbage collector
  setmetatable(NewClosureObject, CLOSURE_Metatable)
  -- Return value
  return NewClosureObject, ClosurePointer
end

--------------------------------------------------------------------------------
-- MODULE INTERFACE                                                           --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  -- High level functions
  loadlib        = LoadLibrary,
  -- Those functions are intended to work with libtcc
  newluafunction = WrapFunction,  -- C function pointer -> Lua function
  newcfunction   = CreateClosure, -- Lua function       -> C function pointer
  -- Direct imports from libffi raw bindings
  readpointer    = libffi.readpointer,
  newpointer     = libffi.newpointer, -- (High, Low)
  convertpointer = libffi.convertpointer,
  derefpointer   = libffi.derefpointer,
  readmemory     = libffi.readmemory,
  writememory    = libffi.writememory,
  pointeroffset  = libffi.pointeroffset,
  pointerdiff    = libffi.pointerdiff,
  -- structures
  newstructure   = NewNamedStructure,
  newstructurea  = NewAnonymousStructure,
  newarray       = ARRAY_NewArray,
  newinstance    = NewInstance, -- alias for newarray(1)
  -- mimalloc
  getpagesize  = libffi.getpagesize,
  malloc       = libffi.malloc,
  realloc      = libffi.realloc,
  free         = libffi.free,
  memset       = libffi.memset,
  NULL         = libffi.NULL,
  POINTER_SIZE = libffi.POINTER_SIZE,
  -- C-string helpers
  allocstring = libffi.allocstring,
  readstring  = libffi.readstring,
  newcstring  = NewCString,
  -- ffi types
  void    = void,
  uint8   = uint8,
  sint8   = sint8,
  uint16  = uint16,
  sint16  = sint16,
  uint32  = uint32,
  sint32  = sint32,
  uint64  = uint64,
  sint64  = sint64,
  float   = float,
  double  = double,
  pointer = pointer,
  -- those types might resolve to nil (and be absent from PUBLIC_API)
  complex_float  = complex_float,
  complex_double = complex_double,
  -- helpful
  size_t  = uint64,
  cstring = CSTRING,
}

return PUBLIC_API
