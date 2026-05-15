--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local uv = require("luv")

local format = string.format

--------------------------------------------------------------------------------
-- TEST DATA                                                                  --
--------------------------------------------------------------------------------

local Filename = "temp-test-hola-世界.lua"
local TestData = "Hello 世界! This is a test.\nLine 2"

--------------------------------------------------------------------------------
-- MAIN TEST                                                                  --
--------------------------------------------------------------------------------

print(format("Testing file: %s", Filename))

-- Write the file

local WriteFd = uv.fs_open(Filename, "w", tonumber("666", 8))
assert(WriteFd, "Failed to open file for writing")

local ByteWritten = uv.fs_write(WriteFd, TestData)
assert((ByteWritten == #TestData), "Not all bytes were written")

local Success = uv.fs_close(WriteFd)
assert(Success, "Failed to close file after writing")

-- Read the file

local ReadFd = uv.fs_open(Filename, "r", tonumber("666", 8))
assert(ReadFd, "Failed to open file for reading")

local StatResult = uv.fs_fstat(ReadFd)
assert(StatResult, "Failed to stat file")
assert(StatResult.size == #TestData, "File size doesn't match written data")

local ReadData = uv.fs_read(ReadFd, StatResult.size)
assert(ReadData, "Failed to read file")
assert(ReadData == TestData, "Read data doesn't match written data")

Success = uv.fs_close(ReadFd)
assert(Success, "Failed to close read handle")

-- Delete the file
Success = uv.fs_unlink(Filename)
assert(Success, "Failed to delete file")

print("OK")
