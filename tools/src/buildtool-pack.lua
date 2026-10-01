--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- buildtool-pack.lua: the ComEXE ZIP builder (Lua manifest -> zip)
--
-- The manifest is a Lua file returning a list of entries:
--
--   { File = "source/path", Entry = "entry/name",    Date?, Mode?       }
--   { Tree = "source/dir",  Prefix = "entry/prefix", Exclude = { ... }? }
--
-- Try to be deterministic, default date (1980-01-01Z), sort name during
-- traversal

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local uv = require("luv")
local Mz = require("com.raw.minizipng")

local format = string.format
local sort   = table.sort
local append = table.insert

local fs_open         = uv.fs_open
local fs_read         = uv.fs_read
local fs_close        = uv.fs_close
local fs_stat         = uv.fs_stat
local fs_scandir      = uv.fs_scandir
local fs_scandir_next = uv.fs_scandir_next

local MZ_OK                      = Mz.MZ_OK
local MZ_OPEN_MODE_CREATE        = Mz.MZ_OPEN_MODE_CREATE
local MZ_OPEN_MODE_WRITE         = Mz.MZ_OPEN_MODE_WRITE
local MZ_VERSION_MADEBY          = Mz.MZ_VERSION_MADEBY
local MZ_ZIP_FLAG_UTF8           = Mz.MZ_ZIP_FLAG_UTF8
local MZ_COMPRESS_METHOD_DEFLATE = Mz.MZ_COMPRESS_METHOD_DEFLATE

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

local DEFAULT_DATE  = 315532800          -- 1980-01-01T00:00:00Z
local DEFAULT_MODE  = tonumber("644", 8) -- rw-r--r--
local DEFAULT_LEVEL = 9
local CHUNK_SIZE    = (64 * 1024)
local READ_MODE     = "r"

local DEFAULT_EXCLUDES = {
  "auto-dir-ok",
  ".gitkeep",
}

local EMPTY_ARRAY = {}

--------------------------------------------------------------------------------
-- UTILITIES                                                                  --
--------------------------------------------------------------------------------

local function ArrayToSet (Array)
  local NewSet = {}
  local Count  = #Array
  for Index = 1, Count do
    local Value = Array[Index]
    NewSet[Value] = true
  end
  return NewSet
end

--------------------------------------------------------------------------------
-- FILE WALKER                                                                --
--------------------------------------------------------------------------------

local function NewExcludeSet (ExtraExclude)
  -- Validate inputs
  assert((type(ExtraExclude) == "table"), "Exclude must be a list of names")
  -- Create a new set
  local NewSet = ArrayToSet(DEFAULT_EXCLUDES)
  -- Add extra excludes
  for Index = 1, #ExtraExclude do
    local Value = ExtraExclude[Index]
    NewSet[Value] = true
  end
  return NewSet
end

local function JoinPath (Left, Right)
  local Result
  if (Left == nil) or (Left == "") then
    Result = Right
  else
    Result = format("%s/%s", Left, Right)
  end
  return Result
end

local function CollectFilesRecursive (Directory, Relative, ExcludeSet, FileList)
  -- Start to scan directory
  local FileHandle, ScanErrorString = fs_scandir(Directory)
  if (not FileHandle) then
    error(format("cannot read directory %s: %s", Directory, ScanErrorString))
  end
  -- Collect names, sort them to be more deterministic
  local Names = {}
  local Name  = fs_scandir_next(FileHandle)
  while Name do
    append(Names, Name)
    Name = fs_scandir_next(FileHandle)
  end
  sort(Names)
  -- Process each entry
  for Index = 1, #Names do
    local DirEntryName = Names[Index]
    local FullPath     = JoinPath(Directory, DirEntryName)
    local EntryName    = JoinPath(Relative,  DirEntryName)
    local StatTable, StatErrorString = fs_stat(FullPath)
    if ExcludeSet[DirEntryName] then
      -- Skip (auto-dir-ok, .gitkeep, ...)
    elseif (StatTable == nil) then
      -- Unreadable or bad link
      error(format("cannot stat %s: %s", FullPath, StatErrorString))
    elseif (StatTable.type == "directory") then
      CollectFilesRecursive(FullPath, EntryName, ExcludeSet, FileList)
    elseif (StatTable.type == "file") then
      local NewFileEntry = { Source = FullPath, Entry = EntryName }
      append(FileList, NewFileEntry)
    else
      error(format("unsupported file type: %s (%s)", FullPath, StatTable.type))
    end
  end
end

local function CollectFiles (Directory, Relative, ExcludeSet)
  local FileList = {}
  CollectFilesRecursive(Directory, Relative, ExcludeSet, FileList)
  return FileList
end

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function WriteCurrentEntryContent (Writer, Filename)
  local FileHandle, OpenErrorString = fs_open(Filename, READ_MODE, 0)
  if (not FileHandle) then
    error(format("cannot open %s: %s", Filename, OpenErrorString))
  end
  -- Param -1 refer to the file current position
  local Chunk, ReadErrorString = fs_read(FileHandle, CHUNK_SIZE, -1)
  -- Try to read first chunk
  if (not Chunk) then
    fs_close(FileHandle)
    error(format("cannot read %s: %s", Filename, ReadErrorString))
  end
  while Chunk do
    -- Write ZIP chunk
    local BytesWritten, WriteErrorString = Mz.mz_zip_entry_write(Writer.Zip, Chunk)
    if (not BytesWritten) then
      fs_close(FileHandle)
      error(format("cannot write %s: %s", Filename, WriteErrorString))
    elseif (BytesWritten ~= #Chunk) then
      fs_close(FileHandle)
      error(format("short write on %s (wrote %d of %d)", Filename, BytesWritten, #Chunk))
    end
    -- Param -1 refer to the file current position
    local NextChunk, NextReadErrorString = fs_read(FileHandle, CHUNK_SIZE, -1)
    -- A failed read stops immediately
    if (NextChunk == nil) and (NextReadErrorString ~= nil) then
      fs_close(FileHandle)
      error(format("cannot read %s: %s", Filename, NextReadErrorString))
    end
    -- An empty read is the clean end of the file and stops the loop
    Chunk = NextChunk
    if (#Chunk == 0) then
      Chunk = nil
    end
  end
  fs_close(FileHandle)
end

local function AddFileEntry (Writer, Entry, Filename, EntryName, EntriesSeen)
  -- Validate inputs
  local StatTable = fs_stat(Filename)
  assert(StatTable, format("missing source file: %s", Filename))
  assert((EntriesSeen[EntryName] == nil), format("duplicate entry name: %s", EntryName))
  EntriesSeen[EntryName] = true
  -- Write entry information
  local Mode     = (Entry.Mode or DEFAULT_MODE)
  local External = (Mode << 16) -- Unix mode in the high 16 bits
  local FileInfo = Writer.FileInfo
  Mz.mz_zip_file_set_filename(FileInfo,           EntryName)
  Mz.mz_zip_file_set_modified_date(FileInfo,      Entry.Date or DEFAULT_DATE)
  Mz.mz_zip_file_set_version_madeby(FileInfo,     MZ_VERSION_MADEBY)
  Mz.mz_zip_file_set_flag(FileInfo,               MZ_ZIP_FLAG_UTF8)
  Mz.mz_zip_file_set_compression_method(FileInfo, MZ_COMPRESS_METHOD_DEFLATE)
  Mz.mz_zip_file_set_external_fa(FileInfo,        External)
  -- Open the entry in streaming mode
  local Code = Mz.mz_zip_entry_write_open(Writer.Zip, FileInfo, Writer.Level)
  if (Code ~= MZ_OK) then
    error(format("cannot add %s (mz error %d)", EntryName, Code))
  end
  -- Stream file contents into the ZIP entry
  WriteCurrentEntryContent(Writer, Filename)
  -- Close the ZIP entry
  Code = Mz.mz_zip_entry_close(Writer.Zip)
  if (Code ~= MZ_OK) then
    error(format("cannot close %s (mz error %d)", EntryName, Code))
  end
  Writer.Count = (Writer.Count + 1)
end

local function AddTreeEntries (Writer, Entry, EntriesSeen)
  local EntryExclude = (Entry.Exclude or EMPTY_ARRAY)
  local Excludes     = NewExcludeSet(EntryExclude)
  local FileList     = CollectFiles(Entry.Tree, "", Excludes)
  for Index = 1, #FileList do
    local File      = FileList[Index]
    local EntryName = JoinPath(Entry.Prefix, File.Entry)
    AddFileEntry(Writer, Entry, File.Source, EntryName, EntriesSeen)
  end
end

local function LoadManifest (ManifestFilename)
  local NewEnvironment = {}
  local Chunk, LoadErrorString = loadfile(ManifestFilename, "t", NewEnvironment)
  if (not Chunk) then
    error(format("cannot load manifest %s: %s", ManifestFilename, LoadErrorString))
  end
  local Success, Entries = pcall(Chunk)
  if (not Success) then
    local ErrorString = Entries
    error(format("manifest error in %s: %s", ManifestFilename, ErrorString))
  end
  return Entries
end

local function WriteZipArchive (Entries, OutputFilename, CompressionLevel)
  -- Create the required elements
  local Stream     = Mz.mz_stream_os_create()
  local Zip        = Mz.mz_zip_create()
  local Mode       = (MZ_OPEN_MODE_CREATE | MZ_OPEN_MODE_WRITE)
  local ReturnCode = Mz.mz_stream_os_open(Stream, OutputFilename, Mode)
  if (ReturnCode == MZ_OK) then
    ReturnCode = Mz.mz_zip_open(Zip, Stream, Mode)
  end
  if (ReturnCode ~= MZ_OK) then
    error(format("cannot create %s (mz error %d)", OutputFilename, ReturnCode))
  end
  -- Use the simpler older ZIP data descriptor format
  Mz.mz_zip_set_data_descriptor(Zip, false)
  -- New writer
  local NewWriter = {
    Zip      = Zip,
    Level    = CompressionLevel,
    FileInfo = Mz.mz_zip_file_create(),
    Count    = 0,
  }
  -- Store all the entries in EntriesSeen to ensure no duplicates
  local EntriesSeen = {}
  for Index = 1, #Entries do
    local Entry = Entries[Index]
    assert((type(Entry) == "table"), format("manifest entry %d is not a table", Index))
    if Entry.File then
      assert(Entry.Entry, format("manifest entry %d declares File without Entry", Index))
      AddFileEntry(NewWriter, Entry, Entry.File, Entry.Entry, EntriesSeen)
    elseif Entry.Tree then
      AddTreeEntries(NewWriter, Entry, EntriesSeen)
    else
      error(format("manifest entry %d expects either File or Tree", Index))
    end
  end
  -- Close the archive
  ReturnCode = Mz.mz_zip_close(Zip)
  if (ReturnCode ~= MZ_OK) then
    error(format("cannot close %s (mz error %d)", OutputFilename, ReturnCode))
  end
  -- Cleanup
  Mz.mz_stream_os_close(Stream)
  Mz.mz_stream_os_delete(Stream)
  Mz.mz_zip_file_delete(NewWriter.FileInfo)
  Mz.mz_zip_delete(Zip)
  -- Return written entries
  return NewWriter.Count
end

local function PACK_Main (Arguments)
  -- Unpack arguments
  local ManifestFilename = Arguments[1]
  local OutputFilename   = Arguments[2]
  local CompressionLevel = (tonumber(Arguments[3]) or DEFAULT_LEVEL)
  -- Validate inputs
  assert(ManifestFilename, "a manifest path is required")
  assert(OutputFilename,   "an output path is required")
  assert((CompressionLevel > 0) and (CompressionLevel <= 9), "a level between 1 and 9 is required")
  -- Load the manifest, then validate what it returned
  local Entries = LoadManifest(ManifestFilename)
  -- Validate manifest
  assert((type(Entries) == "table"), format("manifest must return a list of entries: %s", ManifestFilename))
  assert((#Entries > 0), format("manifest has no entries: %s", ManifestFilename))
  -- Pack the ZIP according to the manifest
  local Count     = WriteZipArchive(Entries, OutputFilename, CompressionLevel)
  local StatTable = fs_stat(OutputFilename)
  local SizeInBytes
  if StatTable then
    SizeInBytes = StatTable.size
  else
    SizeInBytes = 0
  end
  print(format("packed %s: %d entries, %d bytes", OutputFilename, Count, SizeInBytes))
  return 0
end

--------------------------------------------------------------------------------
-- PUBLIC INTERFACE                                                           --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  Run = PACK_Main,
}

return PUBLIC_API
