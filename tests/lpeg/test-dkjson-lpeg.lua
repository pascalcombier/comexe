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
-- INFO                                                                       --
--------------------------------------------------------------------------------

-- This is a stupid micro-benchmark to show that dkjson+LPEG is faster that
-- dkjson alone if we have huge data set
--
-- It's not *that* significant, only 2 times faster. And in most cases, Lua's
-- match function will be faster, but PEG will be more general and we can reuse
-- existing grammar to parse things (Lua, , XML, C, Regular Expression, etc).
--
-- http://lua-users.org/wiki/LpegRecipes

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local format = string.format
local append = table.insert
local concat = table.concat

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function MakeTestData ()
  local Items = {}
  for Index = 1, 50000 do
    local Active
    if ((Index % 2) == 0) then
      Active = "true"
    else
      Active = "false"
    end
    local NewItem = format('{"id":%d,"name":"user%d","active":%s}', Index, Index, Active)
    append(Items, NewItem)
  end
  local ItemsString = concat(Items, ",")
  local JsonString  = format("[%s]", ItemsString)
  return JsonString
end

local TestData    = MakeTestData()
local DataSizeMiB = #TestData / (1024 * 1024)
print(format("Test data %.2f MiB", DataSizeMiB))

local function RunBenchmark (DkjsonModule)
  local StartTime  = os.clock()
  local Iterations = 30
  for Index = 1, Iterations do
    local Decoded, Position, ErrorMessage = DkjsonModule.decode(TestData, 1, nil)
  end
  local ElapsedSeconds = (os.clock() - StartTime)
  local MibPerSecond   = ((DataSizeMiB * Iterations) / ElapsedSeconds)
  return ElapsedSeconds, MibPerSecond
end

--------------------------------------------------------------------------------
-- TEST 1: DKJSON WITHOUT LPEG                                                --
--------------------------------------------------------------------------------

package.loaded["dkjson"] = nil
local TEST1_Dkjson = require("dkjson")

local TEST1_ElapsedSeconds, TEST1_MibPerSecond = RunBenchmark(TEST1_Dkjson)

--------------------------------------------------------------------------------
-- TEST 2: DKJSON WITH LPEG                                                   --
--------------------------------------------------------------------------------

package.loaded["dkjson"] = nil
local TEST2_Dkjson = require("dkjson")
TEST2_Dkjson = TEST2_Dkjson.use_lpeg()

local TEST2_ElapsedSeconds, TEST2_MibPerSecond = RunBenchmark(TEST2_Dkjson)

--------------------------------------------------------------------------------
-- TEST RESULTS                                                               --
--------------------------------------------------------------------------------

local FasterSuffixWithout = ""
local FasterSuffixWith    = ""

if (TEST2_ElapsedSeconds < TEST1_ElapsedSeconds) then
  local Ratio = TEST1_ElapsedSeconds / TEST2_ElapsedSeconds
  FasterSuffixWith = format(" (%.1fx faster)", Ratio)
else
  local Ratio = TEST2_ElapsedSeconds / TEST1_ElapsedSeconds
  FasterSuffixWithout = format(" (%.1fx faster)", Ratio)
end

print(format("DKJSON WITHOUT LPEG: %6.3f sec, %5.2f MiB/s%s", TEST1_ElapsedSeconds, TEST1_MibPerSecond, FasterSuffixWithout))
print(format("DKJSON WITH    LPEG: %6.3f sec, %5.2f MiB/s%s", TEST2_ElapsedSeconds, TEST2_MibPerSecond, FasterSuffixWith))
