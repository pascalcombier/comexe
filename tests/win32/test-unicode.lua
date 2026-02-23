--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- Compare with luv conversions. luv provide functions to convert, but is not
-- suitable for Win32 because the created strings are not null-terminated. For
-- most cases in UTF-8 it's not a big deal, Lua strings adding a single
-- null-terminator in the implementation. But it's a big issue for UTF-16
-- strings, Windows API expecting a 2-byte terminator for strings, leading to
-- crashes.
--
-- Still we use luv strings in this test cases, to make sure the results are the
-- same (omitting the null terminator things.
--
-- ComEXE strings are always NULL terminated: either with a single 0x00 for
-- UTF-8 either with a double 0x00 for UTF-16.

--------------------------------------------------------------------------------
-- TESTS BOILERPLATE                                                          --
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
-- MODULE IMPORTS                                                             --
--------------------------------------------------------------------------------

local win32    = require("com.win32")
local uv       = require("luv")
local reporter = require("mini-reporter")

local format = string.format
local append = table.insert
local concat = table.concat
local byte   = string.byte

local utf8to16 = win32.utf8to16
local utf16to8 = win32.utf16to8

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local Reporter = reporter.new()

--------------------------------------------------------------------------------
-- TEST HIGH-LEVEL INTERFACE FROM win32.lua                                   --
--------------------------------------------------------------------------------

local function MakeHexString (String)
  local StringChunks = {}
  for Index = 1, #String do
    append(StringChunks, format("%02X", byte(String, Index)))
  end
  return concat(StringChunks, "")
end

local function PrintExpectedResults (StringUtf8, ComexeUtf16, ExpectedUtf16, ComexeUtf8, ExpectedUtf8)
  Reporter:writef("INPUT UTF8    ")
  Reporter:printf(MakeHexString(StringUtf8))
  Reporter:writef("GOT  RESULT 1 ")
  Reporter:printf(MakeHexString(ComexeUtf16))
  Reporter:writef("   EXPECTED 1 ")
  Reporter:printf(MakeHexString(ExpectedUtf16))
  Reporter:writef("GOT  RESULT 2 ")
  Reporter:printf(MakeHexString(ComexeUtf8))
  Reporter:writef("   EXPECTED 2 ")
  Reporter:printf(MakeHexString(ExpectedUtf8))
end

local function PerformConversionTest (StringUtf8)
  -- luv strings
  local UvUtf16 = uv.wtf8_to_utf16(StringUtf8)
  local UvUtf8  = uv.utf16_to_wtf8(UvUtf16)
  -- Expectations
  local ExpectedUtf16 = format("%s\x00\x00", UvUtf16)
  local ExpectedUtf8  = UvUtf8
  -- Our own conversion functions from win32.lua
  local ComexeUtf16 = utf8to16(StringUtf8)
  local ComexeUtf8  = utf16to8(UvUtf16)
  -- Results
  local Result = (ComexeUtf16 == ExpectedUtf16)
    and (ComexeUtf8 == ExpectedUtf8)
  if (not Result) then
    PrintExpectedResults(StringUtf8, ComexeUtf16, ExpectedUtf16, ComexeUtf8, ExpectedUtf8)
  end
  return Result
end

--------------------------------------------------------------------------------
-- TEST SCENARIOS                                                             --
--------------------------------------------------------------------------------

local UTF8_STRINGS = {
  "Hello, World! 你好，世界！",
  "hello",
  "héllo",
  "Привет",
  "你好",
  "emoji: \xF0\x9F\x98\x81",
  "",
}

Reporter:block("NOMINAL")

for Index = 1, #UTF8_STRINGS do
  local TestCase   = format("NOM-%03d", Index)
  local TestString = UTF8_STRINGS[Index]
  local Success    = PerformConversionTest(TestString)
  Reporter:expect(TestCase, Success)
end

--------------------------------------------------------------------------------
-- luv COMPATIBILITY                                                          --
--------------------------------------------------------------------------------

Reporter:block("COMPAT")

for Index = 1, #UTF8_STRINGS do
  local TestCase   = format("COMPAT-%03d", Index)
  local TestString = UTF8_STRINGS[Index]
  -- UvUtf16 is not terminated with 0x00 0x00
  local UvUtf16    = uv.wtf8_to_utf16(TestString)
  local ComExeUtf8 = utf16to8(UvUtf16)
  local Success    = (ComExeUtf8 == TestString)
  if (not Success) then
    -- Print diagnostic using reporter writef to keep output consistent
    Reporter:writef("INPUT %s\n", MakeHexString(TestString))
    Reporter:writef("GOT   %s\n", MakeHexString(ComExeUtf8))
    Reporter:writef("EXPECT%s\n", MakeHexString(TestString))
  end
  Reporter:expect(TestCase, Success)
end

--------------------------------------------------------------------------------
-- NEGATIVE TESTS (INVALID UTF-8)                                             --
--------------------------------------------------------------------------------

local INVALID_UTF8 = {
  "\xC3",                 -- truncated 2-byte sequence
  "\xE2\x82",             -- truncated 3-byte sequence
  "\xF0\x9F\x98",         -- truncated 4-byte (emoji) sequence
  "\xF8\x88\x80\x80\x80", -- 5-byte sequence (invalid for UTF-8)
}

Reporter:block("FAILURE")

for Index = 1, #INVALID_UTF8 do
  local TestCase                  = format("FAILURE-%03d", Index)
  local InvalidString             = INVALID_UTF8[Index]
  local StringUtf16, ErrorMessage = utf8to16(InvalidString)
  local Success                   = ((not StringUtf16) and ErrorMessage)
  Reporter:expect(TestCase, Success)
end

--------------------------------------------------------------------------------
-- SUMMARY                                                                    --
--------------------------------------------------------------------------------

Reporter:printf("== SUMMARY ==")
Reporter:summary("os.exit")
