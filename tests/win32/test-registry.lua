--------------------------------------------------------------------------------
-- TESTS BOILERPLATE FOR PACKAGE.PATH                                         --
--------------------------------------------------------------------------------

-- This kind of code should not appear in the real use of ComEXE
--
-- Initialize package.path to include ..\lib\xxx because test libraries are in
-- this directory

local function TEST_UpdatePackagePath (RelativeDirectory)
  -- Retrieve package confiuration (file loadlib.c, function luaopen_package)
  local Configuration = package.config
  local LUA_DIRSEP    = Configuration:sub(1, 1)
  local LUA_PATH_SEP  = Configuration:sub(3, 3)
  local LUA_PATH_MARK = Configuration:sub(5, 5)
  -- Load required modules
  local Runtime   = require("com.runtime")
  local Directory = Runtime.getrelativepath(RelativeDirectory) -- relative to arg[0] directory
  -- Prepend path in a Linux/Windows compatible way
  package.path = string.format("%s%s%s.lua%s%s", Directory, LUA_DIRSEP, LUA_PATH_MARK, LUA_PATH_SEP, package.path)
end

TEST_UpdatePackagePath("../lib")

--------------------------------------------------------------------------------
-- TESTS BOILERPLATE FOR PACKAGE.PATH                                         --
--------------------------------------------------------------------------------

local reporter = require("mini-reporter")
local Win32    = require("com.win32")

local format = string.format
local date   = os.date

local regcreatekey  = Win32.regcreatekey
local regopenkey    = Win32.regopenkey
local newsam        = Win32.newsam
local expandstrings = Win32.expandstrings

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local Reporter = reporter.new()

--------------------------------------------------------------------------------
-- CONSTANTS                                                                      --
--------------------------------------------------------------------------------

local SAM_READ            = newsam("KEY_READ")
local SAM_WRITE           = newsam("KEY_WRITE")
local SAM_READWRITE       = newsam("KEY_READ", "KEY_WRITE")
local SAM_KEY_QUERY_VALUE = newsam("KEY_QUERY_VALUE")
local SAM_ENUM_SUBKEYS    = newsam("KEY_ENUMERATE_SUB_KEYS", "KEY_QUERY_VALUE")

Reporter:block("CONSTANTS")

Reporter:expect("VALUE SAM_READ",            SAM_READ)
Reporter:expect("VALUE SAM_WRITE",           SAM_WRITE)
Reporter:expect("VALUE SAM_READWRITE",       SAM_READWRITE)
Reporter:expect("VALUE SAM_KEY_QUERY_VALUE", SAM_KEY_QUERY_VALUE)
Reporter:expect("VALUE SAM_ENUM_SUBKEYS",    SAM_ENUM_SUBKEYS)

Reporter:expect("TYPE SAM_READ",            type(SAM_READ)=="number")
Reporter:expect("TYPE SAM_WRITE",           type(SAM_WRITE)=="number")
Reporter:expect("TYPE SAM_READWRITE",       type(SAM_READWRITE)=="number")
Reporter:expect("TYPE SAM_KEY_QUERY_VALUE", type(SAM_KEY_QUERY_VALUE)=="number")
Reporter:expect("TYPE SAM_ENUM_SUBKEYS",    type(SAM_ENUM_SUBKEYS)=="number")

--------------------------------------------------------------------------------
-- NON EXISTING KEY                                                           --
--------------------------------------------------------------------------------

Reporter:block("NON EXISTING")

local NonExistingRootKey = [[HKEY_CURRENT_USER\Volatile Environment NOT EXISTING]]

local Key, ErrorMessage = regopenkey(NonExistingRootKey, SAM_READ)

if Key then
  Reporter:printf("LOG %s regopenkey SAM_READ got %q expected nil", NonExistingRootKey, Key)
end

Reporter:expect("NON-EXIST-1", (Key == nil))
Reporter:expect("NON-EXIST-2", (ErrorMessage))

if Key then
  Reporter:printf("LOG WARNING: regopenkey allowed open of non-existing key")
  Reporter:printf("LOG SHOULD NOT HAPPEN")
  Key:close()
end

--------------------------------------------------------------------------------
-- EXISTING VOLATILE KEY READ WRITE                                           --
--------------------------------------------------------------------------------

Reporter:block("VOLATILE/R")

local RootKey           = [[HKEY_CURRENT_USER\Volatile Environment]]
local Key, ErrorMessage = regopenkey(RootKey, SAM_READ)

Reporter:expect("VOL-READ-01", Key)
Reporter:expect("VOL-READ-02", (ErrorMessage == nil))

local Value, Type, ErrorString = Key:get("LOCALAPPDATA")
Reporter:printf("LOG Key:get LOCALAPPDATA returned %q type %q error %q", Value, Type, ErrorString)

Reporter:expect("VOL-READ-03", Value)
Reporter:expect("VOL-READ-04", type(Value) == "string")
Reporter:expect("VOL-READ-05", type(Type)  == "string")
Reporter:expect("VOL-READ-06", (Type == "REG_SZ"))
Reporter:expect("VOL-READ-07", (ErrorString == nil))

local Success, ErrorMessage = Key:close()

Reporter:expect("VOL-READ-08", Success)
Reporter:expect("VOL-READ-09", (ErrorMessage == nil))

--------------------------------------------------------------------------------
-- TEST READ WRITE                                                            --
--------------------------------------------------------------------------------

Reporter:block("VOLATILE/RW")

local RootKey           = [[HKEY_CURRENT_USER\Volatile Environment]]
local Key, ErrorMessage = regopenkey(RootKey, SAM_READWRITE)

Reporter:expect("VOL-READ-WRITE-01", Key)
Reporter:expect("VOL-READ-WRITE-02", (ErrorMessage == nil))

local function GetSetGetName (Name, Suffix)
  local Name = format("%s-%s", Name, Suffix)
  return Name
end

local function TestSetGet (Name, Value, WriteType, ReadType)
  local Success, ErrorMessage = Key:set(Name, Value, WriteType)
  Reporter:expect(GetSetGetName(Name, "01"), Success)
  Reporter:expect(GetSetGetName(Name, "02"), (ErrorMessage == nil))
  local GetValue, GetType, ErrorMessage = Key:get(Name)
  Reporter:expect(GetSetGetName(Name, "03"), GetValue)
  Reporter:expect(GetSetGetName(Name, "04"), GetType)
  Reporter:expect(GetSetGetName(Name, "05"), (ErrorMessage == nil))
  Reporter:expect(GetSetGetName(Name, "06"), (GetValue == Value))
  Reporter:expect(GetSetGetName(Name, "07"), (GetType == ReadType))
  if (GetType ~= ReadType) or (GetValue ~= Value) then
    Reporter:printf("LOG MISMATCH GOT %q %q EXPECTED %q %q", GetType, GetValue, ReadType, Value)
  end
  if (GetType == "REG_EXPAND_SZ") then
    Reporter:printf("LOG REG_EXPAND_SZ string %q", GetValue)
    local ExpandedValue = expandstrings(GetValue)
    Reporter:expect(GetSetGetName(Name, "08"), ExpandedValue)
    if ExpandedValue then
      Reporter:printf("LOG REG_EXPAND_SZ string %q", ExpandedValue)
    else
      Reporter:printf("LOG REG_EXPAND_SZ EXPAND FAILED")
    end
  end
end

-- Don't test REG_MULTI_SZ here for simplicity
local TEST_SET_GET = {
  { "REG_SZ",                   "Hello World 你好",        "REG_SZ"               },
  { "REG_EXPAND_SZ",            "Hello World 你好 %PATH%", "REG_EXPAND_SZ"        },
  { "REG_DWORD",                42,                        "REG_DWORD"            },
  { "REG_DWORD_LITTLE_ENDIAN",  42,                        "REG_DWORD"            },
  { "REG_DWORD_BIG_ENDIAN",     42,                        "REG_DWORD_BIG_ENDIAN" },
  { "REG_QWORD",                0xFF00FF00FF00FF00,        "REG_QWORD"            },
  { "REG_QWORD_LITTLE_ENDIAN",  0xFF00FF00FF00FF00,        "REG_QWORD"            },
}

for Index = 1, #TEST_SET_GET do
  local Entry = TEST_SET_GET[Index]
  local Name  = format("VOL-SET-GET-%02d", Index)
  local WriteType = Entry[1]
  local Value     = Entry[2]
  local ReadType  = Entry[3]
  TestSetGet(Name, Value, WriteType, ReadType)
end

-- REG_MULTI_SZ
local MultiString = { "Hello", "World", "你好" }
local Success, ErrorMessage = Key:set("COMEXE-REG-MULTI_SZ", MultiString, "REG_MULTI_SZ")
Reporter:expect("REG_MULTI_SZ-01", Success)
Reporter:expect("REG_MULTI_SZ-02", (ErrorMessage == nil))

for Index = 1, #MultiString do
  Reporter:printf("LOG SET REG_MULTI_SZ %d %q", Index, MultiString[Index])
end

-- Read back
local MultiStringRead, TypeRead, ErrorMessage = Key:get("COMEXE-REG-MULTI_SZ")
Reporter:expect("REG_MULTI_SZ-03", MultiStringRead)
Reporter:expect("REG_MULTI_SZ-04", type(MultiStringRead) == "table")
Reporter:expect("REG_MULTI_SZ-05", (#MultiStringRead == #MultiString))
Reporter:expect("REG_MULTI_SZ-06", (TypeRead == "REG_MULTI_SZ"))
Reporter:expect("REG_MULTI_SZ-07", (ErrorMessage == nil))

for Index = 1, #MultiStringRead do
  Reporter:printf("LOG GET REG_MULTI_SZ %d %q", Index, MultiStringRead[Index])
end

-- Compare written and read values
for Index = 1, #MultiStringRead do
  local PrintIndex = (7 + Index)
  local ExpectString = MultiString[Index]
  local ReadString   = MultiStringRead[Index]
  Reporter:expect(format("REG_MULTI_SZ-%02d", PrintIndex), (ReadString == ExpectString))
end

-- Close the key after tests
local Success, Code = Key:close()
Reporter:expect("VOL-CLOSE-01", Success)
Reporter:expect("VOL-CLOSE-02", (Code == nil))

--------------------------------------------------------------------------------
-- TEST ERROR REPORTING                                                       --
--------------------------------------------------------------------------------

Reporter:block("ERROR REPORTING")

local ReservedKey       = [[HKEY_LOCAL_MACHINE\SOFTWARE]]
local Key, ErrorMessage = regopenkey(ReservedKey, SAM_WRITE)

if Key then
  local Success, ErrorMessage = Key:close()
  Reporter:expect("ERROR-HANDLING-01", Success)
  Reporter:expect("ERROR-HANDLING-02", (ErrorMessage == nil))
  Reporter:printf("LOG WARNING: regopenkey allowed write access to reserved key")
else
  Reporter:expect("ERROR-HANDLING-03", (Key == nil))
  Reporter:expect("ERROR-HANDLING-04", (type(ErrorMessage) == "string"))
  Reporter:printf("LOG TRY %s %s %s", ReservedKey, tostring(Key), tostring(ErrorMessage))
end

local ReservedKey       = [[HKEY_LOCAL_MACHINE\SOFTWARE_NOT_EXIST]]
local Key, ErrorMessage = regopenkey(ReservedKey, SAM_WRITE)

if Key then
  Reporter:expect("ERROR-HANDLING-05", (ErrorMessage == nil))
  local Success, ErrorMessage = Key:close()
  Reporter:expect("ERROR-HANDLING-06", Success)
  Reporter:expect("ERROR-HANDLING-07", (ErrorMessage == nil))
  Reporter:printf("LOG WARNING - test environment allowed write access to reserved key")
else
  Reporter:expect("ERROR-HANDLING-08", (Key == nil))
  Reporter:expect("ERROR-HANDLING-09", (type(ErrorMessage) == "string"))
  Reporter:printf("LOG TRY %s %s %s", ReservedKey, tostring(Key), tostring(ErrorMessage))
end

--------------------------------------------------------------------------------
-- TEST ITERATE                                                               --
--------------------------------------------------------------------------------

local RootKey           = [[HKEY_CURRENT_USER\Volatile Environment]]
local Key, ErrorMessage = regopenkey(RootKey, SAM_KEY_QUERY_VALUE)

Reporter:expect("QUERY-01", Success)
Reporter:expect("QUERY-02", (ErrorMessage == nil))

local ValueCount = 0
local ValueIndex = 1

Reporter:block("ITERATE VALUES")
Reporter:printf("LOG # Iterate values %s", RootKey)

local function GetTypePrefix (Type)
  local Dict = {
    REG_NONE                = "NONE   ",
    REG_SZ                  = "STRING ",
    REG_EXPAND_SZ           = "STRING-X",
    REG_MULTI_SZ            = "STRING-M",
    REG_DWORD               = "DWORD   ",
    REG_DWORD_LITTLE_ENDIAN = "DWORD-LE",
    REG_DWORD_BIG_ENDIAN    = "DWORD-BE",
    REG_QWORD               = "QWORD   ",
    REG_QWORD_LITTLE_ENDIAN = "QWORD-LE",
  }
  local PrefixString = Dict[Type]
  if (PrefixString == nil) then
    PrefixString = "     ???"
  end
  return PrefixString
end

for Type, Name, Value in Key:values() do
  local TypePrefix = GetTypePrefix(Type)
  local Prefix      = format("%3.3d %s ", ValueIndex, TypePrefix)
  if (Type == "REG_NONE") then
    Reporter:printf("LOG %sNONE", Prefix)
  elseif (Type == "REG_SZ") or (Type == "REG_EXPAND_SZ") then
    local String = Value
    Reporter:printf("LOG %s%s %s %q", Prefix, Name, Type, String)
  elseif (Type == "REG_MULTI_SZ") then
    Reporter:printf("LOG %s%s %s", Prefix, Name, Type)
    local Array = Value
    for Index = 1, #Array do
      local String = Array[Index]
      -- print each multi-string element quoted for clarity
      Reporter:printf("LOG %s  [%d] %q", Prefix, Index, String)
    end
  elseif (Type == "REG_DWORD")
    or (Type == "REG_DWORD_LITTLE_ENDIAN")
    or (Type == "REG_DWORD_BIG_ENDIAN")
  then
    local UsedHexCount = 8
    local FormatHex    = format("0x%%0%dx", UsedHexCount)
    local HexString     = format(FormatHex, Value)
    Reporter:printf("LOG %s%s %d %s", Prefix, Name, Value, HexString)
  elseif (Type == "REG_QWORD") or (Type == "REG_QWORD_LITTLE_ENDIAN") then
    local UsedHexCount = 16
    local FormatHex    = format("0x%%0%dx", UsedHexCount)
    local HexString    = format(FormatHex, Value)
    Reporter:printf("LOG %s%s %d %s", Prefix, Name, Value, HexString)
  else
    Reporter:printf("LOG ERROR: unexpected type %s", tostring(Type))
  end
  -- Next
  ValueIndex = (ValueIndex + 1)
  ValueCount = (ValueCount + 1)
end

local Success, Code = Key:close()
Reporter:expect("ITERATE-CLOSE", Success)

if (ValueCount == 0) then
  Reporter:expect("ITERATE-VALUES-COUNT", (ValueCount > 0))
else
  Reporter:expect("ITERATE-VALUES-COUNT", (ValueCount > 0))
end

--------------------------------------------------------------------------------
-- TEST ITERATE KEYS                                                           
--------------------------------------------------------------------------------

Reporter:block("ITERATE KEYS")

local RootKey           = [[HKEY_CURRENT_USER\Volatile Environment]]
local Key, ErrorMessage = regopenkey(RootKey, SAM_ENUM_SUBKEYS)

Reporter:expect("ITERATE-KEYS-MAIN-01", Key)
Reporter:expect("ITERATE-KEYS-MAIN-02", (ErrorMessage == nil))

Reporter:printf("LOG # Iterate KEYS %s", RootKey)

local TestIndex  = 1
local SubKeyCount = 0

for Name in Key:keys() do
  Reporter:printf("LOG SubKey: [%s]", Name)
  Reporter:expect(format("ITERATE-KEYS-ITER-%02d", TestIndex), Name)
  TestIndex = (TestIndex + 1)
  Reporter:expect(format("ITERATE-KEYS-ITER-%02d", TestIndex), type(Name) == "string")
  SubKeyCount = (SubKeyCount + 1)
end

local Success, ErrorMessage = Key:close()
Reporter:expect("ITERATE-KEYS-MAIN-03", Success)
Reporter:expect("ITERATE-KEYS-MAIN-04", (ErrorMessage == nil))
Reporter:expect("ITERATE-KEYS-MAIN-05", (SubKeyCount > 0))

--------------------------------------------------------------------------------
-- TEST CREATE/DELETE KEY                                                     --
--------------------------------------------------------------------------------

local function FormatIsoDate ()
  return date("%Y-%m-%dT%H:%M:%S")
end

Reporter:block("CREATE/DELETE")

local Timestamp  = FormatIsoDate()

local TestSubKey = format("COMEXE_TEST_%s", Timestamp)
local FullKey    = format([[HKEY_CURRENT_USER\Volatile Environment\%s]], TestSubKey)

-- Create a non-volatile key in volatile parent => fail
local NewKey, ErrorMessage = regcreatekey(FullKey, SAM_READWRITE)
Reporter:expect("CREATE-FAIL-01", (NewKey       == nil))
Reporter:expect("CREATE-FAIL-02", (ErrorMessage ~= nil))

local VOLATILE = Win32.newoptions("REG_OPTION_VOLATILE")
Reporter:printf("LOG DEBUG VOLATILE %s", tostring(VOLATILE))

local NewKey, ErrorMessage = regcreatekey(FullKey, SAM_READWRITE, VOLATILE)
Reporter:expect("CREATE-NEWKEY-01", NewKey)
Reporter:expect("CREATE-NEWKEY-02", (ErrorMessage == nil))

-- Set a couple of values
local Success, ErrorMessage = NewKey:set("COMEXE-TEST-VALUE-1", "Value One 你好", "REG_SZ")
Reporter:expect("CREATE-NEWKEY-03", Success)
Reporter:expect("CREATE-NEWKEY-04", (ErrorMessage == nil))

local Success, ErrorMessage = NewKey:set("COMEXE-TEST-VALUE-2", 12345, "REG_DWORD")
Reporter:expect("CREATE-NEWKEY-05", Success)
Reporter:expect("CREATE-NEWKEY-06", (ErrorMessage == nil))

-- Verify values can be read back
local Value, Type, ErrorMessage = NewKey:get("COMEXE-TEST-VALUE-1")
Reporter:expect("CREATE-NEWKEY-07", (Value == "Value One 你好"))
Reporter:expect("CREATE-NEWKEY-08", (Type  == "REG_SZ"))
Reporter:expect("CREATE-NEWKEY-09", (ErrorMessage == nil))

local Value, Type, ErrorMessage = NewKey:get("COMEXE-TEST-VALUE-2")
Reporter:expect("CREATE-NEWKEY-10", (Value == 12345))
Reporter:expect("CREATE-NEWKEY-11", (Type  == "REG_DWORD"))
Reporter:expect("CREATE-NEWKEY-12", (ErrorMessage == nil))

-- Delete one value
local Success, ErrorMessage = NewKey:delete("COMEXE-TEST-VALUE-1")
Reporter:expect("CREATE-NEWKEY-13", Success)
Reporter:expect("CREATE-NEWKEY-14", (ErrorMessage == nil))

-- Verify deletion of the value: reading should return nil or error
local Value, Type, ErrorMessage = NewKey:get("COMEXE-TEST-VALUE-1")
Reporter:expect("CREATE-NEWKEY-14", (Value == nil))
Reporter:expect("CREATE-NEWKEY-15", (Type == nil))
Reporter:expect("CREATE-NEWKEY-16", (ErrorMessage ~= nil))

-- Close the key object
local Success, ErrorMessage = NewKey:close()
Reporter:expect("CREATE-NEWKEY-17", Success)
Reporter:expect("CREATE-NEWKEY-18", (ErrorMessage == nil))

-- Delete the key using our API
local Success, ErrorMessage = Win32.regdeletekey(FullKey)
Reporter:expect("CREATE-NEWKEY-19", Success)
Reporter:expect("CREATE-NEWKEY-20", (ErrorMessage == nil))

-- Verify deletion: opening must fail
local Key, ErrorMessage = regopenkey(FullKey, SAM_READ)
Reporter:expect("CREATE-NEWKEY-21", (Key == nil))
Reporter:expect("CREATE-NEWKEY-22", (ErrorMessage ~= nil))

--------------------------------------------------------------------------------
-- FORCE GARBAGE COLLECTOR                                                    --
--------------------------------------------------------------------------------

Reporter:block("FORCE GC")

Key = nil

for Index = 1, 10 do
  collectgarbage("collect")
end

Reporter:expect("NORMAL", true)

--------------------------------------------------------------------------------
-- SUMMARY                                                                    --
--------------------------------------------------------------------------------

Reporter:printf("== SUMMARY ==")
Reporter:summary("os.exit")
