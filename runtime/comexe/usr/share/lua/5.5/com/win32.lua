--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- This library is a high-level library on top of the Win32 API
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

local Runtime = require("com.runtime")
local libffi  = require("com.ffi")

local format = string.format
local pack   = string.pack
local unpack = string.unpack
local byte   = string.byte
local concat = table.concat

local append    = Runtime.append
local NewBuffer = Runtime.newbuffer
local hasprefix = Runtime.hasprefix

local NULL          = libffi.NULL
local readstring    = libffi.readstring
local readstringw   = libffi.readstringw
local stringpointer = libffi.stringpointer
local newpointer    = libffi.newpointer
local newarray      = libffi.newarray
local newinstance   = libffi.newinstance
local derefpointer  = libffi.derefpointer
local readvalue     = libffi.readvalue
local writevalue    = libffi.writevalue
local sizeof        = libffi.sizeof
local uint32        = libffi.uint32
local pointer       = libffi.pointer

--------------------------------------------------------------------------------
-- FFI IMPORTS                                                                --
--------------------------------------------------------------------------------

-- @BEGIN FfiHeader("BindWin32", "libffi", "win32.h")
-- @OUTPUT
-- Constants
local CP_UTF8 = 65001
local ERROR_SUCCESS = 0
local FORMAT_MESSAGE_FROM_SYSTEM = 4096
local FORMAT_MESSAGE_IGNORE_INSERTS = 512
local FORMAT_MESSAGE_MAX_WIDTH_MASK = 255
local IDCANCEL = 2
local IDNO = 7
local IDOK = 1
local IDYES = 6
local INFINITE = 4294967295
local KEY_ALL_ACCESS = 983103
local KEY_CREATE_LINK = 32
local KEY_CREATE_SUB_KEY = 4
local KEY_ENUMERATE_SUB_KEYS = 8
local KEY_EXECUTE = 131097
local KEY_NOTIFY = 16
local KEY_QUERY_VALUE = 1
local KEY_READ = 131097
local KEY_SET_VALUE = 2
local KEY_WOW64_32KEY = 512
local KEY_WOW64_64KEY = 256
local KEY_WRITE = 131078
local MB_ERR_INVALID_CHARS = 8
local MB_ICONERROR = 16
local MB_ICONINFORMATION = 64
local MB_ICONQUESTION = 32
local MB_ICONWARNING = 48
local MB_OK = 0
local MB_OKCANCEL = 1
local MB_YESNO = 4
local MB_YESNOCANCEL = 3
local REG_BINARY = 3
local REG_DWORD = 4
local REG_DWORD_BIG_ENDIAN = 5
local REG_DWORD_LITTLE_ENDIAN = 4
local REG_EXPAND_SZ = 2
local REG_FULL_RESOURCE_DESCRIPTOR = 9
local REG_LINK = 6
local REG_MULTI_SZ = 7
local REG_NONE = 0
local REG_OPTION_BACKUP_RESTORE = 4
local REG_OPTION_CREATE_LINK = 2
local REG_OPTION_NON_VOLATILE = 0
local REG_OPTION_VOLATILE = 1
local REG_QWORD = 11
local REG_QWORD_LITTLE_ENDIAN = 11
local REG_RESOURCE_LIST = 8
local REG_RESOURCE_REQUIREMENTS_LIST = 10
local REG_SZ = 1
local SEE_MASK_NOCLOSEPROCESS = 64
local SW_FORCEMINIMIZE = 11
local SW_HIDE = 0
local SW_MAXIMIZE = 3
local SW_MINIMIZE = 6
local SW_NORMAL = 1
local SW_RESTORE = 9
local SW_SHOW = 5
local SW_SHOWDEFAULT = 10
local SW_SHOWMAXIMIZED = 3
local SW_SHOWMINIMIZED = 2
local SW_SHOWMINNOACTIVE = 7
local SW_SHOWNA = 8
local SW_SHOWNOACTIVATE = 4
local SW_SHOWNORMAL = 1
local WC_ERR_INVALID_CHARS = 128
-- Structures
local SHELLEXECUTEINFOW
-- Functions
local CloseHandle
local ExpandEnvironmentStringsW
local FormatMessageW
local GetExitCodeProcess
local GetLastError
local MessageBoxW
local MultiByteToWideChar
local RegCloseKey
local RegCreateKeyExW
local RegDeleteKeyW
local RegDeleteValueW
local RegEnumKeyExW
local RegEnumValueW
local RegFlushKey
local RegOpenKeyExW
local RegQueryInfoKeyW
local RegQueryValueExW
local RegSetValueExW
local ShellExecuteExW
local WaitForSingleObject
local WideCharToMultiByte
-- Binding function
local function BindWin32 (Library)
  SHELLEXECUTEINFOW = libffi.newstructure("SHELLEXECUTEINFOW",
    libffi.uint32, "cbSize",
    libffi.uint32, "fMask",
    libffi.pointer, "hwnd",
    libffi.cstring, "lpVerb",
    libffi.cstring, "lpFile",
    libffi.cstring, "lpParameters",
    libffi.cstring, "lpDirectory",
    libffi.sint32, "nShow",
    libffi.pointer, "hInstApp",
    libffi.pointer, "lpIDList",
    libffi.cstring, "lpClass",
    libffi.pointer, "hkeyClass",
    libffi.uint32, "dwHotKey",
    libffi.pointer, "hIcon",
    libffi.pointer, "hProcess"
  )
  CloseHandle = Library:bind(libffi.sint32, "CloseHandle", libffi.pointer)
  ExpandEnvironmentStringsW = Library:bind(libffi.uint32, "ExpandEnvironmentStringsW", libffi.pointer, libffi.pointer, libffi.uint32)
  FormatMessageW = Library:bind(libffi.uint32, "FormatMessageW", libffi.uint32, libffi.pointer, libffi.uint32, libffi.uint32, libffi.pointer, libffi.uint32, libffi.pointer)
  GetExitCodeProcess = Library:bind(libffi.sint32, "GetExitCodeProcess", libffi.pointer, libffi.pointer)
  GetLastError = Library:bind(libffi.uint32, "GetLastError")
  MessageBoxW = Library:bind(libffi.sint32, "MessageBoxW", libffi.pointer, libffi.pointer, libffi.pointer, libffi.uint32)
  MultiByteToWideChar = Library:bind(libffi.sint32, "MultiByteToWideChar", libffi.uint32, libffi.uint32, libffi.pointer, libffi.sint32, libffi.pointer, libffi.sint32)
  RegCloseKey = Library:bind(libffi.sint32, "RegCloseKey", libffi.pointer)
  RegCreateKeyExW = Library:bind(libffi.sint32, "RegCreateKeyExW", libffi.pointer, libffi.pointer, libffi.uint32, libffi.pointer, libffi.uint32, libffi.uint32, libffi.pointer, libffi.pointer, libffi.pointer)
  RegDeleteKeyW = Library:bind(libffi.sint32, "RegDeleteKeyW", libffi.pointer, libffi.pointer)
  RegDeleteValueW = Library:bind(libffi.sint32, "RegDeleteValueW", libffi.pointer, libffi.pointer)
  RegEnumKeyExW = Library:bind(libffi.sint32, "RegEnumKeyExW", libffi.pointer, libffi.uint32, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer)
  RegEnumValueW = Library:bind(libffi.sint32, "RegEnumValueW", libffi.pointer, libffi.uint32, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer)
  RegFlushKey = Library:bind(libffi.sint32, "RegFlushKey", libffi.pointer)
  RegOpenKeyExW = Library:bind(libffi.sint32, "RegOpenKeyExW", libffi.pointer, libffi.pointer, libffi.uint32, libffi.uint32, libffi.pointer)
  RegQueryInfoKeyW = Library:bind(libffi.sint32, "RegQueryInfoKeyW", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer)
  RegQueryValueExW = Library:bind(libffi.sint32, "RegQueryValueExW", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer)
  RegSetValueExW = Library:bind(libffi.sint32, "RegSetValueExW", libffi.pointer, libffi.pointer, libffi.uint32, libffi.uint32, libffi.pointer, libffi.uint32)
  ShellExecuteExW = Library:bind(libffi.sint32, "ShellExecuteExW", libffi.pointer)
  WaitForSingleObject = Library:bind(libffi.uint32, "WaitForSingleObject", libffi.pointer, libffi.uint32)
  WideCharToMultiByte = Library:bind(libffi.sint32, "WideCharToMultiByte", libffi.uint32, libffi.uint32, libffi.pointer, libffi.sint32, libffi.pointer, libffi.sint32, libffi.pointer, libffi.pointer)
end
-- @END

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

-- A single buffer for everything, set to 4 KiB for FormatMessage
local BUFFER_SIZE = 4096
local Buffer      = NewBuffer(BUFFER_SIZE)

-- Buffers reused in registry functions
local PointerArray   = newarray(pointer, 1)
local IntegerArray   = newarray(uint32, 2)
local PointerPointer = PointerArray:getpointer()

-- Pre-declaration, implemented in WIN32_utf16to8Impl, needed because:
-- WIN32_FormatMessage calls WIN32_utf16to8
-- WIN32_utf16to8      calls WIN32_FormatMessage
local WIN32_utf16to8

--------------------------------------------------------------------------------
-- LUA MAPPING                                                                --
--------------------------------------------------------------------------------

-- String -> Win32 constant value
local WIN32_REG_TYPE_VALUES = {
  REG_NONE                       = REG_NONE,
  REG_SZ                         = REG_SZ,
  REG_EXPAND_SZ                  = REG_EXPAND_SZ,
  REG_BINARY                     = REG_BINARY,
  REG_DWORD                      = REG_DWORD,
  REG_DWORD_LITTLE_ENDIAN        = REG_DWORD_LITTLE_ENDIAN,
  REG_DWORD_BIG_ENDIAN           = REG_DWORD_BIG_ENDIAN,
  REG_LINK                       = REG_LINK,
  REG_MULTI_SZ                   = REG_MULTI_SZ,
  REG_RESOURCE_LIST              = REG_RESOURCE_LIST,
  REG_FULL_RESOURCE_DESCRIPTOR   = REG_FULL_RESOURCE_DESCRIPTOR,
  REG_RESOURCE_REQUIREMENTS_LIST = REG_RESOURCE_REQUIREMENTS_LIST,
  REG_QWORD                      = REG_QWORD,
  REG_QWORD_LITTLE_ENDIAN        = REG_QWORD_LITTLE_ENDIAN,
}

-- Win32 constant value -> string name
local WIN32_REG_TYPE_NAMES = {}
for ConstantName, ConstantValue in pairs(WIN32_REG_TYPE_VALUES) do
  WIN32_REG_TYPE_NAMES[ConstantValue] = ConstantName
end

-- Fix dictionary: remove duplicated values
WIN32_REG_TYPE_NAMES[4]  = "REG_DWORD"
WIN32_REG_TYPE_NAMES[11] = "REG_QWORD"

-- Constants for WIN32_NewSam function API
local REG_SamConstants = {
  KEY_ALL_ACCESS         = KEY_ALL_ACCESS,
  KEY_CREATE_LINK        = KEY_CREATE_LINK,
  KEY_CREATE_SUB_KEY     = KEY_CREATE_SUB_KEY,
  KEY_ENUMERATE_SUB_KEYS = KEY_ENUMERATE_SUB_KEYS,
  KEY_EXECUTE            = KEY_EXECUTE,
  KEY_NOTIFY             = KEY_NOTIFY,
  KEY_QUERY_VALUE        = KEY_QUERY_VALUE,
  KEY_READ               = KEY_READ,
  KEY_SET_VALUE          = KEY_SET_VALUE,
  KEY_WOW64_32KEY        = KEY_WOW64_32KEY,
  KEY_WOW64_64KEY        = KEY_WOW64_64KEY,
  KEY_WRITE              = KEY_WRITE
}

-- Constants for REG_OPTION_ values used by RegCreateKeyEx
local REG_OptionConstants = {
  REG_OPTION_NON_VOLATILE   = REG_OPTION_NON_VOLATILE,
  REG_OPTION_VOLATILE       = REG_OPTION_VOLATILE,
  REG_OPTION_CREATE_LINK    = REG_OPTION_CREATE_LINK,
  REG_OPTION_BACKUP_RESTORE = REG_OPTION_BACKUP_RESTORE,
}

-- Constants for the ShellExecute ShowCmd
local SW_CONSTANTS = {
  SW_HIDE            = SW_HIDE,
  SW_SHOWNORMAL      = SW_SHOWNORMAL,
  SW_NORMAL          = SW_NORMAL,
  SW_SHOWMINIMIZED   = SW_SHOWMINIMIZED,
  SW_SHOWMAXIMIZED   = SW_SHOWMAXIMIZED,
  SW_MAXIMIZE        = SW_MAXIMIZE,
  SW_SHOWNOACTIVATE  = SW_SHOWNOACTIVATE,
  SW_SHOW            = SW_SHOW,
  SW_MINIMIZE        = SW_MINIMIZE,
  SW_SHOWMINNOACTIVE = SW_SHOWMINNOACTIVE,
  SW_SHOWNA          = SW_SHOWNA,
  SW_RESTORE         = SW_RESTORE,
  SW_SHOWDEFAULT     = SW_SHOWDEFAULT,
  SW_FORCEMINIMIZE   = SW_FORCEMINIMIZE,
}

-- MessageBox type, keyed by name for the messagebox API
local MB_TYPE = {
  OK          = MB_OK,
  OKCANCEL    = MB_OKCANCEL,
  YESNO       = MB_YESNO,
  YESNOCANCEL = MB_YESNOCANCEL,
}

-- MessageBox icon, keyed by name for the messagebox API
local MB_ICON = {
  NONE        = 0,
  INFORMATION = MB_ICONINFORMATION,
  WARNING     = MB_ICONWARNING,
  ERROR       = MB_ICONERROR,
  QUESTION    = MB_ICONQUESTION,
}

-- MB_BUTTON is dict integer->string, NOT string->string
local MB_BUTTON = {
  [IDOK]     = "ok",
  [IDCANCEL] = "cancel",
  [IDYES]    = "yes",
  [IDNO]     = "no",
}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function WIN32_FormatMessage (ErrorCode)
  -- local data
  local Result
  -- We don't call Buffer:ensurecapacity(BUFFER_SIZE) because we use a static 4
  -- KiB buffer.
  local Flags = (FORMAT_MESSAGE_MAX_WIDTH_MASK | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS)
  -- Retrieve the actual C pointer
  local BufferPointer = Buffer:getpointer(0)
  -- FormatMessageW returns the number of characters written, excluding the
  -- NULL. There is not clear way to remove newline characters.
  local CharWritten = FormatMessageW(Flags, NULL, ErrorCode, 0, BufferPointer, (BUFFER_SIZE // 2), NULL)
  -- Error handling
  if (CharWritten >= 1) then
    local Utf16String = Buffer:read(1, (CharWritten * 2))
    local Utf8String  = WIN32_utf16to8(Utf16String)
    if Utf8String then
      -- Trim the string from FormatMessageW to avoid ending newline
      Result = Utf8String:gsub("[ \t\r\n]+$", "")
    end
  end
  if (Result == nil) then
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
  -- We need this special case because when calling MultiByteToWideChar with an
  -- empty string, it return 0 with GetLastError Invalid param.
  if (StringUtf8 == "") then
    StringUtf16 = "\x00\x00"
  else
    -- Call MultiByteToWideChar a first time to determine the required buffer size
    local RequiredChars = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, StringUtf8, -1, NULL, 0)
    if (RequiredChars == 0) then
      local ErrorCode = GetLastError()
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
      local WrittenChars = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, StringUtf8, -1, DataPointer, RequiredChars)
      if (WrittenChars == 0) then
        local ErrorCode = GetLastError()
        if (ErrorCode == 0) then
          ErrorString = "Unknown error" -- Should not happen
        else
          ErrorString = WIN32_FormatMessage(ErrorCode)
        end
      else
        -- Convert into a Lua string, including 2 additional 0x00 (thanks to -1 in MultiByteToWideChar)
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

local function WIN32_utf16to8Impl (StringUtf16)
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
    local RequiredBytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, StringUtf16, CharCount, NULL, 0, NULL, false)
    if (RequiredBytes == 0) then
      local ErrorCode = GetLastError()
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
      local Written = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, StringUtf16, CharCount, DataPointer, TotalByteCount, NULL, false)
      if (Written == 0) then
        local ErrorCode = GetLastError()
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
  -- Return value
  return Result, ErrorString
end
WIN32_utf16to8 = WIN32_utf16to8Impl -- Pre-declaration

-- This function is in Win32 and not in ffi.lua common to both Linux/Windows
-- because we use the conversion functions from the Win32.
--
-- Can return nil
local function WIN32_PointerToString (Address, SourceEncoding, TargetEncoding)
  local Result
  local ErrorString
  if (Address ~= NULL) then
    local RawBytes
    if (SourceEncoding == "utf8") then
      RawBytes = readstring(Address)
    elseif (SourceEncoding == "utf16") then
      RawBytes = readstringw(Address)
    end
    if (RawBytes and (#RawBytes > 0)) then
      if (SourceEncoding == TargetEncoding) then
        Result = RawBytes
      elseif (SourceEncoding == "utf16") then
        Result, ErrorString = WIN32_utf16to8(RawBytes)
      else
        Result, ErrorString = WIN32_utf8toutf16(RawBytes)
      end
    end
  end
  -- Return value
  return Result, ErrorString
end

--------------------------------------------------------------------------------
-- REGISTRY                                                                   --
--------------------------------------------------------------------------------

-- Root keys are not exported in WIN32_Constants, only used internally.
-- HKEY root constants are integers like 0x80000000 but used as pointers (HKEY)
local REG_ROOT_KEYS = {
  { "HKEY_CLASSES_ROOT",                newpointer(0, 0x80000000) },
  { "HKEY_CURRENT_USER",                newpointer(0, 0x80000001) },
  { "HKEY_LOCAL_MACHINE",               newpointer(0, 0x80000002) },
  { "HKEY_USERS",                       newpointer(0, 0x80000003) },
  { "HKEY_PERFORMANCE_DATA",            newpointer(0, 0x80000004) },
  { "HKEY_PERFORMANCE_TEXT",            newpointer(0, 0x80000050) },
  { "HKEY_PERFORMANCE_NLSTEXT",         newpointer(0, 0x80000060) },
  { "HKEY_CURRENT_CONFIG",              newpointer(0, 0x80000005) },
  { "HKEY_DYN_DATA",                    newpointer(0, 0x80000006) },
  { "HKEY_CURRENT_USER_LOCAL_SETTINGS", newpointer(0, 0x80000007) },
}

-- Convert a C pointer to a buffer into a Lua array of UTF-8 strings
local function REG_ParseMultiString (Utf16String)
  -- Convert whole buffer to UTF-8 first
  local AllUtf8 = WIN32_utf16to8(Utf16String)
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
    ConvertedValue = WIN32_utf16to8(RawValue)
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

-- LSTATUS RegQueryValueExW(
--   [in]                HKEY    hKey,
--   [in, optional]      LPCWSTR lpValueName,
--                       LPDWORD lpReserved,
--   [out, optional]     LPDWORD lpType,
--   [out, optional]     LPBYTE  lpData,
--   [in, out, optional] LPDWORD lpcbData
-- );
local function KEY_MethodGetImpl (KeyObject, ValueNameUtf16)
  -- local data
  local ResultValue
  local ResultType
  local ResultErrorMessage
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  -- Get pointers to integer from the shared array
  local OutTypePointer = IntegerArray:getpointer(1)
  local OutSizePointer = IntegerArray:getpointer(2)
  -- Call the Win32 RegQueryValueExW to retrieve the TYPE and SIZE
  local Status = RegQueryValueExW(RawKey, ValueNameUtf16, NULL, OutTypePointer, NULL, OutSizePointer)
  if (Status == ERROR_SUCCESS) then
    -- Read back the values TYPE and SIZE
    local Type        = readvalue(OutTypePointer, 0, uint32)
    local SizeInBytes = readvalue(OutSizePointer, 0, uint32)
    -- Evaluate result
    if (SizeInBytes == 0) then
      ResultType = (WIN32_REG_TYPE_NAMES[Type] or "UnknownType")
    else
      -- Retrieve data
      Buffer:ensurecapacity(SizeInBytes)
      local DataPointer = Buffer:getpointer(0)
      -- Call the Win32 RegQueryValueExW to retrieve the DATA
      Status = RegQueryValueExW(RawKey, ValueNameUtf16, NULL, OutTypePointer, DataPointer, OutSizePointer)
      -- Convert the data
      if (Status == ERROR_SUCCESS) then
        -- Read back the values TYPE and SIZE
        Type        = readvalue(OutTypePointer, 0, uint32)
        SizeInBytes = readvalue(OutSizePointer, 0, uint32)
        -- Convert
        local RawData        = Buffer:read(1, SizeInBytes)
        local ConvertedValue = REG_ConvertRawValue(RawData, Type)
        -- Set results
        ResultValue = ConvertedValue
        ResultType  = (WIN32_REG_TYPE_NAMES[Type] or "UnknownType")
      else
        -- Second call to RegQueryValueExW failed, the return value is directly
        -- usable by WIN32_FormatMessage without GetLastError
        ResultErrorMessage = WIN32_FormatMessage(Status)
      end
    end
  else
    -- First call to RegQueryValueExW failed, the return value is directly
    -- usable by WIN32_FormatMessage without GetLastError
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
    local PartUtf16 = WIN32_utf8toutf16(PartUtf8)
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
  local ValueNameUtf16 = WIN32_utf8toutf16(ValueNameUtf8)
  local SizeInBytes
  -- Encode value
  if (TypeValue == REG_SZ) or (TypeValue == REG_EXPAND_SZ) then
    -- REG_SZ/REG_EXPAND_SZ are null-terminated string
    local ValueUtf8  = Value
    local ValueUtf16 = WIN32_utf8toutf16(ValueUtf8)
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
  local Status = RegSetValueExW(RawKey, ValueNameUtf16, 0, TypeValue, DataPointer, SizeInBytes)
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
-- an error string from WIN32_FormatMessage and we return RegEnumValueW's return
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
  -- Get pointers to integer from the shared array
  local OutCountPointer = IntegerArray:getpointer(1)
  local OutTypePointer  = IntegerArray:getpointer(2)
  -- Initialize the API parameters
  writevalue(OutCountPointer, 0, uint32, MAX_BUFFER_CHAR)
  -- Call to RegEnumValueW API to collect the key name
  local ReturnValue = RegEnumValueW(RawKey, Offset, NamePointer, OutCountPointer, NULL, OutTypePointer, NULL, NULL)
  local ValueType
  local ValueNameUtf8
  local ValueObject
  if (ReturnValue == ERROR_SUCCESS) then
    -- Read back the values TYPE and NAME LENGTH
    local Type       = readvalue(OutTypePointer,  0, uint32)
    local NameLength = readvalue(OutCountPointer, 0, uint32)
    -- Documentation: If the data has the REG_SZ, REG_MULTI_SZ or REG_EXPAND_SZ
    -- type, this size includes any terminating null character or characters.
    -- Need to consider the ending 0x00 0x00 to the name buffer
    local NameSizeInBytes = ((NameLength + 1) * 2)
    local ValueNameUtf16  = Buffer:read(1, NameSizeInBytes)
    -- Convert the name for API users
    ValueNameUtf8 = WIN32_utf16to8(ValueNameUtf16)
    -- Simply reuse RegQueryValueExW to get the value from the name, discard ErrorMessage
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
    if (ReturnValue == ERROR_SUCCESS) then
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
  local SubKeyCount
  -- Get pointers to integer from the shared array
  local OutCountPointer  = IntegerArray:getpointer(1)
  local OutLengthPointer = IntegerArray:getpointer(2)
  -- Call RegQueryInfoKeyW API
  local Status = RegQueryInfoKeyW(RawKey, NULL, NULL, NULL, OutCountPointer, OutLengthPointer, NULL, NULL, NULL, NULL, NULL, NULL)
  if (Status == ERROR_SUCCESS) then
    -- Read back the result
    SubKeyCount        = readvalue(OutCountPointer,  0, uint32)
    local MaxSubKeyLen = readvalue(OutLengthPointer, 0, uint32)
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
      -- Prepare RegEnumKeyEx API call
      writevalue(OutCountPointer, 0, uint32, BufferCharCount)
      -- Call RegEnumKeyEx for the key at index Index
      local ReturnValue = RegEnumKeyExW(RawKey, CurrentIndex, NamePointer, OutCountPointer, NULL, NULL, NULL, NULL)
      if (ReturnValue == ERROR_SUCCESS) then
        local NameChars       = readvalue(OutCountPointer, 0, uint32)
        local NameSizeInBytes = ((NameChars + 1) * 2)
        local NameUtf16       = Buffer:read(1, NameSizeInBytes)
        local NameUtf8        = WIN32_utf16to8(NameUtf16)
        -- Next key
        CurrentIndex = (CurrentIndex + 1)
        -- Return the key name
        return NameUtf8
      else
        return nil -- stop iteration
      end
    end
  end
  -- Return value
  return NextFunction
end

local function KEY_MethodClose (KeyObject)
  -- Return value
  local Success
  local ErrorString
  -- Retrieve data
  local RawKey = KeyObject.RawKey
  if RawKey then
    local Status = RegCloseKey(RawKey)
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
  local Status = RegFlushKey(RawKey)
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
  local ValueNameUtf16 = WIN32_utf8toutf16(ValueNameUtf8)
  -- Call raw API to delete the value
  local Status = RegDeleteValueW(RawKey, ValueNameUtf16)
  -- Prepare return values (Only one return statement allowed)
  local Success
  local ErrorMessage
  if (Status == ERROR_SUCCESS) then
    Success = true
  else
    local Message = WIN32_FormatMessage(Status)
    ErrorMessage  = format("%s (error %d)", Message, Status)
    Success       = false
  end
  -- Return value
  return Success, ErrorMessage
end

local function KEY_MethodGet (KeyObject, ValueNameUtf8)
  -- Convert to UTF-16
  local ValueNameUtf16 = WIN32_utf8toutf16(ValueNameUtf8)
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
-- pointer value from REG_ROOT_KEYS and "Volatile Environment" string
--
local function REG_SplitRegistryKey (KeyUtf8)
  -- Results
  local RootKey
  local SubKey
  -- local data
  local Prefix
  local Index = 1
  local Found = false
  local Count = #REG_ROOT_KEYS
  -- Find the root key from REG_ROOT_KEYS
  while (not Found) and (Index <= Count) do
    local Candidate = REG_ROOT_KEYS[Index]
    local Name      = Candidate[1]
    if hasprefix(KeyUtf8, Name) then
      RootKey = Candidate[2]
      Prefix  = Name
      Found   = true
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
  -- Return values: root key (pointer), SubKey (String)
  return RootKey, SubKey
end

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

-- LSTATUS RegCreateKeyExW(
--  [in]            HKEY    hKey,
--  [in]            LPCWSTR lpSubKey,
--                  DWORD   Reserved,
--  [in, optional]  LPWSTR  lpClass,
--  [in]            DWORD   dwOptions,
--  [in]            REGSAM  samDesired,
--  [in, optional]  const LPSECURITY_ATTRIBUTES lpSecurityAttributes,
--  [out]           PHKEY   phkResult,
--  [out, optional] LPDWORD lpdwDisposition
-- );
local function REG_RegCreateKey (KeyUtf8, Sam, Options)
  -- Handle defaults
  local UsedSam     = (Sam or KEY_READ)
  local UsedOptions = (Options or REG_OPTION_NON_VOLATILE)
  local UsedClass   = NULL
  -- Extract RootKey constant from string
  local RootKeyPointer, SubKeyUtf8 = REG_SplitRegistryKey(KeyUtf8)
  assert(RootKeyPointer, format("Malformed UTF-8 key '%s'", KeyUtf8))
  -- Convert the string
  local SubKeyUtf16 = WIN32_utf8toutf16(SubKeyUtf8)
  -- Try create the key (or open if exists)
  local Status = RegCreateKeyExW(RootKeyPointer, SubKeyUtf16, 0, UsedClass, UsedOptions, UsedSam, NULL, PointerPointer, NULL)
  local FormattedErrorString
  local NewKeyObject
  if (Status == ERROR_SUCCESS) then
    -- Read back resulting pointer
    local RawKey = derefpointer(PointerPointer)
    -- Create the new Lua object
    NewKeyObject = {
      RawKey = RawKey
    }
    -- Attach methods
    setmetatable(NewKeyObject, KEY_Metatable)
  else
    local Message        = WIN32_FormatMessage(Status)
    FormattedErrorString = format("%s (error %d)", Message, Status)
  end
  -- Return value
  return NewKeyObject, FormattedErrorString
end

local function REG_RegOpenKey (KeyUtf8, Sam)
  -- Validate inputs
  local UsedSam     = (Sam or KEY_READ)
  local UsedOptions = 0
  -- Extract RootKey constant from string
  local RootKeyPointer, SubKeyUtf8 = REG_SplitRegistryKey(KeyUtf8)
  assert(RootKeyPointer, format("Malformed UTF-8 key '%s'", KeyUtf8))
  -- Convert the string
  local SubKeyUtf16 = WIN32_utf8toutf16(SubKeyUtf8)
  -- Try open the key
  local Status = RegOpenKeyExW(RootKeyPointer, SubKeyUtf16, UsedOptions, UsedSam, PointerPointer)
  local FormattedErrorString
  local NewKeyObject
  if (Status == ERROR_SUCCESS) then
    -- Read back resulting pointer
    local RawKey = derefpointer(PointerPointer)
    -- Create the new Lua object
    NewKeyObject = {
      RawKey = RawKey
    }
    -- Attach methods
    setmetatable(NewKeyObject, KEY_Metatable)
  else
    local Message        = WIN32_FormatMessage(Status)
    FormattedErrorString = format("%s (error %d)", Message, Status)
  end
  -- Return value
  return NewKeyObject, FormattedErrorString
end

local function REG_RegDeleteKey (KeyUtf8)
  -- Transform the high-level registry key string
  local RootKeyPointer, SubKeyUtf8 = REG_SplitRegistryKey(KeyUtf8)
  assert(RootKeyPointer, format("Malformed UTF-8 key '%s'", KeyUtf8))
  -- Call the C API
  local SubKeyUtf16 = WIN32_utf8toutf16(SubKeyUtf8)
  local Status      = RegDeleteKeyW(RootKeyPointer, SubKeyUtf16)
  local Success
  local ErrorMessage
  if (Status == ERROR_SUCCESS) then
    Success = true
  else
    local Message = WIN32_FormatMessage(Status)
    ErrorMessage  = format("%s (error %d)", Message, Status)
    Success       = false
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
  local RequiredChars = ExpandEnvironmentStringsW(StringUtf16, NULL, 0)
  -- local data
  local Result
  local ErrorMessage
  -- Error handling
  if (RequiredChars == 0) then
    local ErrorCode = GetLastError()
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
    local WrittenChars = ExpandEnvironmentStringsW(StringUtf16, DataPointer, RequiredChars)
    if (WrittenChars == 0) then
      local ErrorCode = GetLastError()
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

-- int MessageBoxW(
--   [in] HWND    hWnd,
--   [in] LPCWSTR lpText,
--   [in] LPCWSTR lpCaption,
--   [in] UINT    uType
-- );
--
-- Usage: Win32.messagebox(Hwnd, Text, Title, Type, Icon)
-- Return "ok" | "cancel" | "yes" | "no"
local function WIN32_MessageBox (Hwnd, Text, Title, Type, Icon)
  -- Handle defaults
  local TypeValue  = (MB_TYPE[Type] or MB_OK)
  local IconValue  = (MB_ICON[Icon] or 0)
  local TitleValue = (Title or "Message")
  -- Prepare data
  local Flags        = (TypeValue | IconValue)
  local TextUtf16    = WIN32_utf8toutf16(Text)
  local TitleUtf16   = WIN32_utf8toutf16(TitleValue)
  local TextPointer  = stringpointer(TextUtf16)
  local TitlePointer = stringpointer(TitleUtf16)
  -- Call the Win32 API
  local Result = MessageBoxW(Hwnd, TextPointer, TitlePointer, Flags)
  -- Return value
  local ReturnValue = (MB_BUTTON[Result] or format("Error-%q", Result))
  return ReturnValue
end

local function WIN32_ShellExecute (VerbUtf8, FileUtf8, ParamsUtf8, DirUtf8, ShowCmdString, WaitForProcess)
  -- Convert inputs to UTF-16 (Win32 format)
  local VerbUtf16
  local FileUtf16
  local ParamsUtf16
  local DirUtf16
  -- Handle parameters
  if VerbUtf8 then
    VerbUtf16 = WIN32_utf8toutf16(VerbUtf8)
  end
  if FileUtf8 then
    FileUtf16 = WIN32_utf8toutf16(FileUtf8)
  end
  if ParamsUtf8 then
    ParamsUtf16 = WIN32_utf8toutf16(ParamsUtf8)
  end
  if DirUtf8 then
    DirUtf16 = WIN32_utf8toutf16(DirUtf8)
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
  -- Call the shell
  local Info = newinstance(SHELLEXECUTEINFOW)
  Info:set("cbSize",       sizeof(SHELLEXECUTEINFOW))
  Info:set("fMask",        SEE_MASK_NOCLOSEPROCESS)
  Info:set("hwnd",         NULL)
  Info:set("lpVerb",       VerbUtf16)
  Info:set("lpFile",       FileUtf16)
  Info:set("lpParameters", ParamsUtf16)
  Info:set("lpDirectory",  DirUtf16)
  Info:set("nShow",        OptionShowCmd)
  Info:set("hInstApp",     NULL)
  Info:set("hProcess",     NULL)
  local Success = ShellExecuteExW(Info:getpointer())
  local ExitCode
  if Success then
    local Process = Info:get("hProcess")
    if (Process ~= NULL) then
      if OptionWait then
        WaitForSingleObject(Process, INFINITE)
        local ExitCodePointer = IntegerArray:getpointer(1)
        local GotExitCode     = GetExitCodeProcess(Process, ExitCodePointer)
        if (GotExitCode ~= 0) then
          ExitCode = readvalue(ExitCodePointer, 0, uint32)
        end
      end
      CloseHandle(Process)
    end
  end
  local ErrorMessage
  if (not Success) then
    local ErrorCode = GetLastError()
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

-- Assume that the DLLs are existing
local Win32 = libffi.loadlib("kernel32.dll")
Win32:addlibrary("advapi32.dll")
Win32:addlibrary("shell32.dll")
Win32:addlibrary("user32.dll")
BindWin32(Win32)

local PUBLIC_API = {
  -- UTF conversions
  utf8to16        = WIN32_utf8toutf16,
  utf16to8        = WIN32_utf16to8,
  pointertostring = WIN32_PointerToString,
  -- Registry
  newsam       = REG_NewSam,
  newoptions   = REG_NewOptions,
  regcreatekey = REG_RegCreateKey,
  regopenkey   = REG_RegOpenKey,
  regdeletekey = REG_RegDeleteKey,
  -- Miscellaneous
  getlasterror  = GetLastError,
  formatmessage = WIN32_FormatMessage,
  expandstrings = WIN32_ExpandEnvironmentStrings,
  shellexecute  = WIN32_ShellExecute,
  messagebox    = WIN32_MessageBox,
  -- High level
  openbrowser = WIN32_OpenBrowser
}

return PUBLIC_API
