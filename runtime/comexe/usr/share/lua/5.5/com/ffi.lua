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
-- * Does not support struct-by-value callbacks

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local LibFFI    = require("com.raw.libffi")
local StructFFI = require("com.ffi-structure")

local append = table.insert
local format = string.format
local concat = table.concat

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

-- FfiType -> LuaStructureObject
local FFI_STRUCT_TYPES = {
}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

-- By design, the C layer does not validate inputs
local function ValidateFfiType (Type)
  local ValidFfiType = FFI_TYPES[Type]
  -- Validate inputs
  assert(ValidFfiType, format("Invalid FFI type: %s [%q]", tostring(Type), FFI_TYPE_NAME[Type]))
  -- Return value
  return ValidFfiType
end

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

local function LIBRARY_MethodGetFunction (Library, ReturnType, FunctionName, ...)
  -- Extract arguments
  local ArgumentCount = select("#", ...)
  local Signature     = { ValidateFfiType(ReturnType) }
  for Index = 1, ArgumentCount do
    local Argument = select(Index, ...)
    local FfiType  = ValidateFfiType(Argument)
    append(Signature, FfiType)
  end
  local CifCache = Library.CifCache
  local CacheKey = MakeCacheKey(Signature)
  local Cif      = CifCache[CacheKey]
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

local LIBRARY_Metatable = {
  -- MetatableLuaDefinedMethods
  __gc = LIBRARY_GarbageCollectMethod,
  -- MetatableUserDefinedMethods
  __index = {
    getfunction = LIBRARY_MethodGetFunction
  }
}

local function LoadLibrary (DllFilename)
  local Handle = loadlib(DllFilename)
  local NewLibraryObject
  if Handle then
    -- Create a new library object
    NewLibraryObject = {
      Filename     = DllFilename,
      Handle       = Handle,
      SymbolCache  = {},
      CifCache     = {},
      ContextCache = {},
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
  local ArgumentCount = select("#", ...)
  local Signature     = { ValidateFfiType(ReturnType) }
  for Index = 1, ArgumentCount do
    local Argument = select(Index, ...)
    local FfiType  = ValidateFfiType(Argument)
    append(Signature, FfiType)
  end
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
  -- MetatableLuaDefinedMethods
  __gc = CLOSURE_GarbageCollectMethod
}

local function CreateClosure (LuaFunction, ReturnType, ...)
  -- Validate inputs
  assert(type(LuaFunction)=="function", "First argument must be a Lua function")
  local ArgumentCount = select("#", ...)
  local Signature     = { ValidateFfiType(ReturnType) }
  for Index = 1, ArgumentCount do
    local Argument = select(Index, ...)
    local FfiType  = ValidateFfiType(Argument)
    append(Signature, FfiType)
  end
  local Cif = newcif(Signature)
  assert(Cif, "Failed to create ffi cif for closure")
  local ClosureUserdata, ClosurePointer = newclosure(Cif, LuaFunction)
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
  newluafunction = WrapFunction,  -- C function pointer -> Lua functions
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
  newstructtype    = NewNamedStructure,
  newstructtype2   = NewAnonymousStructure,
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
  -- helpful
  size_t = uint64
}

return PUBLIC_API
