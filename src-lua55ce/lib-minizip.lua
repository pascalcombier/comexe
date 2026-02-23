--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- We only support new ZIP creation, and not ZIP edition. Minizip does not
-- support ZIP edition, it just support APPEND_STATUS_ADDINZIP which essentially
-- add a new record at the end of the file without much check. So one could end
-- with duplicates entries, which may lead to issues.
--
-- We remove the need for APPEND_STATUS_ADDINZIP by providing ZIP_NewMerger: one
-- can create a new ZIP by merging multiple directories/ZIP together.

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local MiniZip = require("com.raw.minizip")
local Runtime = require("com.runtime")

local format      = string.format
local stderr      = io.stderr
local append      = Runtime.append
local newpathname = Runtime.newpathname
local readfile    = Runtime.readfile
local fileexists  = Runtime.fileexists
local listfiles   = Runtime.listfiles

-- functions unzip
local unzip_open                  = MiniZip.unzip_open
local unzip_goto_first_file       = MiniZip.unzip_goto_first_file
local unzip_goto_next_file        = MiniZip.unzip_goto_next_file
local unzip_get_current_file_info = MiniZip.unzip_get_current_file_info
local unzip_open_current_file     = MiniZip.unzip_open_current_file
local unzip_read_current_file     = MiniZip.unzip_read_current_file_string
local unzip_close_current_file    = MiniZip.unzip_close_current_file
local unzip_close                 = MiniZip.unzip_close

-- functions zip
local zip_open                    = MiniZip.zip_open
local zip_open_newfile_in_zip     = MiniZip.zip_open_newfile_in_zip
local zip_write_data              = MiniZip.zip_write_data
local zip_close_file              = MiniZip.zip_close_file
local zip_close                   = MiniZip.zip_close

-- Constants
local UNZ_OK                    = MiniZip.UNZ_OK
local UNZ_END_OF_LIST_OF_FILE   = MiniZip.UNZ_END_OF_LIST_OF_FILE
local ZIP_OK                    = MiniZip.ZIP_OK
local APPEND_STATUS_CREATE      = MiniZip.APPEND_STATUS_CREATE
local APPEND_STATUS_CREATEAFTER = MiniZip.APPEND_STATUS_CREATEAFTER
local APPEND_STATUS_ADDINZIP    = MiniZip.APPEND_STATUS_ADDINZIP
local Z_DEFLATED                = MiniZip.Z_DEFLATED
local Z_DEFAULT_COMPRESSION     = MiniZip.Z_DEFAULT_COMPRESSION
local Z_NO_COMPRESSION          = MiniZip.Z_NO_COMPRESSION
local Z_BEST_SPEED              = MiniZip.Z_BEST_SPEED
local Z_BEST_COMPRESSION        = MiniZip.Z_BEST_COMPRESSION

--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS                                                            --
--------------------------------------------------------------------------------

local function ZIP_HandleFile (UnzFile, FileInfo, EntryCallback)
  -- Local variables
  local Continue  = true
  local EntryName = FileInfo.filename
  -- Provide a function to stop iteration
  local function StopIterationFunction ()
    Continue = false
  end
  -- Provide a function to read content if necessary
  local function ReadFunction ()
    local FileContent = nil
    local OpenResult  = unzip_open_current_file(UnzFile)
    if (OpenResult == UNZ_OK) then
      local SizeInBytes = FileInfo.uncompressed_size
      -- Read the entire file content
      if (SizeInBytes > 0) then
        -- Read the entire file in one operation
        local Data, ErrorMessage = unzip_read_current_file(UnzFile, SizeInBytes)
        if Data and (#Data > 0) then
          FileContent = Data
        end
      end
     -- Ignore the return value of unzip_close_current_file
       unzip_close_current_file(UnzFile)
    end
    -- Return value
    return FileContent
  end
  -- Call the entry function
  EntryCallback(EntryName, ReadFunction, StopIterationFunction)
  -- Return the continue status
  return Continue
end

local function ZIP_IterateRead (ZipFilename, EntryFunc)
  -- Local data
  local Success = false
  local ErrorMessage
  -- Open the ZIP file for reading
  local UnzFile, OpenError = unzip_open(ZipFilename)
  assert(UnzFile, OpenError)
  -- Iterate
  local Continue = (unzip_goto_first_file(UnzFile) == UNZ_OK)
  while Continue do
    -- Get current file info
    local FileInfo, FileError = unzip_get_current_file_info(UnzFile)
    if FileInfo then
      -- Handle the current file
      Continue = ZIP_HandleFile(UnzFile, FileInfo, EntryFunc)
      -- Try to go to next file
      if Continue then
        local NextResult = unzip_goto_next_file(UnzFile)
        if (NextResult == UNZ_END_OF_LIST_OF_FILE) then
          Continue = false
          Success  = true
        elseif (NextResult ~= UNZ_OK) then
          Continue = false
        end
      end
    else
      ErrorMessage = FileError
      Continue     = false
    end
  end
  -- If we finished the loop without errors, it's successful
  Success = (not Continue) and (not ErrorMessage)
  -- Ignore the return value of unzip_close
  unzip_close(UnzFile)
  -- Return values
  return Success, ErrorMessage
end

--------------------------------------------------------------------------------
-- TYPE ARCHIVE WRITER                                                        --
--------------------------------------------------------------------------------

local function ZIPW_MethodClose (WriterObject)
  -- Retrieve the zip handle
  local ZipFile = WriterObject.ZipFile
  if ZipFile then
    -- Close the zip file
    local ZipComment  = nil
    local CloseResult = zip_close(ZipFile, ZipComment)
    -- Mark as closed
    WriterObject.ZipFile = nil
    -- Return the result for potential error checking
    return CloseResult
  end
end

local function ZIPW_MethodWriteEntry (WriterObject, EntryName, FileContents)
  -- Retrieve data
  local ZipFile          = WriterObject.ZipFile
  local CompressionLevel = WriterObject.CompressionLevel
  -- Error handling
  assert(ZipFile,      "API: Write after close")
  assert(FileContents, "FileContents must be provided")
  -- Open new file in zip (only Z_DEFLATED is supported by minizip)
  local Result = zip_open_newfile_in_zip(ZipFile, EntryName, Z_DEFLATED, CompressionLevel)
  local ErrorMessage
  if (Result == ZIP_OK) then
    -- Write the data
    local WriteResult = zip_write_data(ZipFile, FileContents)
    if (WriteResult == ZIP_OK) then
      -- Close file in zip
      local CloseResult = zip_close_file(ZipFile)
      if (CloseResult ~= ZIP_OK) then
        ErrorMessage = format("Failed to close file in zip (error code: %d)", CloseResult)
      end
    else
      ErrorMessage = format("Failed to write data to zip (error code: %d)", WriteResult)
    end
  else
    ErrorMessage = format("Failed to create new file in zip (error code: %d)", Result)
  end
  -- Evaluate success
  local Success = (ErrorMessage == nil)
  -- Return value: Success is true if ErrorMessage is nil
  return Success, ErrorMessage
end

local ZIPW_Metatable = {
  -- Generic methods
  __gc = ZIPW_MethodClose,
  -- Custom methods
  __index = {
    Close      = ZIPW_MethodClose,
    WriteEntry = ZIPW_MethodWriteEntry
  }
}

local function ZIP_NewWriter (ZipFilename, OptionalMode, OptionalCompressionLevel)
  -- Result variables
  local NewWriterObject
  -- Handle default values
  local Mode             = (OptionalMode or APPEND_STATUS_CREATE)
  local CompressionLevel = (OptionalCompressionLevel or Z_DEFAULT_COMPRESSION)
  -- APPEND_STATUS_CREATE basically means OVERWRITE previous ZIP
  local ZipFile, ErrorMessage = zip_open(ZipFilename, Mode)
  -- Only proceed if zip creation succeeded
  if ZipFile then
    -- Create a new writer object
    NewWriterObject = {
      ZipFile          = ZipFile,
      CompressionLevel = CompressionLevel
    }
    -- Attach the metatable
    setmetatable(NewWriterObject, ZIPW_Metatable)
  end
  -- Return the writer object and error message
  return NewWriterObject, ErrorMessage
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
  local NativePathname = SourcePathname:convert("native")
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
-- remove the first path component from each entry.
--
-- Example: "DIR-1/DIR-2/file.txt" -> "DIR-2/file.txt"
local function ZIPM_ImportDirectory (Merger, Writer, SourceId, SourcePath, EntriesSet)
  -- local callback
  local function ProcessFile (NativePathname, FileType)
    if (FileType == "file") then
      local FilePathname = newpathname(NativePathname)
      -- Remove the directory element (i.e. "DIR-1")
      FilePathname:remove(1)
      -- Convert
      local ZipEntryName = FilePathname:convert("internal")
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
  local Writer, ErrorString = ZIP_NewWriter(ZipFilename, APPEND_STATUS_CREATE, CompressionLevel)
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
  IterateRead = ZIP_IterateRead,
  NewWriter   = ZIP_NewWriter, --  Low-level writer
  NewMerger   = ZIP_NewMerger, -- High-level writer
  -- Constants
  APPEND_STATUS_CREATE      = APPEND_STATUS_CREATE,
  APPEND_STATUS_CREATEAFTER = APPEND_STATUS_CREATEAFTER,
  APPEND_STATUS_ADDINZIP    = APPEND_STATUS_ADDINZIP,
  Z_DEFAULT_COMPRESSION     = Z_DEFAULT_COMPRESSION,
  Z_NO_COMPRESSION          = Z_NO_COMPRESSION,
  Z_BEST_SPEED              = Z_BEST_SPEED,
  Z_BEST_COMPRESSION        = Z_BEST_COMPRESSION,
}

return PUBLIC_API
