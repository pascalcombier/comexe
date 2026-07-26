--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- ComEXE preprocessor: generate FFI bindings, can be extended later.
--
-- Limitation: only work with LF-based files (Linux, not CRLF Windows)
--
-- GENERAL SYNTAX:
--   -- @BEGIN <OperationName>
--   -- @PARAM <key> <value>
--   -- INPUT-LINE-1
--   -- INPUT-LINE-2
--   -- INPUT-LINE-3
--   -- @OUTPUT
--   GENERATE CODE 1
--   GENERATE CODE 2
--   GENERATE CODE 3
--   -- @END
--
-- The @PARAM lines are user-defined key-value pairs passed to the handler.
-- Everything between @BEGIN and @END (excluding @PARAM lines) is replaced
-- by the handler's generated output on each run.
--
-- Usage:
--   bin/lua55ce -x --preprocess mymodule.lua
--
-- Adding a handler:
--   local HANDLERS = {
--     ["import-c-header"] = HandleGenerateFfi,
--     MyNewOp             = HandleMyNewOp,
--   }

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime         = require("com.runtime")
local FfiCompiler     = require("ffi-compiler")
local TextBlockEditor = require("text-block-editor")

local format = string.format
local concat = table.concat

local newpathname      = Runtime.newpathname
local readfile         = Runtime.readfile
local GenerateBindings = FfiCompiler.GenerateBindings

--------------------------------------------------------------------------------
-- PREPROCESSOR HANDLERS                                                      --
--------------------------------------------------------------------------------

-- import-c-header: read a C header file and generate FFI bindings
--
-- Usage:
--   -- @BEGIN import-c-header
--   -- @PARAM file <header.h> -- C header to parse (user-written)
--   -- @PARAM function <Name> -- Name of the function to generate
--   -- @PARAM lib <libffi>    -- Name of the variable containing the libffi
--   -- @OUTPUT
--   GENERATED-CODE HERE
--   -- @END
local function HandleImportHeader (Block, Directory)
  -- Retrieve block info
  local HeaderFile   = Block.file
  local FunctionName = Block["function"] -- function is reserved keyword
  local FfiVariable  = Block.lib
  -- local data
  local Lines
  local ErrorString
  -- Validate inputs
  if (not HeaderFile) then
    ErrorString = "Missing @PARAM file"
  elseif (not FunctionName) then
    ErrorString = "Missing @PARAM function"
  elseif (not FfiVariable) then
    ErrorString = "Missing @PARAM lib"
  else
    local HeaderPathname = newpathname(Directory, HeaderFile)
    local HeaderFilename = tostring(HeaderPathname)
    local FileContent, ReadErrorString = readfile(HeaderFilename)
    if FileContent then
      Lines, ErrorString = GenerateBindings(FileContent, FfiVariable, FunctionName)
    else
      ErrorString = ReadErrorString
    end
  end
  return Lines, ErrorString
end

-- import-inline-c: parse inline C code and generate FFI bindings
--
-- Usage:
--   -- @BEGIN import-inline-c
--   -- @PARAM function <Name> -- Name of the function to generate
--   -- @PARAM lib <libffi>    -- Name of the variable containing the libffi
--   -- void puts(const char *s);
--   -- void exit(int status);
--   -- @OUTPUT
--   -- GENERATED-CODE HERE
--   -- @END
local function HandleImportInlineC (Block, Directory)
  -- Retrieve data
  local FunctionName = Block["function"] -- function is reserved keyword
  local FfiVariable  = Block.lib
  -- local data
  local ReturnLines
  local ErrorString
  -- Validate inputs
  if (not FunctionName) then
    ErrorString = "Missing @PARAM function"
  elseif (not FfiVariable) then
    ErrorString = "Missing @PARAM lib"
  else
    local SourceC = concat(Block.Input, "\n")
    ReturnLines, ErrorString = GenerateBindings(SourceC, FfiVariable, FunctionName)
  end
  return ReturnLines, ErrorString
end

--------------------------------------------------------------------------------
-- PROCESSOR                                                                  --
--------------------------------------------------------------------------------

local HANDLERS = {
  ["import-c-header"] = HandleImportHeader,
  ["import-inline-c"] = HandleImportInlineC,
}

local function ProcessBlocks (Editor, Directory)
  -- local data
  local BlockCount = Editor:blockcount()
  local BlockIndex = 1
  local TotalCount = 0
  local ErrorString
  -- Main iteration
  while (BlockIndex <= BlockCount) and (not ErrorString) do
    local Block     = Editor:getblock(BlockIndex)
    local BlockType = Block.Type
    local Handler   = HANDLERS[BlockType]
    if Handler then
      local NewLines, HandlerErrorString = Handler(Block, Directory)
      if NewLines then
        Block.Output = NewLines
        TotalCount   = (TotalCount + #NewLines)
      elseif HandlerErrorString then
        ErrorString = format("Handler '%s' error: %s", BlockType, HandlerErrorString)
      end
    else
      ErrorString = format("No handler for block type '%s'", BlockType)
    end
    BlockIndex = (BlockIndex + 1)
  end
  -- Return value
  return TotalCount, ErrorString
end

local function ProcessFile (Filename)
  local Editor, LoadErrorString = TextBlockEditor.load(Filename)
  local Count
  local StatusString
  if Editor then
    local Directory = newpathname(Filename):parent()
    local TotalCount, BlockErrorString = ProcessBlocks(Editor, Directory)
    if (TotalCount > 0) then
      local SaveSuccess, SaveStatus = Editor:save()
      if SaveSuccess then
        Count        = TotalCount
        StatusString = SaveStatus
      else
        StatusString = format("Cannot write %s: %s", Filename, SaveStatus)
      end
    elseif (TotalCount == 0) and (not BlockErrorString) then
      Count        = 0
      StatusString = "no-markers"
    else
      StatusString = BlockErrorString
    end
  else
    StatusString = LoadErrorString
  end
  -- return value
  return Count, StatusString
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  process = ProcessFile,
}

return PUBLIC_API
