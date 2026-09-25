--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local MiniZip = require("com.raw.minizipng")
local Runtime = require("com.runtime")

local format      = string.format
local stderr      = io.stderr
local newbuffer   = Runtime.newbuffer
local newpathname = Runtime.newpathname
local append      = Runtime.append
local readfile    = Runtime.readfile
local fileexists  = Runtime.fileexists
local listfiles   = Runtime.listfiles

-- Stream objects
local mz_stream_os_create = MiniZip.mz_stream_os_create
local mz_stream_os_open   = MiniZip.mz_stream_os_open
local mz_stream_os_close  = MiniZip.mz_stream_os_close
local mz_stream_os_delete = MiniZip.mz_stream_os_delete

-- Zip object
local mz_zip_create              = MiniZip.mz_zip_create
local mz_zip_delete              = MiniZip.mz_zip_delete
local mz_zip_open                = MiniZip.mz_zip_open
local mz_zip_close               = MiniZip.mz_zip_close
local mz_zip_set_data_descriptor = MiniZip.mz_zip_set_data_descriptor

-- Zip write
local mz_zip_entry_write_open = MiniZip.mz_zip_entry_write_open
local mz_zip_entry_write      = MiniZip.mz_zip_entry_write
local mz_zip_entry_close      = MiniZip.mz_zip_entry_close

-- Zip read
local mz_zip_goto_first_entry = MiniZip.mz_zip_goto_first_entry
local mz_zip_goto_next_entry  = MiniZip.mz_zip_goto_next_entry
local mz_zip_entry_get_info   = MiniZip.mz_zip_entry_get_info
local mz_zip_entry_read_open  = MiniZip.mz_zip_entry_read_open
local mz_zip_entry_read       = MiniZip.mz_zip_entry_read

-- mz_zip_file descriptor, on the C side, minizip-ng API is simply accessing
-- structure members directly. Here we have get/set functions
local mz_zip_file_create                 = MiniZip.mz_zip_file_create
local mz_zip_file_delete                 = MiniZip.mz_zip_file_delete
local mz_zip_file_set_filename           = MiniZip.mz_zip_file_set_filename
local mz_zip_file_set_modified_date      = MiniZip.mz_zip_file_set_modified_date
local mz_zip_file_set_version_madeby     = MiniZip.mz_zip_file_set_version_madeby
local mz_zip_file_set_flag               = MiniZip.mz_zip_file_set_flag
local mz_zip_file_set_compression_method = MiniZip.mz_zip_file_set_compression_method
local mz_zip_file_set_external_fa        = MiniZip.mz_zip_file_set_external_fa
local mz_zip_file_get_filename           = MiniZip.mz_zip_file_get_filename
local mz_zip_file_get_uncompressed_size  = MiniZip.mz_zip_file_get_uncompressed_size

-- minizip-ng constants
local MZ_OK                      = MiniZip.MZ_OK
local MZ_MEM_ERROR               = MiniZip.MZ_MEM_ERROR
local MZ_END_OF_LIST             = MiniZip.MZ_END_OF_LIST
local MZ_OPEN_MODE_READ          = MiniZip.MZ_OPEN_MODE_READ
local MZ_OPEN_MODE_WRITE         = MiniZip.MZ_OPEN_MODE_WRITE
local MZ_OPEN_MODE_CREATE        = MiniZip.MZ_OPEN_MODE_CREATE
local MZ_COMPRESS_METHOD_STORE   = MiniZip.MZ_COMPRESS_METHOD_STORE
local MZ_COMPRESS_METHOD_DEFLATE = MiniZip.MZ_COMPRESS_METHOD_DEFLATE
local MZ_ZIP_FLAG_UTF8           = MiniZip.MZ_ZIP_FLAG_UTF8
local MZ_VERSION_MADEBY          = MiniZip.MZ_VERSION_MADEBY

-- Compression, zlib values registered from C by the raw binding
local Z_DEFAULT_COMPRESSION = MiniZip.Z_DEFAULT_COMPRESSION
local Z_NO_COMPRESSION      = MiniZip.Z_NO_COMPRESSION
local Z_BEST_COMPRESSION    = MiniZip.Z_BEST_COMPRESSION

-- Writer policy: fixed timestamp, external FA stands for external file attributes
-- WRITER_DATE is local midnight, not 1980-01-01T00:00:00Z
local WRITER_TIME               = { year = 1980, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
local WRITER_DATE               = os.time(WRITER_TIME)
local WRITER_MODE               = tonumber("644", 8)  -- rw-r--r--
local WRITER_EXTERNAL_FA        = (WRITER_MODE << 16) -- unix mode in the high 16 bits
local WRITER_LEVEL_WHEN_DEFAULT = Z_BEST_COMPRESSION
local READER_BUFFER_CAPACITY    = (64 * 1024) -- 64 KiB

--------------------------------------------------------------------------------
-- ARCHIVE OPEN/CLOSE                                                         --
--------------------------------------------------------------------------------

local function ZIP_OpenRead (ZipFilename)
  -- Local data
  local NewStream  = mz_stream_os_create()
  local NewZipFile = mz_zip_create()
  local NewReader
  local ErrorString
  -- Check NewStream and NewZipFile
  local Result = MZ_MEM_ERROR
  if NewStream and NewZipFile then
    Result = mz_stream_os_open(NewStream, ZipFilename, MZ_OPEN_MODE_READ)
    if (Result == MZ_OK) then
      Result = mz_zip_open(NewZipFile, NewStream, MZ_OPEN_MODE_READ)
    end
  end
  -- Evaluate the result
  if (Result == MZ_OK) then
    NewReader = {
      ZipFile = NewZipFile,
      Stream  = NewStream,
      Buffer  = newbuffer(READER_BUFFER_CAPACITY),
    }
  else
    ErrorString = format("Failed to open ZIP file [%s] (mz error %d)", ZipFilename, Result)
    mz_zip_delete(NewZipFile)
    mz_stream_os_delete(NewStream)
  end
  -- Return values
  return NewReader, ErrorString
end

local function ZIP_CloseRead (Reader)
  -- Retrieve data
  local ZipFile = Reader.ZipFile
  local Stream  = Reader.Stream
  local Result
  if ZipFile then
    Result = mz_zip_close(ZipFile)
    mz_zip_delete(ZipFile)
    Reader.ZipFile = nil
  end
  if Stream then
    mz_stream_os_close(Stream)
    mz_stream_os_delete(Stream)
    Reader.Stream = nil
  end
  -- Release buffer, which has its own __gc
  Reader.Buffer = nil
  -- Return value
  return Result
end

local function ZIP_ReadOpenedEntry (Reader, SizeInBytes)
  -- Local data
  local Buffer = Reader.Buffer
  local FileContent
  if (SizeInBytes > 0) then
    Buffer:ensurecapacity(SizeInBytes)
    local BytesRead = mz_zip_entry_read(Reader.ZipFile, Buffer:getpointer(), SizeInBytes)
    if (BytesRead == SizeInBytes) then
      FileContent = Buffer:read(1, BytesRead)
    end
  elseif (SizeInBytes == 0) then
    FileContent = ""
  end
  -- Return value
  return FileContent
end

--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS                                                            --
--------------------------------------------------------------------------------

local function ZIP_HandleFile (Reader, FileInfo, EntryCallback)
  -- Local variables
  local Continue  = true
  local ZipFile   = Reader.ZipFile
  local EntryName = mz_zip_file_get_filename(FileInfo)
  local EntrySize = mz_zip_file_get_uncompressed_size(FileInfo)
  local ErrorString
  -- Provide a function to stop iteration
  local function StopIterationFunction ()
    Continue = false
  end
  -- Provide a function to read content if necessary
  local function ReadFunction ()
    local OpenResult = mz_zip_entry_read_open(ZipFile)
    local FileContent
    if (OpenResult == MZ_OK) then
      -- Read the entire file through the reader buffer
      FileContent = ZIP_ReadOpenedEntry(Reader, EntrySize)
      -- mz_zip_entry_close can actually fail due to CRC mismatch
      local CloseResult = mz_zip_entry_close(ZipFile)
      if (CloseResult ~= MZ_OK) then
        FileContent = nil
        ErrorString = format("Failed to verify entry [%s] (mz error %d)", EntryName, CloseResult)
      end
    end
    -- Return value
    return FileContent
  end
  -- Call the entry function
  EntryCallback(EntryName, ReadFunction, StopIterationFunction)
  -- Return the continue status
  return Continue, ErrorString
end

local function ZIP_IterateRead (ZipFilename, EntryFunc)
  -- Local data
  local Success = false
  local ErrorString
  -- Open the ZIP file for reading
  local Reader, OpenError = ZIP_OpenRead(ZipFilename)
  assert(Reader, OpenError)
  local ZipFile  = Reader.ZipFile
  -- Iterate
  local Continue = (mz_zip_goto_first_entry(ZipFile) == MZ_OK)
  while Continue do
    -- Get current file info
    local FileInfo, FileError = mz_zip_entry_get_info(ZipFile)
    if FileInfo then
      -- Handle the current file
      local EntryErrorString
      Continue, EntryErrorString = ZIP_HandleFile(Reader, FileInfo, EntryFunc)
      if EntryErrorString then
        ErrorString = EntryErrorString
      end
      -- Try to go to next file
      if Continue then
        local NextResult = mz_zip_goto_next_entry(ZipFile)
        if (NextResult == MZ_END_OF_LIST) then
          Continue = false
          Success  = true
        elseif (NextResult ~= MZ_OK) then
          Continue = false
        end
      end
    else
      ErrorString = format("Failed to get current entry info (mz error %d)", FileError)
      Continue    = false
    end
  end
  -- If we finished the loop without errors, it's successful
  Success = (not Continue) and (not ErrorString)
  -- Ignore the return value of the reader close
  ZIP_CloseRead(Reader)
  -- Return values
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- TYPE ARCHIVE READER                                                        --
--------------------------------------------------------------------------------

local function ZIPR_MethodClose (ReaderObject)
  -- Retrieve handle
  local Reader = ReaderObject.Reader
  local Result
  if Reader then
    Result = ZIP_CloseRead(Reader)
    ReaderObject.Reader = nil
  end
  -- Return value
  return Result
end

local function ZIPR_MethodRead (ReaderObject, EntryName)
  -- Local variables
  local FileContent
  local Reader = ReaderObject.Reader
  assert(Reader, "API misuse: Read after close")
  local ZipFile = Reader.ZipFile
  -- Reset to beginning
  local Status   = mz_zip_goto_first_entry(ZipFile)
  local Continue = (Status == MZ_OK)
  -- Iterate through files
  while Continue do
    local FileInfo = mz_zip_entry_get_info(ZipFile)
    if FileInfo then
      if (mz_zip_file_get_filename(FileInfo) == EntryName) then
        local OpenResult = mz_zip_entry_read_open(ZipFile)
        if (OpenResult == MZ_OK) then
          FileContent = ZIP_ReadOpenedEntry(Reader, mz_zip_file_get_uncompressed_size(FileInfo))
          -- mz_zip_entry_close can actually fail due to CRC mismatch
          local CloseResult = mz_zip_entry_close(ZipFile)
          if (CloseResult ~= MZ_OK) then
            FileContent = nil
          end
        end
        Continue = false
      else
        -- Go to next file
        Status   = mz_zip_goto_next_entry(ZipFile)
        Continue = (Status == MZ_OK)
      end
    else
      Continue = false -- mz_zip_entry_get_info returned an error code
    end
  end
  -- Return value
  return FileContent
end

local ZIPR_Metatable = {
  -- METATABLE_LuaDefinedMethods
  __gc = ZIPR_MethodClose,
  -- METATABLE_UserDefinedMethods
  __index = {
    Read  = ZIPR_MethodRead,
    Close = ZIPR_MethodClose,
  }
}

local function ZIP_NewReader (ZipFilename)
  -- Result variables
  local NewReaderObject
  -- Open the ZIP file for reading
  local Reader, ErrorString = ZIP_OpenRead(ZipFilename)
  -- Only proceed if zip opening succeeded
  if Reader then
    -- Create a new reader object
    NewReaderObject = {
      Reader = Reader
    }
    -- Attach the metatable
    setmetatable(NewReaderObject, ZIPR_Metatable)
  end
  -- Return the reader object and error message
  return NewReaderObject, ErrorString
end

--------------------------------------------------------------------------------
-- TYPE ARCHIVE WRITER                                                        --
--------------------------------------------------------------------------------

local function ZIPW_MethodClose (WriterObject)
  -- Retrieve data
  local ZipFile = WriterObject.ZipFile
  if ZipFile then
    -- Close the zip file
    local CloseResult = mz_zip_close(ZipFile)
    mz_zip_delete(ZipFile)
    mz_stream_os_close(WriterObject.Stream)
    mz_stream_os_delete(WriterObject.Stream)
    mz_zip_file_delete(WriterObject.FileInfo)
    -- Mark as closed
    WriterObject.ZipFile  = nil
    WriterObject.Stream   = nil
    WriterObject.FileInfo = nil
    -- Return the result for potential error checking
    return CloseResult
  end
end

local function ZIPW_MethodWriteEntry (WriterObject, EntryName, FileContents)
  -- Retrieve data
  local ZipFile          = WriterObject.ZipFile
  local FileInfo         = WriterObject.FileInfo
  local CompressionLevel = WriterObject.CompressionLevel
  -- Error handling
  assert(ZipFile,                          "API: Write after close")
  assert((type(EntryName) == "string"),    "EntryName must be a string")
  assert((type(FileContents) == "string"), "FileContents must be a string")
  -- Entry description
  mz_zip_file_set_filename(FileInfo,           EntryName)
  mz_zip_file_set_modified_date(FileInfo,      WriterObject.Date)
  mz_zip_file_set_version_madeby(FileInfo,     WriterObject.VersionMadeBy)
  mz_zip_file_set_flag(FileInfo,               MZ_ZIP_FLAG_UTF8)
  mz_zip_file_set_compression_method(FileInfo, WriterObject.CompressionMethod)
  mz_zip_file_set_external_fa(FileInfo,        WriterObject.ExternalAttributes)
  -- Open the new entry in the zip
  local Result = mz_zip_entry_write_open(ZipFile, FileInfo, CompressionLevel)
  local ErrorString
  if (Result == MZ_OK) then
    -- mz_zip_entry_write returns the number of bytes written
    local WrittenBytes = mz_zip_entry_write(ZipFile, FileContents)
    if (WrittenBytes == #FileContents) then
      -- Close file in zip
      local CloseResult = mz_zip_entry_close(ZipFile)
      if (CloseResult ~= MZ_OK) then
        ErrorString = format("Failed to close file in zip (mz error %d)", CloseResult)
      end
    else
      ErrorString = format("Failed to write data to zip (mz error %d)", WrittenBytes)
    end
  else
    ErrorString = format("Failed to create new file in zip (mz error %d)", Result)
  end
  -- Evaluate success
  local Success = (ErrorString == nil)
  return Success, ErrorString
end

local ZIPW_Metatable = {
  -- METATABLE_LuaDefinedMethods
  __gc = ZIPW_MethodClose,
  -- METATABLE_UserDefinedMethods
  __index = {
    Close      = ZIPW_MethodClose,
    WriteEntry = ZIPW_MethodWriteEntry
  }
}

local function ZIP_NewWriter (ZipFilename, OptionalCompressionLevel)
  -- Result variables
  local NewWriterObject
  local ErrorString
  local CompressionLevel  = (OptionalCompressionLevel or Z_BEST_COMPRESSION)
  local CompressionMethod = MZ_COMPRESS_METHOD_DEFLATE
  local RealLevel         = CompressionLevel
  -- API misuse check
  assert((CompressionLevel == Z_DEFAULT_COMPRESSION) or ((CompressionLevel >= Z_NO_COMPRESSION) and (CompressionLevel <= Z_BEST_COMPRESSION)), "API misuse: compression level must be -1 or 0..9")
  if (CompressionLevel == Z_NO_COMPRESSION) then
    CompressionMethod = MZ_COMPRESS_METHOD_STORE
    RealLevel         = 0
  elseif (CompressionLevel == Z_DEFAULT_COMPRESSION) then
    RealLevel = WRITER_LEVEL_WHEN_DEFAULT
  end
  -- Open the file stream, then the archive
  local Mode     = (MZ_OPEN_MODE_CREATE | MZ_OPEN_MODE_WRITE)
  local Stream   = mz_stream_os_create()
  local ZipFile  = mz_zip_create()
  local FileInfo = mz_zip_file_create()
  -- Check results
  local Result = MZ_MEM_ERROR
  if Stream and ZipFile and FileInfo then
    Result = mz_stream_os_open(Stream, ZipFilename, Mode)
    if (Result == MZ_OK) then
      Result = mz_zip_open(ZipFile, Stream, Mode)
    end
  end
  -- Only proceed if zip creation succeeded
  if (Result == MZ_OK) then
    -- Deterministic archives
    mz_zip_set_data_descriptor(ZipFile, false)
    -- Create a new writer object
    NewWriterObject = {
      ZipFile            = ZipFile,
      Stream             = Stream,
      FileInfo           = FileInfo,
      CompressionLevel   = RealLevel,
      CompressionMethod  = CompressionMethod,
      Date               = WRITER_DATE,
      ExternalAttributes = WRITER_EXTERNAL_FA,
      VersionMadeBy      = MZ_VERSION_MADEBY,
    }
    -- Attach the metatable
    setmetatable(NewWriterObject, ZIPW_Metatable)
  else
    ErrorString = format("Failed to create ZIP file [%s] (mz error %d)", ZipFilename, Result)
    mz_zip_delete(ZipFile)
    mz_stream_os_delete(Stream)
    mz_zip_file_delete(FileInfo)
  end
  -- Return the writer object and error message
  return NewWriterObject, ErrorString
end

--------------------------------------------------------------------------------
-- ZIP MERGER                                                                 --
--------------------------------------------------------------------------------

-- Add an explicit entry to the ZIP
local function ZIPM_MergerAddEntry (Merger, ZipEntryName, FileContents)
  -- Validate inputs
  assert((type(ZipEntryName) == "string"), "ZipEntryName must be a string")
  assert((type(FileContents) == "string"), "FileContents must be a string")
  -- Create the new entry
  local NewEntry = {
    name    = ZipEntryName,
    content = FileContents
  }
  -- Store the new entry
  local Entries = Merger.Entries
  append(Entries, NewEntry)
end

-- SourcePath: the path to the directory or ZIP file
-- SourceType: "dir" or "zip"
--
-- SourceType is not inferred from SourcePath. At the beginning we were checking
-- the file extension and directory existence to decide if it was "dir" or
-- "zip".  But this was actually a bad idea. We actually use it from
-- extented-commands were we actually use an EXE file as it was a ZIP file.
--
-- Return a new source
local function ZIPM_MergerAddSource (Merger, SourcePath, SourceType)
  -- Validate inputs
  assert((type(SourcePath) == "string"), "SourcePath must be a string")
  assert((type(SourceType) == "string"), "SourceType must be a string")
  assert((SourceType == "dir") or (SourceType == "zip"), "SourceType must be 'dir', 'zip'")
  -- Convert pathname to native
  local SourcePathname = newpathname(SourcePath)
  local NativePathname = tostring(SourcePathname)
  -- Store the source
  local NewSource = {
    type = SourceType,
    path = NativePathname
  }
  -- Store the source
  local Sources = Merger.Sources
  append(Sources, NewSource)
  local NewSourceId = #Sources
  -- Return value
  return NewSourceId
end

-- Add a rule for a source
-- action: "COPY" or "SKIP"
local function ZIPM_MergerAddRule (Merger, SourceId, Pattern, Action)
  assert((Action == "COPY") or (Action == "SKIP"), "action must be COPY or SKIP")
  -- Create the new rule
  local NewRule = {
    sourceId = SourceId,
    pattern  = Pattern,
    action   = Action
  }
  -- Store the rule
  local Rules = Merger.Rules
  append(Rules, NewRule)
end

-- Determine the action for a given source entry: return "COPY" or "SKIP"
local function ZIP_GetActionForEntry (Merger, SourceId, EntryName)
  -- Retrieve data
  local Rules = Merger.Rules
  -- Check all rules for this source
  local Index = 1
  local Action
  while (Action == nil) and (Index <= #Rules) do
    local Rule         = Rules[Index]
    local RuleSourceId = Rule.sourceId
    if (RuleSourceId == SourceId) then
      local RulePattern = Rule.pattern
      local RuleAction  = Rule.action
      if EntryName:match(RulePattern) then
        Action = RuleAction
      end
    end
    Index = (Index + 1)
  end
  -- Validate outputs
  assert(Action, format("no matching rule for entry %q (source id %q)", EntryName, SourceId))
  -- Return value
  return Action
end

-- Write a ZIP entry, warn about duplicates
local function ZIPM_WriteEntry (Writer, EntryName, EntryContent, EntriesSet)
  -- Validate inputs
  assert(type(EntryName)    == "string", "EntryName must be a string")
  assert(type(EntryContent) == "string", "EntryContent must be a string")
  -- If already present, print to stderr and set error (do not perform an early return)
  if EntriesSet[EntryName] then
    local Message = format("WARNING: duplicate entry: %s\n", EntryName)
    stderr:write(Message)
  end
  -- Write the ZIP Entry
  local Success, ErrorString = Writer:WriteEntry(EntryName, EntryContent)
  if Success then
    EntriesSet[EntryName] = true -- Duplicate detection
  end
  -- Return value
  return Success, ErrorString
end

-- Tricky: importing a directory treats that directory as the ZIP root and so
-- we need to remove the source-root path components from each entry.
--
-- Example: SourcePath "DIR-1" and file "DIR-1/DIR-2/file.txt" -> "DIR-2/file.txt"
local function ZIPM_ImportDirectory (Merger, Writer, SourceId, SourcePath, EntriesSet)
  local SourceRootPath  = newpathname(SourcePath)
  local SourceRootDepth = SourceRootPath:depth()
  -- local callback
  local function ProcessFile (NativePathname, FileType)
    if (FileType == "file") then
      local FilePathname = newpathname(NativePathname)
      -- Remove source root components to build the ZIP entry
      FilePathname:remove(1, SourceRootDepth)
      -- Convert
      local ZipEntryName = FilePathname:tointernal()
      -- Check the action for this entry
      local Action = ZIP_GetActionForEntry(Merger, SourceId, ZipEntryName)
      if (Action == "COPY") then
        local FileContent = readfile(NativePathname, "string")
        if FileContent then
          local Success, ErrorString = ZIPM_WriteEntry(Writer, ZipEntryName, FileContent, EntriesSet)
          if Success then
            Merger:verboselog("%s -> %s", NativePathname, ZipEntryName)
          else
            local Error = format("Failed to write entry [%s] from directory [%s]: %s\n", ZipEntryName, SourcePath, ErrorString)
            stderr:write(Error)
          end
        else
          print(format("ERROR reading file: %s", NativePathname))
        end
      end
    end
  end
  -- Start the file iterator
  Merger:verboselog("PROCESSING DIR [%s]", SourcePath)
  listfiles(SourcePath, ProcessFile)
end

local function ZIPM_ImportZipFile (Merger, Writer, SourceId, ZipFilename, EntriesSet)
  -- Local callback
  local function ProcessZipEntry (ZipEntryname, ReadFunction, StopFunction)
    local EntryAction = ZIP_GetActionForEntry(Merger, SourceId , ZipEntryname)
    if (EntryAction == "COPY") then
      local ZipEntryContent = ReadFunction()
      if ZipEntryContent then
        local WriteSuccess, WriteErrorString = ZIPM_WriteEntry(Writer, ZipEntryname, ZipEntryContent, EntriesSet)
        if WriteSuccess then
          Merger:verboselog("%s", ZipEntryname)
        else
          local Error = format("ERROR copying entry [%s] from ZIP [%s]: %s\n", ZipEntryname, ZipFilename, WriteErrorString)
          stderr:write(Error)
        end
      else
        print(format("ERROR reading entry [%s] from ZIP [%s]", ZipEntryname, ZipFilename))
      end
    end
  end
  -- Iterate through all the entries of the ZIP file
  Merger:verboselog("PROCESSING ZIP [%s]", ZipFilename)
  local Success, ErrorString = ZIP_IterateRead(ZipFilename, ProcessZipEntry)
  if (not Success) then
    print(format("ERROR processing ZIP file [%s]: %s", ZipFilename, ErrorString))
  end
end

local function ZIPM_MethodWriteZip (Merger)
  -- Retrieve data
  local ZipFilename      = Merger.ZipFilename
  local CompressionLevel = Merger.CompressionLevel
  local Entries          = Merger.Entries
  local Sources          = Merger.Sources
  local EntriesSet       = Merger.EntriesSet
  -- Create a new zip file for writing (overwrite if exists)
  local Writer, ErrorString = ZIP_NewWriter(ZipFilename, CompressionLevel)
  assert(Writer, format("Failed to create ZIP file [%s]: %s", ZipFilename, ErrorString))
  -- Write all specific entries first
  if (#Entries > 0) then
    Merger:verboselog("PROCESSING SPECIAL ENTRIES")
  end
  for Index, Entry in ipairs(Entries) do
    local EntryName    = Entry.name
    local EntryContent = Entry.content
    local Success, ErrorString = ZIPM_WriteEntry(Writer, EntryName, EntryContent, EntriesSet)
    if ErrorString then
      print(format("ERROR writing entry [%s]: %s", EntryName, ErrorString))
    else
      Merger:verboselog("%s", EntryName)
    end
  end
  -- Process all sources
  for SourceId, Source in ipairs(Sources) do
    local SourceType = Source.type
    local SourcePath = Source.path
    if (SourceType == "dir") then
      ZIPM_ImportDirectory(Merger, Writer, SourceId, SourcePath, EntriesSet)
    elseif (SourceType == "zip") then
      if fileexists(SourcePath) then
        ZIPM_ImportZipFile(Merger, Writer, SourceId, SourcePath, EntriesSet)
      else
        print(format("ERROR: ZIP file not found: %s", SourcePath))
      end
    end
  end
  -- Close the writer
  Merger:verboselog("ZIP write operation completed: %s", ZipFilename)
  Writer:Close()
end

local ZIPM_Metatable = {
  -- custom methods
  __index = {
    AddEntry  = ZIPM_MergerAddEntry,
    AddSource = ZIPM_MergerAddSource,
    AddRule   = ZIPM_MergerAddRule,
    WriteZip  = ZIPM_MethodWriteZip
  }
}

---@diagnostic disable-next-line: unused-local
local function ZIPM_MethodLogVerbose (ZipMerger, ...)
  local FormattedString = format(...)
  print(FormattedString)
end

local function ZIPM_MethodLogDummy (...)
  -- Don't print anything: non-verbose, default
end

local function ZIP_NewMerger (ZipFilename, CompressionLevel, Options)
  -- Create the new merger
  local NewZipMerger = {
    ZipFilename      = ZipFilename,
    CompressionLevel = (CompressionLevel or Z_DEFAULT_COMPRESSION),
    Entries          = {},
    EntriesSet       = {},
    Sources          = {},
    Rules            = {},
  }
  -- Choose the logging method
  if (Options == "VERBOSE") then
    NewZipMerger.verboselog = ZIPM_MethodLogVerbose
  else
    NewZipMerger.verboselog = ZIPM_MethodLogDummy
  end
  -- Attach the metatable
  setmetatable(NewZipMerger, ZIPM_Metatable)
  -- Return value
  return NewZipMerger
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  -- Functions
  newreader   = ZIP_NewReader,
  iterateread = ZIP_IterateRead,
  newwriter   = ZIP_NewWriter, --  Low-level writer
  newmerger   = ZIP_NewMerger, -- High-level writer
  -- Constants
  Z_DEFAULT_COMPRESSION = Z_DEFAULT_COMPRESSION,
  Z_NO_COMPRESSION      = Z_NO_COMPRESSION,
  Z_BEST_COMPRESSION    = Z_BEST_COMPRESSION,
}

return PUBLIC_API
