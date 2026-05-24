--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- This file implement structure for ffi, essentially 2 things:
--
-- StructureType
--   Represent a structure type: fields, names, offsets, etc
--   STRUCTURE_TYPE_METATABLE
--
-- StructureInstance
--   Represent a structure instance allocated on the C side
--   With the methods to read and write fields
--   STRUCTURE_INSTANCE_METATABLE
--
-- Both StructureType and StructureInstance are complex Lua object
--
-- In the code below, FfiType refer to the type returned by libffi (lightuserdata)
--
-- Initially, we wanted to support function calls StructByValue. But for that we
-- essentially need to implement structure fields, offset, etc. So finally it's
-- also suitable for function calls StructByReference.
--
-- To make things simple, in both case we allocate memory on the C side.

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi     = require("com.raw.libffi")
local fficstring = require("com.ffi-cstring")

local format = string.format
local append = table.insert
local concat = table.concat
local pack   = string.pack
local unpack = string.unpack

local readmemory       = libffi.readmemory
local writememory      = libffi.writememory
local readpointer      = libffi.readpointer
local writepointer     = libffi.writepointer
local pointeroffset    = libffi.pointeroffset
local newstruct        = libffi.newstruct
local gettypesize      = libffi.gettypesize
local gettypealignment = libffi.gettypealignment
local getstructoffsets = libffi.getstructoffsets
local FFI_OK           = libffi.FFI_OK
local NULL             = libffi.NULL
local void             = libffi.void
local uint8            = libffi.uint8
local sint8            = libffi.sint8
local uint16           = libffi.uint16
local sint16           = libffi.sint16
local uint32           = libffi.uint32
local sint32           = libffi.sint32
local uint64           = libffi.uint64
local sint64           = libffi.sint64
local float            = libffi.float
local double           = libffi.double
local pointer          = libffi.pointer
local readstring       = libffi.readstring
local allocstring      = libffi.allocstring
local free             = libffi.free

-- The CString type constant (shared from ffi-cstring)
local cstring = fficstring.cstring

local POINTER_SIZE = gettypesize(pointer)

-- In this map, we will also register the sizes of StructureType created by
-- NewNamedStructure and NewAnonymousStructure
local FFI_TYPE_SIZE = {
  [uint8]   = 1,
  [sint8]   = 1,
  [uint16]  = 2,
  [sint16]  = 2,
  [uint32]  = 4,
  [sint32]  = 4,
  [uint64]  = 8,
  [sint64]  = 8,
  [float]   = 4,
  [double]  = 8,
  [pointer] = POINTER_SIZE,
  [cstring] = POINTER_SIZE,
}

local FFI_TYPE_PACK = {
  [uint8]  = "<I1",
  [sint8]  = "<i1",
  [uint16] = "<I2",
  [sint16] = "<i2",
  [uint32] = "<I4",
  [sint32] = "<i4",
  [uint64] = "<I8",
  [sint64] = "<i8",
  [float]  = "<f",
  [double] = "<d",
}

-- In this map, we will also register the names of StructureType created by
-- NewNamedStructure and NewAnonymousStructure
local FfiTypeNameMap = {
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
  [cstring] = "cstring",
}

-- Map FfiType to StructureType (created by NewNamedStructure or
-- NewAnonymousStructure) and also map StructureType to itself
--
-- So we can get StructureType from either:
--   a FfiType
--   a StructureType
local StructureTypeMap = {}

-- Map FfiType to FfiType and StructureType to FfiType
--
-- So that we can get a FfiType from either:
--   a FfiType
--   a StructureType
--
-- StructureType will be inserted by NewStructure
local FfiTypeMap = {
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
  [cstring] = pointer,
}

-- Used for auto-naming structures created by NewAnonymousStructure
local StructureCountBySignature = {}

-- Metatable for StructureType
local STRUCTURE_TYPE_METATABLE

-- Metatable for StructureInstance
local STRUCTURE_INSTANCE_METATABLE

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

-- Is it a StructureInstance
local function IsStructureInstance (Value)
  local IsObject = (getmetatable(Value) == STRUCTURE_INSTANCE_METATABLE)
  return IsObject
end

local function NewStructureInstance (Structure, BufferPointer, InstanceOffset, Parent)
  -- Create the Lua structure instance wrapper
  local NewStructureInstance = {
    StructType     = Structure,
    BufferPointer  = BufferPointer,
    InstanceOffset = InstanceOffset,
    Parent         = Parent,
    TrackedStrings = {},
  }
  -- Attach metatable
  setmetatable(NewStructureInstance, STRUCTURE_INSTANCE_METATABLE)
  -- Return value
  return NewStructureInstance
end

local function BuildStructureFields (FieldNames, FieldTypes, FieldFfiTypes, Offsets)
  -- local data
  local NewFields  = {}
  local NewNameMap = {}
  local FieldCount = #FieldTypes
  -- Iterate over the fields
  for FieldIndex = 1, FieldCount do
    local Name         = FieldNames[FieldIndex]
    local FieldFfiType = FieldFfiTypes[FieldIndex]
    local FieldSize    = FFI_TYPE_SIZE[FieldFfiType]
    assert(FieldSize, format("Unable to infer field size for %s", Name))
    -- Autoname the field
    if (Name == nil) then
      Name = format("Field%2.2d", FieldIndex)
    end
    -- Create the new field
    local NewField = {
      Index      = FieldIndex,
      Name       = Name,
      Type       = FieldTypes[FieldIndex],
      FfiType    = FieldFfiType,
      Size       = FieldSize,
      Offset     = Offsets[FieldIndex],
      PackFormat = FFI_TYPE_PACK[FieldFfiType],
    }
    -- Register new field
    NewFields[FieldIndex] = NewField
    NewNameMap[Name]      = NewField
  end
  -- Return value
  return NewFields, NewNameMap
end

local function CreateStructureType (StructureName, FfiType, FieldNames, FieldTypes, FieldFfiTypes, StructureSize, StructureAlignment, Offsets)
  -- Create fields
  local Fields, NameMap = BuildStructureFields(FieldNames, FieldTypes, FieldFfiTypes, Offsets)
  -- Create the Lua structure object
  local NewStructureType = {
    Name        = StructureName,
    FfiType     = FfiType,
    Size        = StructureSize,
    Alignment   = StructureAlignment,
    Fields      = Fields,
    FieldByName = NameMap,
  }
  -- Attach metatable
  setmetatable(NewStructureType, STRUCTURE_TYPE_METATABLE)
  -- Return value
  return NewStructureType
end

local function NewStructure (StructureName, FieldNames, FieldTypes)
  local FieldCount    = #FieldTypes
  local FieldFfiTypes = {}
  local NewStructureType
  local ErrorString
  -- Validate inputs
  assert((FieldCount > 0), "newstructure requires at least one field")
  -- Resolve types into FfiType
  for FieldIndex = 1, FieldCount do
    local FieldType    = FieldTypes[FieldIndex]
    local FfiFieldType = FfiTypeMap[FieldType]
    assert((FfiFieldType ~= nil),  format("Field %d: invalid ffi type",  FieldIndex))
    assert((FfiFieldType ~= void), format("Field %d: void is forbidden", FieldIndex))
    FieldFfiTypes[FieldIndex] = FfiFieldType
  end
  -- C API is taking elements on the Lua stack
  local StructureFfiType = newstruct(table.unpack(FieldFfiTypes))
  -- Calculate offsets
  local ReturnCode, Offsets = getstructoffsets(StructureFfiType)
  if (ReturnCode == FFI_OK) then
    -- get type size and alignment
    local SizeInBytes = gettypesize(StructureFfiType)
    local Alignment   = gettypealignment(StructureFfiType)
    -- Register type size
    FFI_TYPE_SIZE[StructureFfiType] = SizeInBytes
    -- Create the high level Lua object
    NewStructureType = CreateStructureType(StructureName, StructureFfiType, FieldNames, FieldTypes, FieldFfiTypes, SizeInBytes, Alignment, Offsets)
    -- Register elements to look-up tables
    StructureTypeMap[StructureFfiType] = NewStructureType
    StructureTypeMap[NewStructureType] = NewStructureType
    FfiTypeMap[NewStructureType]       = StructureFfiType
    FfiTypeNameMap[StructureFfiType]   = StructureName
    FfiTypeNameMap[NewStructureType]   = StructureName
  else
    ErrorString = format("getstructoffsets return %d instead of FFI_OK", ReturnCode)
  end
  -- Return value
  return NewStructureType, ErrorString
end

--------------------------------------------------------------------------------
-- TYPE OBJECT METHODS                                                        --
--------------------------------------------------------------------------------

local function STRUCTURE_GetTypeName (Structure)
  local TypeName = Structure.Name
  return TypeName
end

local function STRUCTURE_GetFfiType (Structure)
  local FfiType = Structure.FfiType
  return FfiType
end

local function STRUCTURE_GetAlignment (Structure)
  local Alignment = Structure.Alignment
  return Alignment
end

local function STRUCTURE_GetSizeInBytes (Structure)
  local SizeInBytes = Structure.Size
  return SizeInBytes
end

-- Rebuild the offset list from the fields
local function STRUCTURE_TypeGetOffsets (Structure)
  -- local data
  local Offsets    = {}
  local Fields     = Structure.Fields
  local FieldCount = #Fields
  -- Collect offsets
  for Index = 1, FieldCount do
    local Field       = Fields[Index]
    local FieldOffset = Field.Offset
    append(Offsets, FieldOffset)
  end
  -- Return value
  return Offsets
end

local function STRUCTURE_NewInstanceFromPointer (Structure, BufferPointer)
  assert((type(BufferPointer) == "userdata"), "expects pointer (lightuserdata)")
  local NewInstance = NewStructureInstance(Structure, BufferPointer, 0, nil)
  return NewInstance
end

STRUCTURE_TYPE_METATABLE = {
  -- METATABLE_UserDefinedMethods
  __index = {
    gettypename    = STRUCTURE_GetTypeName,
    getffitype     = STRUCTURE_GetFfiType,
    getalignment   = STRUCTURE_GetAlignment,
    getsizeinbytes = STRUCTURE_GetSizeInBytes,
    getoffsets     = STRUCTURE_TypeGetOffsets,
    cast           = STRUCTURE_NewInstanceFromPointer,
  }
}

--------------------------------------------------------------------------------
-- INSTANCE METHODS                                                           --
--------------------------------------------------------------------------------

local function STRUCTURE_INSTANCE_GetPointer (Instance)
  -- Retrieve data
  local BufferPointer  = Instance.BufferPointer
  local InstanceOffset = Instance.InstanceOffset
  -- Calculate new pointer
  local PointerValue = pointeroffset(BufferPointer, InstanceOffset)
  -- Return value
  return PointerValue
end

local function ResolvePointerValue (Value)
  local PointerValue
  if (Value == nil) then
    PointerValue = NULL
  elseif (type(Value) == "userdata") then
    PointerValue = Value
  elseif IsStructureInstance(Value) then
    PointerValue = Value:getpointer()
  else
    error(format("Invalid pointer value type: %s (%q)", type(Value), Value))
  end
  -- Return value
  return PointerValue
end

local function STRUCTURE_INSTANCE_Set (Instance, FieldIndex, FieldValue)
  -- Validate inputs
  local StructureType  = Instance.StructType
  local InstanceOffset = Instance.InstanceOffset
  local Fields         = StructureType.Fields
  local Field          = Fields[FieldIndex]
  assert(Field, format("Invalid field: %d", FieldIndex))
  -- Retrieve data
  local BufferPointer      = Instance.BufferPointer
  local FieldOffset        = (InstanceOffset + Field.Offset)
  local FieldFfiType       = Field.FfiType
  local FieldStructureType = StructureTypeMap[FieldFfiType]
  -- Write data into C side
  if FieldStructureType then
    -- Set StructureByValue
    local SourcePointer = FieldValue.BufferPointer
    local SourceOffset  = FieldValue.InstanceOffset
    local SizeInBytes   = FieldStructureType.Size
    local ValueBlob     = readmemory(SourcePointer, SourceOffset, SizeInBytes)
    assert(SizeInBytes == #ValueBlob, "Invalid structure size")
    writememory(BufferPointer, FieldOffset, ValueBlob)
  elseif (Field.Type == cstring) then
    -- Handle cstring field: accept Lua string or nil
    local TrackedStrings = Instance.TrackedStrings
    local OldPointer     = TrackedStrings[FieldIndex]
    -- Free previously tracked string
    if OldPointer then
      free(OldPointer)
      TrackedStrings[FieldIndex] = nil
    end
    if (FieldValue == nil) then
      writepointer(BufferPointer, FieldOffset, NULL)
    elseif (type(FieldValue) == "string") then
      local NewPointer = allocstring(FieldValue)
      writepointer(BufferPointer, FieldOffset, NewPointer)
      TrackedStrings[FieldIndex] = NewPointer
    else
      error(format("cstring field expects nil or string, got %s", type(FieldValue)))
    end
  elseif (FieldFfiType == pointer) then
    -- Overwrite the pointer on the C side
    local PointerValue = ResolvePointerValue(FieldValue)
    writepointer(BufferPointer, FieldOffset, PointerValue)
  else
    -- Pack the value in to a binary string and write it on the C side
    local FieldFormat = Field.PackFormat
    assert(FieldFormat, format("Field %s does not support write", Field.Name))
    local PackedValue = pack(FieldFormat, FieldValue)
    writememory(BufferPointer, FieldOffset, PackedValue)
  end
end

local function STRUCTURE_INSTANCE_SetField (Instance, Name, Value)
  -- Validate inputs
  local StructureType = Instance.StructType
  local FieldByName   = StructureType.FieldByName
  local Field         = FieldByName[Name]
  assert(Field, format("Unknown field: %q (%s)", Name, type(Name)))
  -- Set the field value
  local FieldIndex = Field.Index
  STRUCTURE_INSTANCE_Set(Instance, FieldIndex, Value)
end

local function STRUCTURE_INSTANCE_Get (Instance, Index)
  -- Validate inputs
  local StructureType  = Instance.StructType
  local InstanceOffset = Instance.InstanceOffset
  local Fields         = StructureType.Fields
  local Field          = Fields[Index]
  assert(Field, format("Invalid field: %d", Index))
  -- Retrieve data
  local BufferPointer      = Instance.BufferPointer
  local FieldOffset        = (InstanceOffset + Field.Offset)
  local FieldFfiType       = Field.FfiType
  local FieldStructureType = StructureTypeMap[FieldFfiType]
  local FieldValue
  -- Read data from C side
  if FieldStructureType then
    -- Get StructureByValue (aka nested structure)
    FieldValue = NewStructureInstance(FieldStructureType, BufferPointer, FieldOffset, (Instance.Parent or Instance))
  elseif (Field.Type == cstring) then
    -- Read cstring: read pointer then convert to Lua string
    local StringPointer = readpointer(BufferPointer, FieldOffset)
    if (StringPointer ~= NULL) then
      FieldValue = readstring(StringPointer)
    end
  elseif (FieldFfiType == pointer) then
    -- Read the pointer value
    FieldValue = readpointer(BufferPointer, FieldOffset)
  else
    -- Read as binary string and unpack
    local FieldSize   = Field.Size
    local FieldFormat = Field.PackFormat
    local FieldBlob   = readmemory(BufferPointer, FieldOffset, FieldSize)
    FieldValue = unpack(FieldFormat, FieldBlob, 1)
  end
  -- Return value
  return FieldValue
end

local function STRUCTURE_INSTANCE_GetField (Instance, Name)
  -- Validate inputs
  local StructureType = Instance.StructType
  local FieldByName   = StructureType.FieldByName
  local Field         = FieldByName[Name]
  assert(Field, format("Unknown field: %q (%s)", Name, type(Name)))
  -- Read the field value
  local FieldIndex = Field.Index
  local FieldValue = STRUCTURE_INSTANCE_Get(Instance, FieldIndex)
  -- Return value
  return FieldValue
end

local function STRUCTURE_INSTANCE_FreeTrackedStrings (Instance)
  local TrackedStrings = Instance.TrackedStrings
  for FieldIndex, PointerValue in pairs(TrackedStrings) do
    free(PointerValue)
  end
end

STRUCTURE_INSTANCE_METATABLE = {
  -- METATABLE_LuaDefinedMethods
  __gc = STRUCTURE_INSTANCE_FreeTrackedStrings,
  -- METATABLE_UserDefinedMethods
  __index = {
    getpointer = STRUCTURE_INSTANCE_GetPointer,
    set        = STRUCTURE_INSTANCE_Set,
    get        = STRUCTURE_INSTANCE_Get,
    setfield   = STRUCTURE_INSTANCE_SetField,
    getfield   = STRUCTURE_INSTANCE_GetField,
  }
}

--------------------------------------------------------------------------------
-- MAIN FUNCTIONS: CREATE STRUCTURES                                          --
--------------------------------------------------------------------------------

-- Create a named structure
-- Example: NewNamedStructure("MyStruct", uint32, "First", float, "Second")
local function NewNamedStructure (...)
  -- Validate inputs
  local ArgumentCount = select("#", ...)
  assert((ArgumentCount >= 3), "expects struct name followed by at least one field pair")
  -- local data
  local StructureName = select(1, ...)
  local FieldNames    = {}
  local FieldTypes    = {}
  assert((type(StructureName) == "string"), "expects struct name as first argument")
  assert((((ArgumentCount - 1) % 2) == 0),  "expects field name/type pairs after the struct name")
  -- Collect fields
  for Index = 2, ArgumentCount, 2 do
    local TypeIndex = (Index + 0)
    local NameIndex = (Index + 1)
    local FieldType = select(TypeIndex, ...)
    local FieldName = select(NameIndex, ...)
    assert((type(FieldName) == "string"), format("Argument %d should be field name", NameIndex))
    append(FieldNames, FieldName)
    append(FieldTypes, FieldType)
  end
  -- Create the new structure
  local NewStructureType, ErrorString = NewStructure(StructureName, FieldNames, FieldTypes)
  -- Return value
  return NewStructureType, ErrorString
end

-- Return a string like "uint32-uint32"
local function BuildStructureSignatureString (FieldTypes)
  -- local data
  local SignatureParts = {}
  local FieldCount     = #FieldTypes
  -- Collect type names 
  for Index = 1, FieldCount do
    local FieldType = FieldTypes[Index]
    local FieldName = FfiTypeNameMap[FieldType]
    assert(FieldName, format("Unexpected field type: %s", tostring(FieldType)))
    append(SignatureParts, FieldName)
  end
  -- Format type name
  local StructureTypeName = concat(SignatureParts, "-")
  return StructureTypeName
end

-- Return: struct-uint32-uint32-0001, struct-uint32-uint32-0002, etc
local function CreateStructureName (FieldTypes)
  -- Build a signature string
  local SignatureString = BuildStructureSignatureString(FieldTypes)
  -- How many of Structure with the same signature exists?
  local Count = StructureCountBySignature[SignatureString]
  local StructureTypeId
  if Count then
    StructureTypeId = (Count + 1)
  else
    StructureTypeId = 1
  end
  local AutoName = format("struct-%s-%4.4d",  SignatureString, StructureTypeId)
  -- Update signature count
  StructureCountBySignature[SignatureString] = StructureTypeId
  -- Return value
  return AutoName
end

-- Create structure from anonymous fields
-- Example: NewStructType(uint32, float)
local function NewAnonymousStructure (...)
  -- local data
  local FieldCount = select("#", ...)
  local FieldTypes = {}
  local FieldNames = {}
  -- Collect fields from the stack
  for Index = 1, FieldCount do
    -- Type can be either a FfiType or LuaStructureObject
    local Type = select(Index, ...)
    FieldTypes[Index] = Type
    FieldNames[Index] = format("Field-%d", Index)
  end
  -- Infer a structure name from structure fields
  local StructureName = CreateStructureName(FieldTypes)
  -- Create the new structure type
  local NewStructureType, ErrorString = NewStructure(StructureName, FieldNames, FieldTypes)
  -- return values
  return NewStructureType, ErrorString
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  newnamedstruct     = NewNamedStructure,
  newanonymousstruct = NewAnonymousStructure,
}

return PUBLIC_API
