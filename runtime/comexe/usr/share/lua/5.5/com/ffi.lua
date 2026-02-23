--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Limitations
-- * Does not support 32 bits (cdecl vs stdcall)
-- * Does not support nested/recursive callbacks

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

-- Import raw bindings
local LibFFI = require("com.raw.libffi")

-- local imports
local format = string.format
local concat = table.concat

-- Localize
local fficall         = LibFFI.call
local loadlib         = LibFFI.loadlib
local getproc         = LibFFI.getproc
local newcif          = LibFFI.newcif
local newcallcontext  = LibFFI.newcallcontext
local newclosure      = LibFFI.newclosure
local freecallcontext = LibFFI.freecallcontext
local freecif         = LibFFI.freecif
local freelib         = LibFFI.freelib
local freeclosure     = LibFFI.freeclosure

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

local function LIBRARY_MethodGetFunction (Library, ReturnType, FunctionName, ...)
  -- Create cache key for the function signature
  local CacheKey = concat({ReturnType, ...}, "-")
  local Cif      = Library.CifCache[CacheKey]
  -- Populate Cif cache if needed
  if (Cif == nil) then
    local NewCif, ErrorMessage = newcif(ReturnType, ...)
    assert(NewCif, format("%s [%s]", ErrorMessage, CacheKey))
    Library.CifCache[CacheKey] = NewCif
    Cif = NewCif
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
  -- Return a function that uses the cached context
  local Function = function (...)
    return fficall(CallContext, FunctionPointer, ...)
  end
  -- Return value
  return Function
end

local LIBRARY_Metatable = {
  -- Pre-defined Lua methods
  __gc = LIBRARY_GarbageCollectMethod,
  -- Custom methods
  __index = {
    GetFunction = LIBRARY_MethodGetFunction
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
  -- Prepare the function and wrap it
  local Cif, ErrorMessage = newcif(ReturnType, ...)
  assert(Cif, ErrorMessage)
  local CallContext, ctxErr = newcallcontext(Cif)
  assert(CallContext, ctxErr)
  local function CallFunction (...)
    return fficall(CallContext, RawSymbol, ...)
  end
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
  -- Pre-defined Lua methods
  __gc = CLOSURE_GarbageCollectMethod
}

local function CreateClosure (LuaFunction, ReturnType, ...)
  -- Validate inputs
  assert(type(LuaFunction)=="function", "First argument must be a Lua function")
  -- Cfi
  local Cif, ErrorMessage = newcif(ReturnType, ...)
  assert(Cif, ErrorMessage)
  local ClosureUserdata, ClosurePointer = newclosure(Cif, LuaFunction)
  local NewClosureObject = {
    Cif             = Cif,
    ClosureUserdata = ClosureUserdata,
    ClosurePointer  = ClosurePointer,
  }
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
  newpointer     = LibFFI.newpointer, -- (High, Low)
  convertpointer = LibFFI.convertpointer,
  derefpointer   = LibFFI.derefpointer,
  readpointer    = LibFFI.readpointer,
  writepointer   = LibFFI.writepointer,
  -- mimalloc
  getpagesize = LibFFI.getpagesize,
  malloc      = LibFFI.malloc,
  realloc     = LibFFI.realloc,
  free        = LibFFI.free,
  memset      = LibFFI.memset,
  NULL        = LibFFI.NULL,
}

return PUBLIC_API
