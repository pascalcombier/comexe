--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Library "com.win32" is a high-level library on the top of "com.raw.win32"
--
-- Error management
-- Registry
-- ShellExecute
-- UTF8/16 conversions
--
-- REG_BINARY
-- REG_DWORD
-- REG_DWORD_LITTLE_ENDIAN
-- REG_DWORD_BIG_ENDIAN
-- REG_EXPAND_SZ
-- REG_LINK
-- REG_MULTI_SZ
-- REG_NONE
-- REG_QWORD
-- REG_QWORD_LITTLE_ENDIAN
-- REG_SZ
--

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local win32   = require("com.raw.win32")
local Runtime = require("com.runtime")
local ffi     = require("com.ffi")

local format = string.format
local pack   = string.pack
local unpack = string.unpack
local concat = table.concat
local byte   = string.byte

local append              = Runtime.append
local NewBuffer           = Runtime.newbuffer
local hasprefix           = Runtime.hasprefix
local getlasterror        = win32.getlasterror
local formatmessageA      = win32.formatmessageA
local widechartomultibyte = win32.widechartomultibyte
local multibytetowidechar = win32.multibytetowidechar
local expandenv           = win32.expandenvironmentstrings
local shellexecute        = win32.shellexecute

local regcreatekeyex  = win32.regcreatekeyex
local regopenkeyex    = win32.regopenkeyex
local regsetvalueex   = win32.regsetvalueex
local regenumvalue    = win32.regenumvalue
local regenumkeyex    = win32.regenumkeyex
local regclosekey     = win32.regclosekey
local regqueryvalueex = win32.regqueryvalueex
local regqueryinfokey = win32.regqueryinfokey
local regdeletekey    = win32.regdeletekey
local regdeletevalue  = win32.regdeletevalue
local regflushkey     = win32.regflushkey

local NULL = ffi.NULL

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

-- A single buffer for everything, set to 4 KiB for FormatMessage
local BUFFER_SIZE = 4096
local Buffer      = NewBuffer(BUFFER_SIZE)

-- Note that there is no such thing as a "REG_DWORD_BIG_ENDIAN" constant
local WIN32_REG_TYPE_VALUES = {
  REG_NONE                       = 0,
  REG_SZ                         = 1,
  REG_EXPAND_SZ                  = 2,
  REG_BINARY                     = 3,
  REG_DWORD                      = 4,
  REG_DWORD_LITTLE_ENDIAN        = 4,
  REG_DWORD_BIG_ENDIAN           = 5,
  REG_LINK                       = 6,
  REG_MULTI_SZ                   = 7,
  REG_RESOURCE_LIST              = 8,
  REG_FULL_RESOURCE_DESCRIPTOR   = 9,
  REG_RESOURCE_REQUIREMENTS_LIST = 10,
  REG_QWORD                      = 11,
  REG_QWORD_LITTLE_ENDIAN        = 11,
}

local WIN32_REG_TYPE_NAMES = {}
for ConstantName, ConstantValue in pairs(WIN32_REG_TYPE_VALUES) do
  WIN32_REG_TYPE_NAMES[ConstantValue] = ConstantName
end

-- Fix dictionnary: remove duplicated values
WIN32_REG_TYPE_NAMES[4]  = "REG_DWORD"
WIN32_REG_TYPE_NAMES[11] = "REG_QWORD"

-- WIN32 CONSTANTS
local ERROR_SUCCESS                 = 0
local CP_UTF8                       = 65001
local FORMAT_MESSAGE_FROM_SYSTEM    = 0x1000
local FORMAT_MESSAGE_IGNORE_INSERTS = 0x200
local FORMAT_MESSAGE_MAX_WIDTH_MASK = 0x000000FF
local WC_ERR_INVALID_CHARS          = 0x00000080
local MB_ERR_INVALID_CHARS          = 0x00000008

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local function WIN32_FormatMessage (ErrorCode)
  -- local data
  local Result
  -- We don't call Buffer:ensurecapacity(BUFFER_SIZE) because we use a static 4
  -- KiB static buffer.
  local Flags = (FORMAT_MESSAGE_MAX_WIDTH_MASK | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS)
  -- Retrieve the actual C pointer
  local BufferPointer = Buffer:getpointer(0)
  -- formatmessageA return the number of characters written, excluding the
  -- NULL. There is not clear way to remove newline characters.
  local CharWritten = formatmessageA(Flags, NULL, ErrorCode, 0, BufferPointer, BUFFER_SIZE, NULL)
  -- Error handling
  if (CharWritten >= 1) then
    local AnsiString = Buffer:read(1, CharWritten)
    -- Trim the string from FormatMessageA to avoid ending newline
    local CleanAnsiString = AnsiString:gsub("[ \t\r\n]+$", "")
    Result = CleanAnsiString
  else
    Result = format("Error %d", ErrorCode)
  end
  -- Return value
  return Result
end

--------------------------------------------------------------------------------
-- FUNCTIONS FOR UTF CONVERSIONS                                              --
--------------------------------------------------------------------------------

-- We have here 2 functions serving the same purpose as luv.wtf8_to_utf16 and
-- utf16_to_wtf8
--
-- The key difference is that WIN32_utf8toutf16 provide a Lua string which
-- embeds 2 0x00 bytes at the end, making it suitable for Win32 use. The second
-- difference is that it does not internally use malloc/free, the buffer is
-- static and shared with other functions.
--
-- Note that the 2 functions are not symetric. The UTF-16 version will return a
-- string suitable for Win32 like "XXXX\x00\x00", correctly terminated (actually
-- more than correctly terminated, because in reality Lua will add its own 0x00,
-- so actually the string will be triple-terminated, but this is a detail).
--
-- The UTF-8 string, will simply rely on Lua mecanism which automatically create
-- null-terminated strings, it will be like "Hello", and not like "Hello\x00".
--
-- MultiByteToWideChar doc:
--
-- If this parameter is -1, the function processes the entire input string,
-- including the terminating null character. Therefore, the resulting Unicode
-- string has a terminating null character, and the length returned by the
-- function includes this character.
--
local function WIN32_utf8toutf16 (StringUtf8)
  -- Local data
  local StringUtf16
  local ErrorString
  -- We need this special case because when calling multibytetowidechar with an
  -- empty string, it return 0 with GetLastError Invalid param.
  if (StringUtf8 == "") then
    StringUtf16 = "\x00\x00"
  else
    -- Call MultiByteToWideChar a first time to determine the required buffer size
    local RequiredChars = multibytetowidechar(CP_UTF8, MB_ERR_INVALID_CHARS, StringUtf8, -1, NULL, 0)
    if (RequiredChars == 0) then
      local ErrorCode = getlasterror()
      if (ErrorCode == 0) then
        StringUtf16 = "\x00\x00" -- At this stage it shoud not happen
      else
        ErrorString = WIN32_FormatMessage(ErrorCode)
      end
    else
      -- Resize buffer if necessary and get data pointer
      local RequiredBytes = (RequiredChars * 2)
      Buffer:ensurecapacity(RequiredBytes)
      local DataPointer = Buffer:getpointer(0)
      -- Second call to perform the conversion, pass
      local WrittenChars = multibytetowidechar(CP_UTF8, MB_ERR_INVALID_CHARS, StringUtf8, -1, DataPointer, RequiredChars)
      if (WrittenChars == 0) then
        local ErrorCode = getlasterror()
        if (ErrorCode == 0) then
          ErrorString = "Unknown error" -- Should not happen
        else
          ErrorString = WIN32_FormatMessage(ErrorCode)
        end
      else
        -- Convert into a Lua string, including 2 additional 0x00 (thanks to -1 in multibytetowidechar)
        StringUtf16 = Buffer:read(1, (WrittenChars * 2))
      end
    end
  end
  -- Return values
  return StringUtf16, ErrorString
end

-- That function is to use in WIN32_utf16to8. The key point is that in ComEXE,
-- UTF-16 string ending with L"test\x00\x00" which is incompatible with luv
-- strings which are not double-NULL terminated.
--
-- But in our implementation, to avoid complexity, we better make WIN32_utf16to8
-- support 2 kind of inputs: luv UTF-16 strings and our ComEXE strings.
--
-- That function will determine those cases.
--
local function WIN32_HasEndingUtf16 (Utf16String)
  -- local data
  local Result
  local Length = #Utf16String
  -- Check end of string
  if (Length >= 2) then
    local LastByteIndex1 = (Length - 1)
    local LastByteIndex2 = Length
    local LastByte1, LastByte2 = byte(Utf16String, LastByteIndex1, LastByteIndex2)
    Result = ((LastByte1 == 0x00) and (LastByte2 == 0x00))
  else
    Result = false
  end
  -- Return value
  return Result
end

local function WIN32_utf16to8 (StringUtf16)
  -- Local data
  local SizeInBytes = #StringUtf16
  local CharCount
  local Result
  local ErrorString
  -- This block makes WIN32_utf16to8 compatible with UTF-16 strings created from luv (not double 0x00 terminated)
  if WIN32_HasEndingUtf16(StringUtf16) then
    CharCount = ((SizeInBytes // 2) - 1)
  else
    CharCount = (SizeInBytes // 2)
  end
  -- Handle special case
  if (CharCount == 0) then
    Result = ""
  else
    -- First call with NULL buffer to collect required byte count using the adjusted char count
    local RequiredBytes = widechartomultibyte(CP_UTF8, WC_ERR_INVALID_CHARS, StringUtf16, CharCount, NULL, 0, NULL, false)
    if (RequiredBytes == 0) then
      local ErrorCode = getlasterror()
      if (ErrorCode == 0) then
        Result = "" -- Should not happen
      else
        ErrorString = WIN32_FormatMessage(ErrorCode)
      end
    else
      -- Resize buffer if necessary and get data pointer
      local TotalByteCount = (RequiredBytes + 1)
      Buffer:ensurecapacity(TotalByteCount)
      local DataPointer = Buffer:getpointer(0)
      -- Second call to perform the conversion using the same adjusted count
      local Written = widechartomultibyte(CP_UTF8, WC_ERR_INVALID_CHARS, StringUtf16, CharCount, DataPointer, TotalByteCount, NULL, false)
      if (Written == 0) then
        local ErrorCode = getlasterror()
        if (ErrorCode == 0) then
          Result = "" -- Should not happen
        else
          ErrorString = WIN32_FormatMessage(ErrorCode)
        end
      else
        -- Convert into a Lua string without additional 0x00
        Result = Buffer:read(1, Written)
      end
    end
  end
  -- Single return at end of function
  return Result, ErrorString
end

--------------------------------------------------------------------------------
-- REGISTRY                                                                   --
--------------------------------------------------------------------------------

local UTF8  = WIN32_utf16to8
local UTF16 = WIN32_utf8toutf16

-- Root keys are not exported in WIN32_Constants, only used internally
local REG_ROOT_KEYS = {
  { "HKEY_CLASSES_ROOT",                0x80000000 },
  { "HKEY_CURRENT_USER",                0x80000001 },
  { "HKEY_LOCAL_MACHINE",               0x80000002 },
  { "HKEY_USERS",                       0x80000003 },
  { "HKEY_PERFORMANCE_DATA",            0x80000004 },
  { "HKEY_PERFORMANCE_TEXT",            0x80000050 },
  { "HKEY_PERFORMANCE_NLSTEXT",         0x80000060 },
  { "HKEY_CURRENT_CONFIG",              0x80000005 },
  { "HKEY_DYN_DATA",                    0x80000006 },
  { "HKEY_CURRENT_USER_LOCAL_SETTINGS", 0x80000007 },
}

-- Registry value types
local REG_NONE                = WIN32_REG_TYPE_VALUES["REG_NONE"]
local REG_SZ                  = WIN32_REG_TYPE_VALUES["REG_SZ"]
local REG_EXPAND_SZ           = WIN32_REG_TYPE_VALUES["REG_EXPAND_SZ"]
local REG_MULTI_SZ            = WIN32_REG_TYPE_VALUES["REG_MULTI_SZ"]
local REG_BINARY              = WIN32_REG_TYPE_VALUES["REG_BINARY"]
local REG_DWORD               = WIN32_REG_TYPE_VALUES["REG_DWORD"]
local REG_DWORD_LITTLE_ENDIAN = WIN32_REG_TYPE_VALUES["REG_DWORD_LITTLE_ENDIAN"]
local REG_DWORD_BIG_ENDIAN    = WIN32_REG_TYPE_VALUES["REG_DWORD_BIG_ENDIAN"]
local REG_QWORD               = WIN32_REG_TYPE_VALUES["REG_QWORD"]
local REG_QWORD_LITTLE_ENDIAN = WIN32_REG_TYPE_VALUES["REG_QWORD_LITTLE_ENDIAN"]

-- Convert a C pointer to a buffer into a Lua array of UTF-8 strings
local function REG_ParseMultiString (Utf16String)
  -- Convert whole buffer to UTF-8 first
  local AllUtf8 = UTF8(Utf16String)
  local Parts   = {}
  -- Split in parts
  for Part in AllUtf8:gmatch("[^\x00]+") do
    append(Parts, Part)
  end
  -- Return value
  return Parts
end

-- This API is a little unusual. There are 2 ways to get a value from a Key.
--
-- In the Win32 logic, the function RegQueryValueEx will retrieve a value
-- associated to the given name. Win32 idiom is to call a first time with NULL
-- to retrieve the data size, then allocate a buffer and then call a second
-- time.
--
-- A second important function is value iteration RegEnumValueW, taking a value
-- name and data buffer. The previous idiom does not work exactly the same here,
-- because the name string buffer is mandatory. So we basically need to set the
-- max buffer size (32767 bytes). And then do the same work as RegQueryValueEx.
--
-- So to avoid that, we leverage the existing work done in KEY_MethodGet.
--
local function REG_ConvertRawValue (RawValue, RegTypeInteger)
  -- Local data
  local ConvertedValue
  -- Convert according to the type
  if (RegTypeInteger == REG_SZ) or (RegTypeInteger == REG_EXPAND_SZ) then
    ConvertedValue = UTF8(RawValue)
  elseif (RegTypeInteger == REG_BINARY) then
    ConvertedValue = RawValue
  elseif (RegTypeInteger == REG_MULTI_SZ) then
    ConvertedValue = REG_ParseMultiString(RawValue)
  elseif (RegTypeInteger == REG_DWORD) then
    ConvertedValue = select(1, unpack("=I4", RawValue))
  elseif (RegTypeInteger == REG_DWORD_LITTLE_ENDIAN) then
    ConvertedValue = select(1, unpack("<I4", RawValue))
  elseif (RegTypeInteger == REG_DWORD_BIG_ENDIAN) then
    ConvertedValue = select(1, unpack(">I4", RawValue))
  elseif (RegTypeInteger == REG_QWORD) then
    ConvertedValue = select(1, unpack("=I8", RawValue))
  elseif (RegTypeInteger == REG_QWORD_LITTLE_ENDIAN) then
    ConvertedValue = select(1, unpack("<I8", RawValue))
  end
  -- Unknown format or REG_NONE will return nil
  return ConvertedValue
end

local function KEY_MethodGetImpl (KeyObject, ValueNameUtf16)
  -- local data
  local ResultValue
  local ResultType
  local ResultErrorMessage
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  -- Get the value type and size
  local Status, Type, SizeInBytes = regqueryvalueex(RawKey, ValueNameUtf16, NULL, 0)
  if (Status == ERROR_SUCCESS) then
    if (SizeInBytes == 0) then
      ResultType = (WIN32_REG_TYPE_NAMES[Type] or "UnknownType")
    else
      -- Retrieve data
      Buffer:ensurecapacity(SizeInBytes)
      local DataPointer = Buffer:getpointer(0)
      Status, Type, SizeInBytes = regqueryvalueex(RawKey, ValueNameUtf16, DataPointer, SizeInBytes)
      -- Convert the data
      if (Status == ERROR_SUCCESS) then
        -- Convert
        local RawData        = Buffer:read(1, SizeInBytes)
        local ConvertedValue = REG_ConvertRawValue(RawData, Type)
        -- Set results
        ResultValue = ConvertedValue
        ResultType  = (WIN32_REG_TYPE_NAMES[Type] or "UnknownType")
      else
        -- Second call to regqueryvalueex failed, the return value is directly
        -- usable by WIN32_ErrorMessage without GetLastError
        ResultErrorMessage = WIN32_FormatMessage(Status)
      end
    end
  else
    -- First call to regqueryvalueex failed, the return value is directly
    -- usable by WIN32_ErrorMessage without GetLastError
    ResultErrorMessage = WIN32_FormatMessage(Status)
  end
  -- Return value
  return ResultValue, ResultType, ResultErrorMessage
end

local function REG_FormatMultiString (StringArray)
  -- Local data
  local Result = {}
  -- Collect and convert each chunk
  for Index = 1, #StringArray do
    local PartUtf8  = StringArray[Index]
    local PartUtf16 = UTF16(PartUtf8)
    append(Result, PartUtf16)
  end
  append(Result, "\x00\x00") -- Final UTF-16 null to end the array
  -- Merge the chunks
  local FinalStringUtf16 = concat(Result)
  -- Return value
  return FinalStringUtf16
end

local function KEY_MethodSet (KeyObject, ValueNameUtf8, Value, TypeStringUtf8)
  -- Validate inputs
  local TypeValue = WIN32_REG_TYPE_VALUES[TypeStringUtf8]
  assert(TypeValue, format("Unknown registry type string: '%s'", TypeStringUtf8))
  -- Encode name
  local ValueNameUtf16 = UTF16(ValueNameUtf8)
  local SizeInBytes
  -- Encode value
  if (TypeValue == REG_SZ) or (TypeValue == REG_EXPAND_SZ) then
    -- REG_SZ/REG_EXPAND_SZ are null-terminated string
    local ValueUtf8  = Value
    local ValueUtf16 = UTF16(ValueUtf8)
    Buffer:write(ValueUtf16)
    SizeInBytes = #ValueUtf16
  elseif (TypeValue == REG_MULTI_SZ) then
    local StringArray = Value
    assert(StringArray, format("Invalid multi-string value for %s: %q", TypeStringUtf8, tostring(Value)))
    local ValueUtf16 = REG_FormatMultiString(StringArray)
    Buffer:write(ValueUtf16)
    SizeInBytes = #ValueUtf16
  elseif (TypeValue == REG_BINARY) then
    local BinaryValue = Value
    Buffer:write(BinaryValue)
    SizeInBytes = #BinaryValue
  elseif (TypeValue == REG_DWORD) then
    local Number = Value
    assert(Number, format("Invalid numeric value for %s: %q", TypeStringUtf8, tostring(Value)))
    local PackedString = pack("=I4", Number)
    Buffer:write(PackedString)
    SizeInBytes = 4
  elseif (TypeValue == REG_DWORD_LITTLE_ENDIAN) then
    local Number = Value
    assert(Number, format("Invalid numeric value for %s: %q", TypeStringUtf8, tostring(Value)))
    local PackedString = pack("<I4", Number)
    Buffer:write(PackedString)
    SizeInBytes = 4
  elseif (TypeValue == REG_DWORD_BIG_ENDIAN) then
    local Number = Value
    assert(Number, format("Invalid numeric value for %s: %q", TypeStringUtf8, tostring(Value)))
    local PackedString = pack(">I4", Number)
    Buffer:write(PackedString)
    SizeInBytes = 4
  elseif (TypeValue == REG_QWORD) then
    local Number = Value
    assert(Number, format("Invalid numeric value for %s: %q", TypeStringUtf8, tostring(Value)))
    local PackedString = pack("=I8", Number)
    Buffer:write(PackedString)
    SizeInBytes = 8
  elseif (TypeValue == REG_QWORD_LITTLE_ENDIAN) then
    local Number = Value
    assert(Number, format("Invalid numeric value for %s: %q", TypeStringUtf8, tostring(Value)))
    local PackedString = pack("<I8", Number)
    Buffer:write(PackedString)
    SizeInBytes = 8
  end
  -- Need to get the actual data pointer late, because the buffer pointer
  -- returned by the raw buffer API may change when we write into it.
  local DataPointer = Buffer:getpointer(0)
  -- For REG_NONE, Win32 expects a NULL data pointer and size 0
  if (TypeValue == REG_NONE) then
    DataPointer = NULL
    SizeInBytes = 0
  end
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  -- Call C API to set the value (pass the raw data pointer)
  local Status = regsetvalueex(RawKey, ValueNameUtf16, DataPointer, SizeInBytes, TypeValue)
  -- Set return value
  local Success = (Status == ERROR_SUCCESS)
  local ErrorMessage
  if (not Success) then
    local Message = WIN32_FormatMessage(Status)
    ErrorMessage = format("%s (error %d)", Message, Status)
  end
  -- Return value
  return Success, ErrorMessage
end

-- REG_ReadKeyValue is not intended for interactive call, but to be used for
-- iterator in KEY_MethodIteratorValues. That's the reason why we don't return
-- an error string from WIN32_FormatMessage and we return regenumvalue's return
-- value.
local function REG_ReadKeyValue (KeyObject, Index)
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  -- Calculate offset
  local Offset = (Index - 1)
  -- Initial buffer size for value name
  local MAX_BUFFER      = 32767
  local MAX_BUFFER_CHAR = ((MAX_BUFFER // 2) - 1)
  Buffer:ensurecapacity(MAX_BUFFER)
  local NamePointer = Buffer:getpointer(0)
  -- Call to RegEnumValue to collect the key name
  local ReturnValue, Type, NameLength = regenumvalue(RawKey, Offset, NamePointer, MAX_BUFFER_CHAR, NULL, 0)
  local ValueType
  local ValueNameUtf8
  local ValueObject
  if (ReturnValue == ERROR_SUCCESS) then
    -- Documentation: If the data has the REG_SZ, REG_MULTI_SZ or REG_EXPAND_SZ
    -- type, this size includes any terminating null character or characters.
    -- Need to consider the ending 0x00 0x00 to the name buffer
    local NameSizeInBytes = ((NameLength + 1) * 2)
    local ValueNameUtf16  = Buffer:read(1, NameSizeInBytes)
    -- Convert the name for API users
    ValueNameUtf8 = UTF8(ValueNameUtf16)
    -- Simply reuse regqueryvalueex to get the value from the name, discard ErrorMessage
    ValueObject, ValueType = KEY_MethodGetImpl(KeyObject, ValueNameUtf16)
  end
  -- Return value
  return ReturnValue, ValueType, ValueNameUtf8, ValueObject
end

local function KEY_MethodIteratorValues (KeyObject)
  -- Closure state
  local CurrentIndex = 1
  -- Iterator function
  local function NextFunction ()
    local ReturnValue, ValueType, ValueNameUtf8, Value = REG_ReadKeyValue(KeyObject, CurrentIndex)
    -- ReturnValue is actually the return value of RegEnumValueW
    if (ReturnValue == 0) then
      CurrentIndex = (CurrentIndex + 1)
      return ValueType, ValueNameUtf8, Value
    else
      return nil -- Stop iteration
    end
  end
  -- Return value
  return NextFunction
end

local function KEY_MethodIterateKeys (KeyObject)
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  -- Local data
  local BufferCharCount
  local NamePointer
  -- Use RegQueryInfoKey to determine number of subkeys and maximum name length
  -- The raw binding regqueryinfokey now returns (Status, SubKeyCount, MaxSubKeyLenChars)
  local Status, SubKeyCount, MaxSubKeyLen = regqueryinfokey(RawKey)
  if (Status == ERROR_SUCCESS) then
    -- MaxSubKeyLen does not include terminator
    BufferCharCount = (MaxSubKeyLen + 1)
    -- Ensure we have enough bytes in the shared buffer
    local BufferBytes = (BufferCharCount * 2)
    Buffer:ensurecapacity(BufferBytes)
    NamePointer = Buffer:getpointer(0)
  else
    SubKeyCount = 0
  end
  -- Iterator state
  local CurrentIndex = 0
  -- Iterator implementation
  local function NextFunction ()
    -- Stop condition
    if (CurrentIndex < SubKeyCount) then
      -- Call RegEnumKeyEx for the key at index Index
      local ReturnValue, NameChars = regenumkeyex(RawKey, CurrentIndex, NamePointer, BufferCharCount)
      if (ReturnValue == ERROR_SUCCESS) then
        local NameSizeInBytes = ((NameChars + 1) * 2)
        local NameUtf16       = Buffer:read(1, NameSizeInBytes)
        local NameUtf8        = UTF8(NameUtf16)
        -- Next key
        CurrentIndex = (CurrentIndex + 1)
        -- Return the key name
        return NameUtf8
      else
        return nil -- stop iteration
      end
    end
  end
  -- Single return at end of function (return the prepared iterator)
  return NextFunction
end

local function KEY_MethodClose (KeyObject)
  -- Return value
  local Success
  local ErrorString
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  if RawKey then
    local Status = regclosekey(RawKey)
    if (Status == ERROR_SUCCESS) then
      KeyObject.RawKey = nil
      Success          = true
    else
      local Message = WIN32_FormatMessage(Status)
      ErrorString   = format("%s (error %d)", Message, Status)
      Success       = false
    end
  else
    Success = false
  end
  -- Return value
  return Success, ErrorString
end

local function KEY_MethodFlush (KeyObject)
  -- Return value
  local Success
  local ErrorMessage
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  -- Call the C API
  local Status = regflushkey(RawKey)
  -- Error handling
  if (Status == ERROR_SUCCESS) then
    Success = true
  else
    local Message = WIN32_FormatMessage(Status)
    -- Format error
    ErrorMessage = format("%s (error %d)", Message, Status)
    -- Set error
    Success = false
  end
  -- Return value
  return Success, ErrorMessage
end

local function KEY_MethodGarbage (KeyObject)
  KeyObject:Close()
end

local function KEY_MethodDeleteValue (KeyObject, ValueNameUtf8)
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  -- Convert value name to UTF-16
  local ValueNameUtf16 = UTF16(ValueNameUtf8)
  -- Call raw API to delete the value
  local Status = regdeletevalue(RawKey, ValueNameUtf16)
  -- Prepare return values (Only one return statement allowed)
  local Success
  local ErrorMessage
  if (Status == ERROR_SUCCESS) then
    Success = true
  else
    local Message = WIN32_FormatMessage(Status)
    ErrorMessage  = format("%s (error %d)", Message, Status)
    Success = false
  end
  -- Return value
  return Success, ErrorMessage
end

local function KEY_MethodGet (KeyObject, ValueNameUtf8)
  -- Convert to UTF-16
  local ValueNameUtf16 = UTF16(ValueNameUtf8)
  -- Call the data-extraction function
  return KEY_MethodGetImpl(KeyObject, ValueNameUtf16)
end

local KEY_Metatable = {
  -- Generic methods
  __gc = KEY_MethodGarbage,
  -- Custom methods
  __index = {
    get    = KEY_MethodGet,
    set    = KEY_MethodSet,
    delete = KEY_MethodDeleteValue,
    flush  = KEY_MethodFlush,
    values = KEY_MethodIteratorValues,
    keys   = KEY_MethodIterateKeys,
    close  = KEY_MethodClose,
  }
}

-- In Win32, HKEY_CLASSES_ROOT, HKEY_CURRENT_USER, etc are integer constants.
-- For convenience, this high level API hide this implementation detail. Here,
-- we need to retrieve that constant from a UTF-8 fully designed key string.
--
-- "HKEY_CURRENT_USER\Volatile Environment" will return HKEY_CURRENT_USER
-- integer value from REG_ROOT_KEYS and "Volatile Environment" string
--
local function REG_SplitRegistryKey (KeyUtf8)
  -- Results
  local Root
  local SubKey
  -- local data
  local Prefix
  local Index = 1
  local Found = false
  local Count = #REG_ROOT_KEYS
  -- Iterate over known keys
  while (not Found) and (Index <= Count) do
    local Entry = REG_ROOT_KEYS[Index]
    local Name  = Entry[1]
    if hasprefix(KeyUtf8, Name) then
      Root   = Entry[2]
      Prefix = Name
      Found  = true
    else
      Index = (Index + 1)
    end
  end
  -- Get the subkey after [[ROOT_KEY\]]
  if Found then
    SubKey = KeyUtf8:sub(#Prefix + 2)
  else
    SubKey = KeyUtf8
  end
  -- Return values
  return Root, SubKey
end

-- Constants for WIN32_NewSam function API
local REG_SamConstants = {
  KEY_ALL_ACCESS         = 0xF003F,
  KEY_CREATE_LINK        = 0x00020,
  KEY_CREATE_SUB_KEY     = 0x00004,
  KEY_ENUMERATE_SUB_KEYS = 0x00008,
  KEY_EXECUTE            = 0x20019,
  KEY_NOTIFY             = 0x00010,
  KEY_QUERY_VALUE        = 0x00001,
  KEY_READ               = 0x20019,
  KEY_SET_VALUE          = 0x00002,
  KEY_WOW64_32KEY        = 0x00200,
  KEY_WOW64_64KEY        = 0x00100,
  KEY_WRITE              = 0x20006
}

-- Sam stands for "Registry Key Security and Access Rights". This function is a
-- convenience function to avoid the API user to deal with constant values and
-- binary OR.
local function REG_NewSam (...)
  -- Local data
  local Array  = {...}
  local NewSam = 0
  -- Process inputs
  for Index = 1, #Array do
    local Sam   = Array[Index]
    local Value = REG_SamConstants[Sam]
    assert(Value, format("Unknown SAM constant: '%s'", Sam))
    NewSam = (NewSam | Value)
  end
  -- Return the value
  return NewSam
end

-- Constants for REG_OPTION_ values used by RegCreateKeyEx
local REG_OptionConstants = {
  REG_OPTION_NON_VOLATILE    = 0x00000000,
  REG_OPTION_VOLATILE        = 0x00000001,
  REG_OPTION_CREATE_LINK     = 0x00000002,
  REG_OPTION_BACKUP_RESTORE  = 0x00000004,
}

local function REG_NewOptions (...)
  -- local data
  local Array      = {...}
  local NewOptions = 0
  -- Process inputs
  for Index = 1, #Array do
    local Name  = Array[Index]
    local Value = REG_OptionConstants[Name]
    assert(Value, format("Unknown OPTION constant: '%s'", Name))
    NewOptions = (NewOptions | Value)
  end
  -- Return the value
  return NewOptions
end

local KEY_READ                = REG_SamConstants.KEY_READ
local REG_OPTION_NON_VOLATILE = REG_OptionConstants.REG_OPTION_NON_VOLATILE

local function REG_RegCreateKey (KeyUtf8, Sam, Options)
  -- Validate inputs
  local UsedSam     = (Sam or KEY_READ)
  local UsedOptions = (Options or REG_OPTION_NON_VOLATILE)
  local UsedClass   = nil
  -- Extract RootKey constant from string
  local RootKey, SubKeyUtf8 = REG_SplitRegistryKey(KeyUtf8)
  assert(RootKey, format("Malformed UTF-8 key '%s'", KeyUtf8))
  -- Convert the string
  local SubKeyUtf16 = UTF16(SubKeyUtf8)
  -- Try create the key (or open if exists)
  local Status, RawKey = regcreatekeyex(RootKey, SubKeyUtf16, UsedClass, UsedOptions, UsedSam)
  local FormattedError
  local NewKeyObject
  if (Status == ERROR_SUCCESS) then
    -- Create the new Lua object
    NewKeyObject = {
      RawKey = RawKey
    }
    -- Attach methods
    setmetatable(NewKeyObject, KEY_Metatable)
  else
    local Message  = WIN32_FormatMessage(Status)
    FormattedError = format("%s (error %d)", Message, Status)
  end
  -- Return value
  return NewKeyObject, FormattedError
end

local function REG_RegOpenKey (KeyUtf8, Sam)
  -- Validate inputs
  local UsedSam     = (Sam or KEY_READ)
  local UsedOptions = 0
  -- Extract RootKey constant from string
  local RootKey, SubKeyUtf8 = REG_SplitRegistryKey(KeyUtf8)
  assert(RootKey, format("Malformed UTF-8 key '%s'", KeyUtf8))
  -- Convert the string
  local SubKeyUtf16 = UTF16(SubKeyUtf8)
  -- Try open the key
  local Status, RawKey = regopenkeyex(RootKey, SubKeyUtf16, UsedOptions, UsedSam)
  local FormattedError
  local NewKeyObject
  if (Status == ERROR_SUCCESS) then
    -- Create the new Lua object
    NewKeyObject = {
      RawKey = RawKey
    }
    -- Attach methods
    setmetatable(NewKeyObject, KEY_Metatable)
  else
    local Message  = WIN32_FormatMessage(Status)
    FormattedError = format("%s (error %d)", Message, Status)
  end
  -- Return value
  return NewKeyObject, FormattedError
end

local function REG_RegDeleteKey (KeyUtf8)
  -- Transform the high-level registry key string
  local RootKey, SubKeyUtf8 = REG_SplitRegistryKey(KeyUtf8)
  assert(RootKey, format("Malformed UTF-8 key '%s'", KeyUtf8))
  -- Call the C API
  local SubKeyUtf16 = UTF16(SubKeyUtf8)
  local Status      = regdeletekey(RootKey, SubKeyUtf16)
  local Success
  local ErrorMessage
  if (Status == ERROR_SUCCESS) then
    Success = true
  else
    local Message = WIN32_FormatMessage(Status)
    ErrorMessage = format("%s (error %d)", Message, Status)
    Success      = false
  end
  -- Return value
  return Success, ErrorMessage
end

--------------------------------------------------------------------------------
-- MISCELLANEOUS                                                              --
--------------------------------------------------------------------------------

local function WIN32_ExpandEnvironmentStrings (StringUtf8)
 -- Convert input to UTF-16
  local StringUtf16, ErrorString = WIN32_utf8toutf16(StringUtf8)
  assert(StringUtf16, ErrorString)
  -- Call the C API
  local RequiredChars = expandenv(StringUtf16, NULL, 0)
  -- local data
  local Result
  local ErrorMessage
  -- Error handling
  if (RequiredChars == 0) then
    local ErrorCode = getlasterror()
    if (ErrorCode == 0) then
      ErrorMessage = "Unknown error"
    else
      ErrorMessage = WIN32_FormatMessage(ErrorCode)
    end
  else
    -- Allocate buffer, include terminator
    local RequiredBytes = (RequiredChars * 2)
    Buffer:ensurecapacity(RequiredBytes)
    local DataPointer = Buffer:getpointer(0)
    -- Perform the expansion
    local WrittenChars = expandenv(StringUtf16, DataPointer, RequiredChars)
    if (WrittenChars == 0) then
      local ErrorCode = getlasterror()
      if (ErrorCode == 0) then
        ErrorMessage  = "Unknown error"
      else
        ErrorMessage = WIN32_FormatMessage(ErrorCode)
      end
    else
      if (WrittenChars <= RequiredChars) then
        -- Success: read WrittenChars wide characters (include terminating NUL)
        local StringUtf16 = Buffer:read(1, (WrittenChars * 2))
        -- Convert back to UTF-8
        Result, ErrorMessage = WIN32_utf16to8(StringUtf16)
      else
        -- The buffer was too small (race condition changed buffer size)
        ErrorMessage = "buffer too small"
      end
    end
  end
  -- Return value
  return Result, ErrorMessage
end

local SW_CONSTANTS = {
  SW_HIDE            = 0,
  SW_SHOWNORMAL      = 1,
  SW_NORMAL          = 1,
  SW_SHOWMINIMIZED   = 2,
  SW_SHOWMAXIMIZED   = 3,
  SW_MAXIMIZE        = 3,
  SW_SHOWNOACTIVATE  = 4,
  SW_SHOW            = 5,
  SW_MINIMIZE        = 6,
  SW_SHOWMINNOACTIVE = 7,
  SW_SHOWNA          = 8,
  SW_RESTORE         = 9,
  SW_SHOWDEFAULT     = 10,
  SW_FORCEMINIMIZE   = 11,
}

local function WIN32_ShellExecute (VerbUtf8, FileUtf8, ParamsUtf8, DirUtf8, ShowCmdString, WaitForProcess)
  -- Convert inputs to UTF-16 (Win32 format)
  local VerbUtf16
  local FileUtf16
  local ParamsUtf16
  local DirUtf16
  -- Handle parameters
  if VerbUtf8 then
    VerbUtf16 = UTF16(VerbUtf8)
  end
  if FileUtf8 then
    FileUtf16 = UTF16(FileUtf8)
  end
  if ParamsUtf8 then
    ParamsUtf16 = UTF16(ParamsUtf8)
  end
  if DirUtf8 then
    DirUtf16 = UTF16(DirUtf8)
  end
  local OptionShowCmdString = (ShowCmdString or "SW_NORMAL")
  local OptionShowCmd       = SW_CONSTANTS[OptionShowCmdString]
  assert(OptionShowCmd, format("Unknown ShowCmd string: '%s'", OptionShowCmdString))
  local OptionWait
  if (WaitForProcess == nil) then
    OptionWait = true
  else
    OptionWait = WaitForProcess
  end
  -- Call the C API
  local Success, ExitCode = shellexecute(VerbUtf16, FileUtf16, ParamsUtf16, DirUtf16, OptionShowCmd, OptionWait)
  local ErrorMessage
  if (not Success) then
    local ErrorCode = getlasterror()
    -- Format error
    ErrorMessage = WIN32_FormatMessage(ErrorCode)
  end
  -- Return value
  return Success, ExitCode, ErrorMessage
end

--------------------------------------------------------------------------------
-- HIGH LEVEL: REUSE FUNCTIONS ABOVE                                          --
--------------------------------------------------------------------------------

local function WIN32_OpenBrowser (Uri)
  -- validate inputs
  assert(Uri, "Uri is required")
  -- Prepare the call
  local Operation   = "open"
  local File        = Uri
  local Parameters  = nil
  local Directory   = nil
  local ShowCommand = "SW_SHOWNORMAL"
  local OptionWait  = true
  -- Call the API
  local ExecuteSuccess, ReturnCode, ErrorString = WIN32_ShellExecute(Operation, File, Parameters, Directory, ShowCommand, OptionWait)
  -- Determine success
  local ReturnedSuccess
  if ExecuteSuccess and (ReturnCode == 0) then
    ReturnedSuccess = true
  elseif ErrorString then
    ReturnedSuccess = false
  else
    ErrorString = WIN32_FormatMessage(ReturnCode)
  end
  -- return value
  return ReturnedSuccess, ErrorString
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  -- UTF conversions
  utf8to16 = WIN32_utf8toutf16,
  utf16to8 = WIN32_utf16to8,
  -- Registry
  newsam       = REG_NewSam,
  newoptions   = REG_NewOptions,
  regcreatekey = REG_RegCreateKey,
  regopenkey   = REG_RegOpenKey,
  regdeletekey = REG_RegDeleteKey,
  -- Miscellaneous
  getlasterror  = getlasterror,
  formatmessage = WIN32_FormatMessage,
  expandstrings = WIN32_ExpandEnvironmentStrings,
  shellexecute  = WIN32_ShellExecute,
  -- High level
  openbrowser = WIN32_OpenBrowser
}

return PUBLIC_API
