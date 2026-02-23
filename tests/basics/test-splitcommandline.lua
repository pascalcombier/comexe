--------------------------------------------------------------------------------
-- TESTS BOILERPLATE FOR PACKAGE.PATH                                         --
--------------------------------------------------------------------------------

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
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime  = require("com.runtime")
local reporter = require("mini-reporter")

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local Reporter = reporter.new()

local function EXPECT_TABLE (TestCase, ResultValue, ExpectedValue)
  local Success = true
  if (type(ResultValue) ~= "table") or (type(ExpectedValue) ~= "table") then
    Success = false
  elseif (#ResultValue ~= #ExpectedValue) then
    Success = false
  else
    local Index = 1
    while (Index <= #ExpectedValue) do
      if (ResultValue[Index] ~= ExpectedValue[Index]) then
        Success = false
      end
      Index = (Index + 1)
    end
  end

  if (not Success) then
    local ResultStr   = table.concat(ResultValue or {}, ", ")
    local ExpectedStr = table.concat(ExpectedValue, ", ")
    Reporter:writef("TEST %s FAIL\n", TestCase)
    Reporter:writef("  GOT    [%s]\n", ResultStr)
    Reporter:writef("  EXPECT [%s]\n", ExpectedStr)
  end
  Reporter:expect(TestCase, Success)
end

local function EXPECT_ERROR (TestCase, ResultValue, ErrorMessage, ExpectedError)
  local Success = (ResultValue == nil) and (ErrorMessage == ExpectedError)
  if (not Success) then
    Reporter:writef("TEST %s FAIL\n", TestCase)
    Reporter:writef("  RESULT [%s]\n", tostring(ResultValue))
    Reporter:writef("  GOT    [%s]\n", tostring(ErrorMessage))
    Reporter:writef("  EXPECT [%s]\n", tostring(ExpectedError))
  end
  Reporter:expect(TestCase, Success)
end

--------------------------------------------------------------------------------
-- NOMINAL                                                                    --
--------------------------------------------------------------------------------

Reporter:block("NOMINAL")

-- 1: Simple splitting
local Args1, Err1 = Runtime.splitcommandline("word1 word2 word3")
EXPECT_TABLE("NOM-001-simple", Args1, {"word1", "word2", "word3"})

-- 2: Multiple spaces
local Args2, Err2 = Runtime.splitcommandline("  word1   word2  ")
EXPECT_TABLE("NOM-002-spaces", Args2, {"word1", "word2"})

-- 3: Single quotes
local Args3, Err3 = Runtime.splitcommandline("'single quoted arg' word2")
EXPECT_TABLE("NOM-003-single-quotes", Args3, {"single quoted arg", "word2"})

-- 4: Double quotes
local Args4, Err4 = Runtime.splitcommandline("\"double quoted arg\" word2")
EXPECT_TABLE("NOM-004-double-quotes", Args4, {"double quoted arg", "word2"})

-- 5: Backslash escape outside quotes
local Args5, Err5 = Runtime.splitcommandline("word\\ with\\ spaces word2")
EXPECT_TABLE("NOM-005-escape-outside", Args5, {"word with spaces", "word2"})

-- 6: Backslash escape inside double quotes
local Args6, Err6 = Runtime.splitcommandline("\"escaped \\\" quote\"")
EXPECT_TABLE("NOM-006-escape-inside-double", Args6, {"escaped \" quote"})

-- 7: Backslash does NOT escape inside single quotes
local Args7, Err7 = Runtime.splitcommandline("'no \\ escape'")
EXPECT_TABLE("NOM-007-no-escape-inside-single", Args7, {"no \\ escape"})

-- 8: Mixed quotes
local Args8, Err8 = Runtime.splitcommandline("prefix\"double'single\"suffix")
EXPECT_TABLE("NOM-008-mixed-quotes", Args8, {"prefixdouble'singlesuffix"})

-- 9: Space in double quotes
local Args9, Err9 = Runtime.splitcommandline("\"space\\ in\\ double\"")
EXPECT_TABLE("NOM-009-space-in-double", Args9, {"space in double"})

--------------------------------------------------------------------------------
-- ERRORS                                                                     --
--------------------------------------------------------------------------------

Reporter:block("ERRORS")

-- E1: Unmatched single quote
local ArgsE1, ErrE1 = Runtime.splitcommandline("'unmatched")
EXPECT_ERROR("ERR-001-unmatched-single", ArgsE1, ErrE1, "unmatched single quote")

-- E2: Unmatched double quote
local ArgsE2, ErrE2 = Runtime.splitcommandline("\"unmatched")
EXPECT_ERROR("ERR-002-unmatched-double", ArgsE2, ErrE2, "unmatched double quote")

-- E3: Unfinished escape
local ArgsE3, ErrE3 = Runtime.splitcommandline("unfinished\\")
EXPECT_ERROR("ERR-003-unfinished-escape", ArgsE3, ErrE3, "unfinished escape sequence")

--------------------------------------------------------------------------------
-- SUMMARY                                                                    --
--------------------------------------------------------------------------------

Reporter:summary()
