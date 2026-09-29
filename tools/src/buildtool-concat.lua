--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- concat: concatenate EXE and ZIP together for "buildtool pack"
-- Shall manage Unicode filenames properly, even on on Windows

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local uv = require("luv")

local format = string.format

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

-- Read/write block
local CHUNK_SIZE = (64 * 1024)

-- libuv is always binary mode, never text mode
local READ_MODE  = "r"
local WRITE_MODE = "w"

--  Owner: read/write
--  Group: nothing
-- Others: nothing
local OUTPUT_MODE = tonumber("600", 8)

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function CopyFileIntoHandle (OutputHandle, InputFilename)
  -- Open INPUT file
  local FileHandle, OpenErrorString = uv.fs_open(InputFilename, READ_MODE, 0)
  assert(FileHandle, format("cannot open %s: %s", InputFilename, OpenErrorString))
  -- Read first data chunk, -1 means current file position
  local Chunk, ReadErrorString = uv.fs_read(FileHandle, CHUNK_SIZE, -1)
  assert(Chunk, format("cannot read %s: %s", InputFilename, ReadErrorString))
  -- Read more chunks
  while (Chunk and (#Chunk > 0)) do
    -- Write the chunk, then read the next one
    local WrittenBytes, WriteErrorString = uv.fs_write(OutputHandle, Chunk, -1)
    if (WrittenBytes) then
      local NextChunk, NextErrorString = uv.fs_read(FileHandle, CHUNK_SIZE, -1)
      if NextChunk then
        Chunk = NextChunk
      else
        uv.fs_close(FileHandle)
        error(format("cannot read %s: %s", InputFilename, NextErrorString))
      end
    else
      uv.fs_close(FileHandle)
      error(format("cannot write (after %s): %s", InputFilename, WriteErrorString))
    end
  end
  uv.fs_close(FileHandle)
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local function CONCAT_Run (InputFilenames, OutputFilename)
  -- Validate inputs
  assert((type(InputFilenames) == "table" and (#InputFilenames > 0)), "at least one input file is required")
  assert(type(OutputFilename) == "string", "output path must be a string")
  -- Open the output file in WRITE_MODE
  local OutputHandle, OpenErrorString = uv.fs_open(OutputFilename, WRITE_MODE, OUTPUT_MODE)
  assert(OutputHandle, format("cannot create %s: %s", OutputFilename, OpenErrorString))
  -- Copy all the input files into the output file
  for Index = 1, #InputFilenames do
    local InputFilename = InputFilenames[Index]
    assert(type(InputFilename) == "string", format("input %d is not a path", Index))
    local StatTable = uv.fs_stat(InputFilename)
    if (StatTable == nil) then
      uv.fs_close(OutputHandle)
      error(format("missing input file: %s", InputFilename))
    end
    if (StatTable.type ~= "file") then
      uv.fs_close(OutputHandle)
      error(format("not a regular file: %s", InputFilename))
    end
    CopyFileIntoHandle(OutputHandle, InputFilename)
  end
  uv.fs_close(OutputHandle)
  return 0
end

local PUBLIC_API = {
  Run = CONCAT_Run,
}

return PUBLIC_API
