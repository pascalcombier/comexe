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
local gsub   = string.gsub
local remove = table.remove

local fs_open   = uv.fs_open
local fs_fstat  = uv.fs_fstat
local fs_read   = uv.fs_read
local fs_close  = uv.fs_close
local fs_write  = uv.fs_write
local fs_unlink = uv.fs_unlink
local fs_stat   = uv.fs_stat

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
local FILE_MODE = tonumber("600", 8)

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function SlurpFile (Filename)
  local FileHandle, OpenErrorString = fs_open(Filename, READ_MODE, 0)
  local Content
  local ReadErrorString
  if FileHandle then
    local StatTable, StatErrorString = fs_fstat(FileHandle)
    if StatTable then
      local SizeInBytes = StatTable.size
      if (SizeInBytes <= 0) then
        Content = ""
      else
        Content, ReadErrorString = fs_read(FileHandle, SizeInBytes, 0)
        if (not Content) then
          fs_close(FileHandle)
          error(format("cannot read %s: %s", Filename, ReadErrorString))
        end
      end
    else
      fs_close(FileHandle)
      error(format("cannot stat %s: %s", Filename, StatErrorString))
    end
    fs_close(FileHandle)
  else
    error(format("cannot open %s: %s", Filename, OpenErrorString))
  end
  return Content
end

local function WriteFile (Filename, Content)
  local FileHandle, OpenErrorString = fs_open(Filename, WRITE_MODE, FILE_MODE)
  if FileHandle then
    local BytesWritten, WriteErrorString = fs_write(FileHandle, Content, 0)
    fs_close(FileHandle)
    if (not BytesWritten) then
      fs_unlink(Filename)
      error(format("cannot write %s: %s", Filename, WriteErrorString))
    end
  else
    error(format("cannot open for writing %s: %s", Filename, OpenErrorString))
  end
end

--------------------------------------------------------------------------------
-- LUV CONCATENATION                                                          --
--------------------------------------------------------------------------------

local function CopyFileIntoHandle (OutputHandle, InputFilename)
  -- Open INPUT file
  local FileHandle, OpenErrorString = fs_open(InputFilename, READ_MODE, 0)
  assert(FileHandle, format("cannot open %s: %s", InputFilename, OpenErrorString))
  -- Read first data chunk, -1 means current file position
  local Chunk, ReadErrorString = fs_read(FileHandle, CHUNK_SIZE, -1)
  assert(Chunk, format("cannot read %s: %s", InputFilename, ReadErrorString))
  -- Read more chunks
  while (Chunk and (#Chunk > 0)) do
    -- Write the chunk, then read the next one
    local WrittenBytes, WriteErrorString = fs_write(OutputHandle, Chunk, -1)
    if (WrittenBytes) then
      local NextChunk, NextErrorString = fs_read(FileHandle, CHUNK_SIZE, -1)
      if NextChunk then
        Chunk = NextChunk
      else
        fs_close(FileHandle)
        error(format("cannot read %s: %s", InputFilename, NextErrorString))
      end
    else
      fs_close(FileHandle)
      error(format("cannot write (after %s): %s", InputFilename, WriteErrorString))
    end
  end
  fs_close(FileHandle)
end

local function FILEOPS_Concat (InputFilenames)
  -- Validate inputs
  local OutputFilename = remove(InputFilenames)
  assert((#InputFilenames >= 1), "at least one input file is required")
  assert((type(OutputFilename) == "string"), "output path must be a string")
  -- Open the output file in WRITE_MODE
  local OutputHandle, OpenErrorString = fs_open(OutputFilename, WRITE_MODE, FILE_MODE)
  assert(OutputHandle, format("cannot create %s: %s", OutputFilename, OpenErrorString))
  -- Copy all the input files into the output file
  for Index = 1, #InputFilenames do
    local InputFilename = InputFilenames[Index]
    assert((type(InputFilename) == "string"), format("input %d is not a path", Index))
    local StatTable = fs_stat(InputFilename)
    if (StatTable == nil) then
      fs_close(OutputHandle)
      fs_unlink(OutputFilename)
      error(format("missing input file: %s", InputFilename))
    end
    if (StatTable.type ~= "file") then
      fs_close(OutputHandle)
      fs_unlink(OutputFilename)
      error(format("not a regular file: %s", InputFilename))
    end
    CopyFileIntoHandle(OutputHandle, InputFilename)
  end
  fs_close(OutputHandle)
  return 0
end

--------------------------------------------------------------------------------
-- END OF LINE CONVERSIONS                                                    --
--------------------------------------------------------------------------------

local function ToUnixText (Content)
  local Intermediate = gsub(Content,      "\r\n", "\n")
  local Result       = gsub(Intermediate, "\r",   "\n")
  return Result
end

local function ToDosText (Content)
  local Intermediate = gsub(Content,      "\r\n", "\n")
  local Normalized   = gsub(Intermediate, "\r",   "\n")
  local Result       = gsub(Normalized,   "\n",   "\r\n")
  return Result
end

local function ConvertFile (Filename, ConvertFunction)
  local Content   = SlurpFile(Filename)
  local Converted = ConvertFunction(Content)
  local Result
  if (Converted == Content) then
    Result = "UNCHANGED"
  else
    WriteFile(Filename, Converted)
    Result = "CONVERTED"
  end
  return Result
end

local function ConvertFiles (FilenameList, ConvertFunction, ConvertLabel)
  -- Validate inputs
  assert((type(FilenameList) == "table") and (#FilenameList > 0), "at least one file is required")
  -- Process each file
  local Converted = 0
  for Index = 1, #FilenameList do
    local Filename = FilenameList[Index]
    local State    = ConvertFile(Filename, ConvertFunction)
    if (State == "CONVERTED") then
      Converted = (Converted + 1)
    end
    print(format("%s %s", State, Filename))
  end
  print(format("%s: %d files processed, %d converted", ConvertLabel, #FilenameList, Converted))
  return 0
end

local function FILEOPS_ConvertToUnix (FilenameList)
  return ConvertFiles(FilenameList, ToUnixText, "dos2unix")
end

local function FILEOPS_ConvertToDOS (FilenameList)
  return ConvertFiles(FilenameList, ToDosText, "unix2dos")
end

--------------------------------------------------------------------------------
-- PUBLIC INTERFACE                                                           --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  Concat = FILEOPS_Concat,
  ToUnix = FILEOPS_ConvertToUnix,
  ToDos  = FILEOPS_ConvertToDOS,
}

return PUBLIC_API
