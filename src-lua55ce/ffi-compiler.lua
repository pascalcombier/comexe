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
--   Sqlite3:load("sqlite3-ffi")
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

local contains    = Runtime.contains
local readfile    = Runtime.readfile
local writefile   = Runtime.writefile
local newpathname = Runtime.newpathname
local getparam    = Runtime.getparam

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

--------------------------------------------------------------------------------
-- STRING STREAM                                                              --
--------------------------------------------------------------------------------

local function NewStringStream ()
  -- Local data
  local Lines = {}
  -- Methods
  local function Write (Stream, Text)
    append(Lines, Text)
  end
  local function GetOutput (Stream)
    local OutputString = concat(Lines, "\n")
    return OutputString
  end
  -- Create a new object
  local NewStringStreamObject = {
    write     = Write,
    getoutput = GetOutput,
  }
  -- Return value
  return NewStringStreamObject
end

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
      Done   = true
      Result = nil
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
  ["void"]                   = "libffi.void",
  ["_Bool"]                  = "libffi.sint8",
  ["char"]                   = "libffi.sint8",
  ["signed char"]            = "libffi.sint8",
  ["unsigned char"]          = "libffi.uint8",
  ["short"]                  = "libffi.sint16",
  ["short int"]              = "libffi.sint16",
  ["unsigned short"]         = "libffi.uint16",
  ["unsigned short int"]     = "libffi.uint16",
  ["int"]                    = "libffi.sint32",
  ["signed"]                 = "libffi.sint32",
  ["signed int"]             = "libffi.sint32",
  ["unsigned"]               = "libffi.uint32",
  ["unsigned int"]           = "libffi.uint32",
  ["long long"]              = "libffi.sint64",
  ["long long int"]          = "libffi.sint64",
  ["unsigned long long"]     = "libffi.uint64",
  ["unsigned long long int"] = "libffi.uint64",
  ["float"]                  = "libffi.float",
  ["double"]                 = "libffi.double",
  ["long double"]            = "libffi.double",
  ["size_t"]                 = "libffi.uint64",
  -- standard types from C headers
  ["intptr_t"]               = "libffi.sint64",
  ["uintptr_t"]              = "libffi.uint64",
  ["ptrdiff_t"]              = "libffi.sint64",
  ["int8_t"]                 = "libffi.sint8",
  ["uint8_t"]                = "libffi.uint8",
  ["int16_t"]                = "libffi.sint16",
  ["uint16_t"]               = "libffi.uint16",
  ["int32_t"]                = "libffi.sint32",
  ["uint32_t"]               = "libffi.uint32",
  ["int64_t"]                = "libffi.sint64",
  ["uint64_t"]               = "libffi.uint64",
}

if (getparam("OS") == "windows") then
  PrimitiveFfiToken["long"]              = "libffi.sint32"
  PrimitiveFfiToken["long int"]          = "libffi.sint32"
  PrimitiveFfiToken["unsigned long"]     = "libffi.uint32"
  PrimitiveFfiToken["unsigned long int"] = "libffi.uint32"
else
  PrimitiveFfiToken["long"]              = "libffi.sint64"
  PrimitiveFfiToken["long int"]          = "libffi.sint64"
  PrimitiveFfiToken["unsigned long"]     = "libffi.uint64"
  PrimitiveFfiToken["unsigned long int"] = "libffi.uint64"
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

local function ResolveType (AstType, IsReturnType)
  local Current = UnwrapBaseType(AstType)
  local Result
  if (Current == nil) then
    Result = "libffi.void"
  elseif (Current.tag == "Type") then
    local FfiTypeString = PrimitiveFfiToken[Current.n]
    if FfiTypeString then
      Result = FfiTypeString
    else
      Result = "libffi.pointer"
    end
  elseif (Current.tag == "Pointer") then
    -- Only IsReturnType has automatic cstring conversions
    if IsReturnType then
      local BaseType = UnwrapBaseType(Current.t)
      if BaseType and (BaseType.tag == "Type") and (BaseType.n == "char") then
        Result = "libffi.cstring"
      else
        Result = "libffi.pointer"
      end
    else
      Result = "libffi.pointer"
    end
  elseif (Current.tag == "Array") then
    Result = "libffi.pointer"
  elseif (Current.tag == "Function") then
    Result = "libffi.pointer"
  elseif (Current.tag == "Enum") then
    Result = "libffi.sint32"
  else
    Result = "libffi.pointer"
  end
  return Result
end

--------------------------------------------------------------------------------
-- STRUCT FIELD TYPE RESOLUTION                                               --
--------------------------------------------------------------------------------

local function ResolveFieldType (AstType)
  local Current = UnwrapBaseType(AstType)
  local Result
  if (Current == nil) then
    Result = "libffi.void"
  elseif (Current.tag == "Type") then
    local FfiTypeString = PrimitiveFfiToken[Current.n]
    if FfiTypeString then
      Result = FfiTypeString
    elseif KnownStructTypes[Current.n] then
      Result = format("Library.%s", Current.n)
    else
      Result = "libffi.pointer"
    end
  elseif (Current.tag == "Pointer") then
    local BaseType = UnwrapBaseType(Current.t)
    if BaseType and (BaseType.tag == "Type") and (BaseType.n == "char") then
      Result = "libffi.cstring"
    else
      Result = "libffi.pointer"
    end
  elseif (Current.tag == "Array") then
    Result = "libffi.pointer"
  elseif (Current.tag == "Function") then
    Result = "libffi.pointer"
  elseif (Current.tag == "Enum") then
    Result = "libffi.sint32"
  else
    Result = "libffi.pointer"
  end
  return Result
end

--------------------------------------------------------------------------------
-- CPARSER INTEGRATION                                                        --
--------------------------------------------------------------------------------

local function ParseHeader (Content, InputFilename)
  -- Init structures order
  KnownStructTypes       = {}
  StructDeclarationOrder = {}
  -- Parse
  local Functions    = {}
  local Constants    = {}
  local Structures   = {}
  local LineIterator = NewLineIterator(Content)
  local Iterator     = CParser.declarationIterator(CParserOptions, LineIterator, InputFilename)
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

local function EmitConstant (Stream, Name, Value)
  local ValueType = type(Value)
  local Line
  if (ValueType == "table") then
    if (Value.tag == "string") then
      Line = format("  Library.%s = %q", Name, Value.value)
    else
      Line = format("  Library.%s = %s", Name, tostring(Value.value))
    end
  elseif (ValueType == "number") then
    if (numbertype(Value) == "integer") then
      Line = format("  Library.%s = %d", Name, Value)
    else
      Line = format("  Library.%s = %s", Name, tostring(Value))
    end
  end
  if Line then
    Stream:write(Line)
  else
    print(format("Warning: Skipping constant '%s' with unsupported value type '%s'", Name, ValueType))
  end
end

--------------------------------------------------------------------------------
-- STRUCT TYPE                                                                --
--------------------------------------------------------------------------------

local function EmitStructType (Stream, StructName, StructAction)
  -- StructNode: {tag="Struct", n="Point", ...}
  local StructNode = UnwrapBaseType(StructAction.type)
  local TagName    = StructNode.n
  if (TagName == nil) then
    TagName = StructName
  end
  -- Write structure
  Stream:write(format("  Library.%s = libffi.newstructure(%q,", TagName, TagName))
  local FieldLines = {}
  -- Collect struct fields ("libffi.sint32, "fieldname")
  for FieldIndex = 1, #StructNode do
    local Pair = StructNode[FieldIndex]
    if Pair.bitfield then
      print(format("WARNING: bitfield in struct '%s' not supported", StructName))
    else
      local FieldType = Pair[1]
      local FieldName = Pair[2]
      if FieldName then
        local FfiToken = ResolveFieldType(FieldType)
        local NewLine  = format("    %s, %q", FfiToken, FieldName)
        append(FieldLines, NewLine)
      end
    end
  end
  -- Emit field lines joined with commas
  local FieldBlock = concat(FieldLines, ",\n")
  Stream:write(FieldBlock)
  Stream:write("  )")
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
local function EmitFunction (Stream, Function)
  local FunctionType = Function.type
  local FunctionName = Function.name
  local ReturnToken  = ResolveType(FunctionType.t, true)
  local Parameters   = {}
  local IsVariadic   = false
  for Index = 1, #FunctionType do
    local ParameterEntry = FunctionType[Index]
    if ParameterEntry.ellipsis then
      IsVariadic = true
    else
      local ParameterType = ResolveType(ParameterEntry[1], false)
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
  local Line = format('  Library.%s = Library:%s(%s, "%s"%s)', FunctionName, Method, ReturnToken, FunctionName, ParameterList)
  Stream:write(Line)
end

local function GenerateOutput (Constants, Structures, Functions, InputPath)
  local Stream = NewStringStream()
  local InputPathname = newpathname(InputPath)
  local InputFilename = InputPathname:getname()
  local Timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
  Stream:write("--------------------------------------------------------------------------------")
  Stream:write(format("-- %-74s --", format("Generated by ComEXE ffi-compiler at %s", Timestamp)))
  Stream:write(format("-- %-74s --", InputFilename))
  Stream:write("--------------------------------------------------------------------------------")
  Stream:write("")
  Stream:write("local libffi = require(\"com.ffi\")")
  Stream:write("")
  -- FUNCTIONS block
  Stream:write("--------------------------------------------------------------------------------")
  Stream:write("-- FUNCTIONS                                                                  --")
  Stream:write("--------------------------------------------------------------------------------")
  Stream:write("")
  Stream:write("local function Bind (Library)")
  -- CONSTANTS
  local ConstantNames = GetSortedKeys(Constants)
  if (#ConstantNames > 0) then
    Stream:write("  -- Constants")
    for ConstantIndex = 1, #ConstantNames do
      local Name  = ConstantNames[ConstantIndex]
      local Value = Constants[Name]
      EmitConstant(Stream, Name, Value)
    end
  end
  -- STRUCTURES
  local StructureNames = StructDeclarationOrder
  if (#StructureNames > 0) then
    Stream:write("  -- Structures")
    for StructureIndex = 1, #StructureNames do
      local StructName   = StructureNames[StructureIndex]
      local StructAction = Structures[StructName]
      EmitStructType(Stream, StructName, StructAction)
    end
  end
  -- FUNCTIONS
  if (#Functions > 0) then
    Stream:write("  -- Functions")
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
      EmitFunction(Stream, Function)
    end
  end
  Stream:write("end")
  Stream:write("")
  -- PUBLIC API block
  Stream:write("--------------------------------------------------------------------------------")
  Stream:write("-- PUBLIC API                                                                 --")
  Stream:write("--------------------------------------------------------------------------------")
  Stream:write("")
  Stream:write("local PUBLIC_API = {")
  Stream:write("  bind = Bind,")
  Stream:write("}")
  Stream:write("")
  Stream:write("return PUBLIC_API")
  -- Format the whole thing and return
  local Result = Stream.getoutput()
  return Result
end

local function EvaluateOutputFilename (InputFilename)
  -- local data
  local Pathname = newpathname(InputFilename)
  -- Explode the pathname
  local FileName, ModuleName, Extension = Pathname:getname()
  local Separator
  if contains(ModuleName, "_") then
    Separator = "_"
  else
    Separator = "-"
  end
  -- Drop the file name
  Pathname = Pathname:parent()
  -- New filename
  local OutputName  = format("%s%sffi.lua", ModuleName, Separator)
  local NewPathname = Pathname:child(OutputName)
  local NewFilename = tostring(NewPathname)
  -- Return value
  return NewFilename
end

local function Compile (InputFilename)
  -- Read input
  local FileContent, ReadErrorString = readfile(InputFilename)
  if ReadErrorString then
    error(ReadErrorString)
  end
  -- Parse with cparser and generate output
  local Functions, Constants, Structures = ParseHeader(FileContent, InputFilename)
  -- Generate output
  local OutputString = GenerateOutput(Constants, Structures, Functions, InputFilename)
  -- Write file
  local OutputFilename = EvaluateOutputFilename(InputFilename)
  local Success, WriteErrorString = writefile(OutputFilename, OutputString)
  if WriteErrorString then
    error(WriteErrorString)
  end
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  Compile = Compile,
}

return PUBLIC_API
