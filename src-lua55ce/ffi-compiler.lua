--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Using Facebook cparser, parse a C header (file.h) and generate a Lua
-- binding suitable for ComEXE libffi (file.lua)
--
-- CPARSER DOCUMENTATION
--
-- https://github.com/facebookresearch/CParser/tree/main
--
-- #define will only work with a specified value
-- #define TEST
-- => TEST has no value ("captured" is false) declarationIterator will not trigger a CppEvent
-- 
-- #define TEST 123
-- #undef TEST
-- TEST is 123 ("captured" is true) declarationIterator will trigger a CppEvent
--
-- #define TEST "test"
-- will be ignored as well, strings are not supported by CParser
--
-- LIMITATIONS
--
-- NOT SUPPORTED: bitfield (in structures) 
-- NOT SUPPORTED: UNIONS
--
--
-- USAGE
--
-- > lua55ce -x --compile sqlite3.h
--
-- Then:
-- local ffi     = require("com.ffi")
-- local Sqlite3 = ffi.loadlib("windows", "sqlite3.dll", "linux", "libsqlite3.so")
-- 
-- if Sqlite3 then
--   local Sqlite3Ffi = require("sqlite3-ffi")
--   Sqlite3:attach(Sqlite3Ffi)
--   print("SQlite", Sqlite3.sqlite3_libversion())
-- else
--   print("DLL NOT FOUND")
-- end
--

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local CParser = require("cparser")
local Runtime = require("com.runtime")

local format     = string.format
local append     = table.insert
local concat     = table.concat
local sort       = table.sort
local lower      = string.lower
local sub        = string.sub
local find       = string.find
local numbertype = math.type

local getparam = Runtime.getparam

-- Keep structures, if not known structure, it will fallback to pointer
local KnownStructTypes

-- Generate the structures in the same order they have been declared
local StructDeclarationOrder

--------------------------------------------------------------------------------
-- CPARSER OPTIONS                                                            --
--------------------------------------------------------------------------------

-- C11 with GNU extensions (201112L = C11)
local CParserOptions = {
  "-std=gnu11",
  "-D__STDC__=1",
  "-D__STDC_VERSION__=201112L",
}

-- CParserOptions does not support -D values with __attribute__(()). Because of
-- this limitation, we implement this straight-forward workaround: we inject
-- the define as a constant prefix.
--
-- This COMEXE_WIN32COM_INTERFACE allow us to generate a Win32 Com interface
-- suitable for easycom (static vtable COM interface).
--
local C_HEADER_PREFIX = [[
  #define COMEXE_WIN32COM_INTERFACE __attribute__((comexe_win32com_interface))
]]

--------------------------------------------------------------------------------
-- LINE ITERATOR                                                              --
--------------------------------------------------------------------------------

local function NewLineIterator (Text)
  -- Local data
  local Position    = 1
  local SizeInBytes = #Text
  local Done        = false
  -- Local functions
  local function NextLine ()
    local Result
    if Done then
      Result = nil
    elseif (Position > SizeInBytes) then
      Done = true
    else
      local NewLinePosition = find(Text, "\n", Position, true)
      if NewLinePosition then
        Result   = sub(Text, Position, (NewLinePosition - 1))
        Position = (NewLinePosition + 1)
      else
        Result = sub(Text, Position)
        Done   = true
      end
    end
    return Result
  end
  -- Return value
  return NextLine
end

--------------------------------------------------------------------------------
-- SORTING                                                                    --
--------------------------------------------------------------------------------

local function CompareCaseInsensitive (StringA, StringB)
  local LowerA = lower(StringA)
  local LowerB = lower(StringB)
  return (LowerA < LowerB)
end

local function GetSortedKeys (Table)
  -- Extract keys
  local Keys = {}
  for Key in pairs(Table) do
    append(Keys, Key)
  end
  -- Sort
  sort(Keys, CompareCaseInsensitive)
  -- Return value
  return Keys
end

--------------------------------------------------------------------------------
-- C TYPE TO FFI TOKEN MAPPING                                                --
--------------------------------------------------------------------------------

local PrimitiveFfiToken = {
  ["void"]                   = "void",
  ["_Bool"]                  = "sint8",
  ["char"]                   = "sint8",
  ["signed char"]            = "sint8",
  ["unsigned char"]          = "uint8",
  ["short"]                  = "sint16",
  ["short int"]              = "sint16",
  ["unsigned short"]         = "uint16",
  ["unsigned short int"]     = "uint16",
  ["int"]                    = "sint32",
  ["signed"]                 = "sint32",
  ["signed int"]             = "sint32",
  ["unsigned"]               = "uint32",
  ["unsigned int"]           = "uint32",
  ["long long"]              = "sint64",
  ["long long int"]          = "sint64",
  ["unsigned long long"]     = "uint64",
  ["unsigned long long int"] = "uint64",
  ["float"]                  = "float",
  ["double"]                 = "double",
  ["long double"]            = "double",
  ["size_t"]                 = "uint64",
  -- standard types from C headers
  ["intptr_t"]               = "sint64",
  ["uintptr_t"]              = "uint64",
  ["ptrdiff_t"]              = "sint64",
  ["int8_t"]                 = "sint8",
  ["uint8_t"]                = "uint8",
  ["int16_t"]                = "sint16",
  ["uint16_t"]               = "uint16",
  ["int32_t"]                = "sint32",
  ["uint32_t"]               = "uint32",
  ["int64_t"]                = "sint64",
  ["uint64_t"]               = "uint64",
}

if (getparam("OS") == "windows") then
  PrimitiveFfiToken["long"]              = "sint32"
  PrimitiveFfiToken["long int"]          = "sint32"
  PrimitiveFfiToken["unsigned long"]     = "uint32"
  PrimitiveFfiToken["unsigned long int"] = "uint32"
else
  PrimitiveFfiToken["long"]              = "sint64"
  PrimitiveFfiToken["long int"]          = "sint64"
  PrimitiveFfiToken["unsigned long"]     = "uint64"
  PrimitiveFfiToken["unsigned long int"] = "uint64"
end

-- cparser documentation:
--   For instance, the type const int is printed as
--   Qualified{t=Type{n="int"},const=true}
--  and corresponds to
--      {
--        tag="Qualified",
--        const=true,
--        t= {
--             tag="Type",
--             n = "int"
--           }
--      }

local function UnwrapBaseType (TypeNode)
  local CurrentNode = TypeNode
  while CurrentNode and (CurrentNode.tag == "Qualified") do
    CurrentNode = CurrentNode.t
  end
  return CurrentNode
end

local function TypeIs (TypeNode, TargetTag)
  local CurrentNode = UnwrapBaseType(TypeNode)
  local Result      = (CurrentNode and (CurrentNode.tag == TargetTag))
  return Result
end

local function ResolveType (LibffiVariable, AstType, IsReturnType)
  local Current = UnwrapBaseType(AstType)
  local Result
  if (Current == nil) then
    Result = format("%s.void", LibffiVariable)
  elseif (Current.tag == "Type") then
    local FfiTypeString = PrimitiveFfiToken[Current.n]
    if FfiTypeString then
      Result = format("%s.%s", LibffiVariable, FfiTypeString)
    elseif KnownStructTypes[Current.n] then
      Result = Current.n -- StructByValue
    else
      Result = format("%s.pointer", LibffiVariable)
    end
  elseif (Current.tag == "Pointer") then
    -- Only IsReturnType has automatic cstring conversions
    if IsReturnType then
      local BaseType = UnwrapBaseType(Current.t)
      if BaseType and (BaseType.tag == "Type") and (BaseType.n == "char") then
        Result = format("%s.cstring", LibffiVariable)
      else
        Result = format("%s.pointer", LibffiVariable)
      end
    else
      Result = format("%s.pointer", LibffiVariable)
    end
  elseif (Current.tag == "Array") then
    Result = format("%s.pointer", LibffiVariable)
  elseif (Current.tag == "Function") then
    Result = format("%s.pointer", LibffiVariable)
  elseif (Current.tag == "Enum") then
    Result = format("%s.sint32", LibffiVariable)
  else
    Result = format("%s.pointer", LibffiVariable)
  end
  return Result
end

--------------------------------------------------------------------------------
-- STRUCT FIELD TYPE RESOLUTION                                               --
--------------------------------------------------------------------------------

local function ResolveFieldType (LibffiVariable, AstType)
  local Current = UnwrapBaseType(AstType)
  local Result
  if (Current == nil) then
    Result = format("%s.void", LibffiVariable)
  elseif (Current.tag == "Type") then
    local FfiTypeString = PrimitiveFfiToken[Current.n]
    if FfiTypeString then
      Result = format("%s.%s", LibffiVariable, FfiTypeString)
    elseif KnownStructTypes[Current.n] then
      Result = Current.n
    else
      Result = format("%s.pointer", LibffiVariable)
    end
  elseif (Current.tag == "Pointer") then
    local BaseType = UnwrapBaseType(Current.t)
    if BaseType and (BaseType.tag == "Type") and (BaseType.n == "char") then
      Result = format("%s.cstring", LibffiVariable)
    else
      Result = format("%s.pointer", LibffiVariable)
    end
  elseif (Current.tag == "Array") then
    Result = format("%s.pointer", LibffiVariable)
  elseif (Current.tag == "Function") then
    Result = format("%s.pointer", LibffiVariable)
  elseif (Current.tag == "Enum") then
    Result = format("%s.sint32", LibffiVariable)
  else
    Result = format("%s.pointer", LibffiVariable)
  end
  return Result
end

--------------------------------------------------------------------------------
-- CPARSER INTEGRATION                                                        --
--------------------------------------------------------------------------------

local function ParseHeader (HeaderString)
  -- Prepend built-in defines
  local PatchedHeaderString = format("%s%s", C_HEADER_PREFIX, HeaderString)
  -- Init structures order
  KnownStructTypes       = {}
  StructDeclarationOrder = {}
  -- Parse
  local Functions    = {}
  local Constants    = {}
  local Structures   = {}
  local LineIterator = NewLineIterator(PatchedHeaderString)
  local Iterator     = CParser.declarationIterator(CParserOptions, LineIterator, "ffi-compiler")
  local Action       = Iterator()
  while Action do
    local ActionName = Action.name
    local ActionTag  = Action.tag
    if (ActionTag == "CppEvent") then
      local Directive = Action.directive
      if (Directive == "define") then
        assert(Action.intval, "Expected integer value for #define")
        Constants[ActionName] = Action.intval
      else
        print(format("WARNING: %s directive '%s(%s)' ignored", ActionTag, Directive, ActionName))
      end
    elseif (ActionTag == "Declaration") or (ActionTag == "Definition") then
      if (Action.sclass == "[enum]") and ActionName then
        assert(Action.intval, "Expected integer value for enum constant")
        Constants[ActionName] = Action.intval
      elseif TypeIs(Action.type, "Function") and ActionName then
        local FunctionType = UnwrapBaseType(Action.type)
        if (not FunctionType.inline) and (not FunctionType.withoutProto) then
          local NewFunction = {
            name = ActionName,
            type = FunctionType
          }
          append(Functions, NewFunction)
        end
      end
    elseif (ActionTag == "TypeDef") and ((Action.sclass == "[typetag]") or (Action.sclass == "typedef")) then
      local BaseType = UnwrapBaseType(Action.type)
      if BaseType then
        if (BaseType.tag == "Struct") then
          if (#BaseType > 0) then
            Structures[ActionName] = Action
            KnownStructTypes[ActionName] = true
            append(StructDeclarationOrder, ActionName)
          end
        elseif (BaseType.tag == "Union") then
          print(format("WARNING: union '%s' not supported", ActionName))
        end
      end
    end
    -- Calling this function produces three results:
    --   A declaration iterator function.
    --   A symbol table.
    --   A macro definition table.
    --
    -- Here, we ignore symbol amd macro table
    Action = Iterator()
  end
  -- Return value
  return Functions, Constants, Structures
end

--------------------------------------------------------------------------------
-- CODE GENERATION                                                            --
--------------------------------------------------------------------------------

-- STRUCTURES
--
-- Tagged struct: struct MyStruct { ... };
-- Action.name  = "struct MyStruct" -> StructName = "struct MyStruct"
-- StructNode.n = "MyStruct"        -> TagName = "MyStruct"
--
-- Anonymous struct in typedef: typedef struct { ... } IShellItemVtbl
-- Action.name  = "IShellItemVtbl"   -> StructName = "IShellItemVtbl"
-- StructNode.n = nil                -> TagName = nil
--
local function GetStructureName (StructAction, StructName)
  local StructNode = UnwrapBaseType(StructAction.type)
  local Result     = StructNode.n
  if (not Result) then
    Result = StructName
  end
  return Result
end

local function EmitConstant (Lines, Name, Value)
  local ValueType = type(Value)
  local Line
  if (ValueType == "table") then
    if (Value.tag == "string") then
      Line = format("local %s = %q", Name, Value.value)
    else
      Line = format("local %s = %s", Name, tostring(Value.value))
    end
  elseif (ValueType == "number") then
    if (numbertype(Value) == "integer") then
      Line = format("local %s = %d", Name, Value)
    else
      Line = format("local %s = %s", Name, tostring(Value))
    end
  end
  if Line then
    append(Lines, Line)
  else
    print(format("Warning: Skipping constant '%s' with unsupported value type '%s'", Name, ValueType))
  end
end

--------------------------------------------------------------------------------
-- STRUCT TYPE                                                                --
--------------------------------------------------------------------------------

-- Detect COM interface by reading attribute
local function HasWin32ComInterfaceAttribute (StructNode)
  local Attributes = StructNode.attr
  local Index      = 1
  local Count
  if Attributes then
    Count = #Attributes
  else
    Count = 0
  end
  local Found = false
  while (not Found) and (Index <= Count) do
    if (Attributes[Index] == "comexe_win32com_interface") then
      Found = true
    else
      Index = (Index + 1)
    end
  end
  return Found
end

-- Extract method signature from a function-pointer field
-- Returns: ReturnTypeToken, { ParamTypeToken, ... }
local function ExtractMethodSignature (FieldType, LibffiVariable)
  local CurrentType = UnwrapBaseType(FieldType)
  local InnerType   = UnwrapBaseType(CurrentType.t)
  local ReturnToken = ResolveType(LibffiVariable, InnerType.t, true)
  local ParamTokens = {}
  for ParamIndex = 1, #InnerType do
    local Param = InnerType[ParamIndex]
    if (not Param.ellipsis) then
      local ParamToken = ResolveType(LibffiVariable, Param[1], false)
      append(ParamTokens, ParamToken)
    end
  end
  return ReturnToken, ParamTokens
end

local function EmitStructType (Lines, TagName, FieldLines, LibffiVariable)
  -- Header
  local NewLine = format("  %s = %s.newstructure(%q,", TagName, LibffiVariable, TagName)
  append(Lines, NewLine)
  -- Fields
  for FieldIndex = 1, #FieldLines do
    local Field = FieldLines[FieldIndex]
    local Trailing
    if (FieldIndex < #FieldLines) then
      Trailing = ","
    else
      Trailing = ""
    end
    local NewLine = format("    %s, %q%s", Field.Token, Field.Name, Trailing)
    append(Lines, NewLine)
  end
  -- Footer
  append(Lines, "  )")
end

local function EmitComInterface (Lines, TagName, FieldLines, LibffiVariable)
  -- Header
  local NewLine = format("  %s = {", TagName)
  append(Lines, NewLine)
  -- Fields
  for FieldIndex = 1, #FieldLines do
    local Field = FieldLines[FieldIndex]
    local ReturnToken, ParamTokens = ExtractMethodSignature(Field.FieldType, LibffiVariable)
    local Parts = { ReturnToken, format("%q", Field.Name) }
    for TokenIndex = 1, #ParamTokens do
      append(Parts, ParamTokens[TokenIndex])
    end
    local PartsString = concat(Parts, ", ")
    local NewLine     = format("    { %s },", PartsString)
    append(Lines, NewLine)
  end
  -- Footer
  append(Lines, "  }")
end

local function EmitStructTypeOrComInterface (Lines, StructName, StructAction, LibffiVariable)
  local StructNode = UnwrapBaseType(StructAction.type)
  local TagName    = GetStructureName(StructAction, StructName)
  -- Collect fields
  local FieldLines = {}
  for FieldIndex = 1, #StructNode do
    local Pair = StructNode[FieldIndex]
    if Pair.bitfield then
      print(format("WARNING: bitfield in struct '%s' not supported", StructName))
    else
      local FieldType = Pair[1]
      local FieldName = Pair[2]
      if FieldName then
        local FfiToken = ResolveFieldType(LibffiVariable, FieldType)
        local NewLine  = { Token = FfiToken, Name = FieldName, FieldType = FieldType }
        append(FieldLines, NewLine)
      end
    end
  end
  -- Emit structure or Win32 COM interface
  if HasWin32ComInterfaceAttribute(StructNode) then
    EmitComInterface(Lines, TagName, FieldLines, LibffiVariable)
  else
    EmitStructType(Lines, TagName, FieldLines, LibffiVariable)
  end
end

-- cparser function type looks like:
--
-- FunctionType = {
--   tag = "Function",
--   t   = {tag="Type", n="void"},                   -- return type
--   [1] = {[1]={tag="Type", n="int"}, name="a"},    -- param 1
--   [2] = {[1]={tag="Pointer", t={...}}, name="b"}, -- param 2
--   [3] = {ellipsis=true},                          -- Variadics "..."
--   inline       = false,
--   withoutProto = false,
-- }
--
-- The parameters are:
--   If array        -> normal parameter
--   If hashmap/dict -> parameter variadics "..."
--
-- But there is never more values to this table
--   {[1]={tag="Type", n="int"}, name="a"}
-- ONLY 1 VALUE
--
local function EmitFunction (Lines, Function, LibffiVariable)
  local FunctionType = Function.type
  local FunctionName = Function.name
  local ReturnToken  = ResolveType(LibffiVariable, FunctionType.t, true)
  local Parameters   = {}
  local IsVariadic   = false
  for Index = 1, #FunctionType do
    local ParameterEntry = FunctionType[Index]
    if ParameterEntry.ellipsis then
      IsVariadic = true
    else
      local ParameterType = ResolveType(LibffiVariable, ParameterEntry[1], false)
      append(Parameters, ParameterType)
    end
  end
  local Method
  if IsVariadic then
    Method = "variadicbind"
  else
    Method = "bind"
  end
  local ParametersString = concat(Parameters, ", ")
  local ParameterList
  if (#Parameters > 0) then
    ParameterList = format(", %s", ParametersString)
  else
    ParameterList = ""
  end
  local Line = format('  %s = Library:%s(%s, "%s"%s)', FunctionName, Method, ReturnToken, FunctionName, ParameterList)
  append(Lines, Line)
end

local function GenerateOutput (Constants, Structures, Functions, LibffiVariable, FunctionName)
  local Lines = {}
  -- CONSTANTS
  local ConstantNames = GetSortedKeys(Constants)
  if (#ConstantNames > 0) then
    append(Lines, "-- Constants")
    for ConstantIndex = 1, #ConstantNames do
      local Name  = ConstantNames[ConstantIndex]
      local Value = Constants[Name]
      EmitConstant(Lines, Name, Value)
    end
  end
  -- STRUCTURES
  if (#StructDeclarationOrder > 0) then
    append(Lines, "-- Structures")
    for StructureIndex = 1, #StructDeclarationOrder do
      -- StructName is actually coming from cparser and is a string like "struct XXX"
      local StructName   = StructDeclarationOrder[StructureIndex]
      local StructAction = Structures[StructName]
      local TagName      = GetStructureName(StructAction, StructName)
      local NewLine      = format("local %s", TagName)
      append(Lines, NewLine)
    end
  end
  -- FUNCTIONS
  if (#Functions > 0) then
    append(Lines, "-- Functions")
    local FunctionDict = {}
    for FunctionIndex = 1, #Functions do
      local Function     = Functions[FunctionIndex]
      local FunctionName = Function.name
      FunctionDict[FunctionName] = Function
    end
    local FunctionNames = GetSortedKeys(FunctionDict)
    for FunctionIndex = 1, #FunctionNames do
      local FunctionName = FunctionNames[FunctionIndex]
      local NewLine      = format("local %s", FunctionName)
      append(Lines, NewLine)
    end
  end
  -- Binding function
  append(Lines, "-- Binding function")
  local NewLine = format("local function %s (Library)", FunctionName)
  append(Lines, NewLine)
  -- STRUCTURES
  if (#StructDeclarationOrder > 0) then
    for StructureIndex = 1, #StructDeclarationOrder do
      local StructName   = StructDeclarationOrder[StructureIndex]
      local StructAction = Structures[StructName]
      EmitStructTypeOrComInterface(Lines, StructName, StructAction, LibffiVariable)
    end
  end
  -- FUNCTIONS
  if (#Functions > 0) then
    -- Convert list to dict
    local FunctionDict = {}
    for FunctionIndex = 1, #Functions do
      local Function     = Functions[FunctionIndex]
      local FunctionName = Function.name
      FunctionDict[FunctionName] = Function
    end
    -- Sort function names
    local FunctionNames = GetSortedKeys(FunctionDict)
    -- Output code
    for FunctionIndex = 1, #FunctionNames do
      local FunctionName = FunctionNames[FunctionIndex]
      local Function     = FunctionDict[FunctionName]
      EmitFunction(Lines, Function, LibffiVariable)
    end
  end
  append(Lines, "end")
  -- Return value
  return Lines
end

local function GenerateBindings (InputString, LibffiVariable, FunctionName)
  -- cparser can emit errors
  local Success, Functions, Constants, Structures = pcall(ParseHeader, InputString)
  local Result
  local ErrorString
  if Success then
    Result = GenerateOutput(Constants, Structures, Functions, LibffiVariable, FunctionName)
  else
    local CparserError = Functions -- pcall second value
    ErrorString = format("Syntax error %q in\n%s", CparserError, InputString)
  end
  return Result, ErrorString
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  GenerateBindings = GenerateBindings,
}

return PUBLIC_API
