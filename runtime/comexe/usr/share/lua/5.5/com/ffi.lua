--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- We implement CallStructureByValue and ReturnStructureByValue

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

-- Limitations
-- * Does not support 32 bits (cdecl vs stdcall)
-- * Does not support nested/recursive callbacks

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local LibFFI    = require("com.raw.libffi")
local StructFFI = require("com.ffi-structure")

local append = table.insert
local format = string.format
local concat = table.concat
local unpack = table.unpack

local fficall             = LibFFI.call
local loadlib             = LibFFI.loadlib
local getproc             = LibFFI.getproc
local newcif              = LibFFI.newcif
local newcallcontext      = LibFFI.newcallcontext
local getcifreturnpointer = LibFFI.getcifreturnpointer
local newclosure          = LibFFI.newclosure
local freecallcontext     = LibFFI.freecallcontext
local freecif             = LibFFI.freecif
local freelib             = LibFFI.freelib
local freeclosure         = LibFFI.freeclosure

local void    = LibFFI.void
local uint8   = LibFFI.uint8
local sint8   = LibFFI.sint8
local uint16  = LibFFI.uint16
local sint16  = LibFFI.sint16
local uint32  = LibFFI.uint32
local sint32  = LibFFI.sint32
local uint64  = LibFFI.uint64
local sint64  = LibFFI.sint64
local float   = LibFFI.float
local double  = LibFFI.double
local pointer = LibFFI.pointer

-- Those types might not be present at runtime
local complex_float  = LibFFI.complex_float
local complex_double = LibFFI.complex_double

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

-- newnamedstruct("MyPoint", "x", LibFFI.uint32, "y", LibFFI.uint32)
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
  Library.SymbolCache  = nil
  Library.CifCache     = nil
  Library.ContextCache = nil
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

local function MakeCallableFunction (CallContext, FunctionPointer, Signature)
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
  if ((not HasStructArgument) and (not HasStructReturn)) then
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
    -- Complex calls: implement CallStructureByValue
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
  local Function = MakeCallableFunction(CallContext, FunctionPointer, Signature)
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
    FfiType        = double
    ConvertedValue = Value
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
-- METATABLE                                                                  --
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
  local CallContext  = newcallcontext(Cif)
  local CallFunction = MakeCallableFunction(CallContext, RawSymbol, Signature)
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
  readpointer    = LibFFI.readpointer,
  newpointer     = LibFFI.newpointer, -- (High, Low)
  convertpointer = LibFFI.convertpointer,
  derefpointer   = LibFFI.derefpointer,
  readmemory     = LibFFI.readmemory,
  writememory    = LibFFI.writememory,
  pointeroffset  = LibFFI.pointeroffset,
  pointerdiff    = LibFFI.pointerdiff,
  -- structure by value
  newstructure   = NewNamedStructure,
  newstructurea  = NewAnonymousStructure,
  -- mimalloc
  getpagesize = LibFFI.getpagesize,
  malloc      = LibFFI.malloc,
  realloc     = LibFFI.realloc,
  free        = LibFFI.free,
  memset      = LibFFI.memset,
  NULL        = LibFFI.NULL,
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
  size_t = uint64
}

return PUBLIC_API
