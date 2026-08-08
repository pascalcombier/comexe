--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- ComEXE preprocessor: generate FFI bindings, can be extended later.
--
-- Limitation: work with LF-based files (Linux, on Windows CRLF, might work or
-- not)
--
-- GENERAL SYNTAX:
--   -- @BEGIN FfiHeader("FunctionName", "libffi", "header.h")
--   -- INPUT-LINE-1
--   -- INPUT-LINE-2
--   -- @OUTPUT
--   GENERATED CODE 1
--   GENERATED CODE 2
--   GENERATED CODE 3
--   -- @END
--
-- By design, the @BEGIN line is a Lua expression, evaluated in an environment
-- exposing the registered handlers (FfiHeader, FfiDeclarations).
-- 
-- Each handler receives the block Context as its first argument, plus the
-- arguments given in the expression. The handler shall return the generated
-- output lines.
--
-- Usage:
--   bin/lua55ce -x --preprocess mymodule.lua
--
-- Adding a handler:
--   local function MyHandler (Context, ...)
--     -- read Context.Input, Context.Output, Context.Directory
--     return Lines, ErrorString
--   end
--   HANDLERS["MyHandler"] = MyHandler

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

local function HandleFfiHeader (Context, FunctionName, FfiVariable, HeaderFile)
  -- local data
  local Lines
  local ErrorString
  -- Validate inputs
  if (not FunctionName) then
    ErrorString = "Missing function argument"
  elseif (not FfiVariable) then
    ErrorString = "Missing lib argument"
  elseif (not HeaderFile) then
    ErrorString = "Missing file argument"
  else
    local HeaderPathname = newpathname(Context.Directory, HeaderFile)
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

-- The C declarations come from the block INPUT lines
local function HandleFfiDeclarations (Context, FunctionName, FfiVariable)
  -- local data
  local ReturnLines
  local ErrorString
  -- Validate inputs
  if (not FunctionName) then
    ErrorString = "Missing function argument"
  elseif (not FfiVariable) then
    ErrorString = "Missing lib argument"
  else
    local SourceC = concat(Context.Input, "\n")
    ReturnLines, ErrorString = GenerateBindings(SourceC, FfiVariable, FunctionName)
  end
  return ReturnLines, ErrorString
end

--------------------------------------------------------------------------------
-- PROCESSOR                                                                  --
--------------------------------------------------------------------------------

local HANDLERS = {
  FfiHeader       = HandleFfiHeader,
  FfiDeclarations = HandleFfiDeclarations,
}

-- Build a new sandbox environment at runtime: redirect the calls to HANDLERS
-- with the proper context.
--
-- The @BEGIN Handler(...) will be simply evaluated in this environment
local function BuildEnvironment (Context)
  local NewEnvironment = {}
  for Name, Handler in pairs(HANDLERS) do
    local function NewHandler (...)
      return Handler(Context, ...)
    end
    NewEnvironment[Name] = NewHandler
  end
  return NewEnvironment
end

local function ProcessBlocks (Editor, Directory)
  -- local data
  local BlockCount = Editor:blockcount()
  local BlockIndex = 1
  local TotalCount = 0
  local ErrorString
  -- Main iteration
  while (BlockIndex <= BlockCount) and (not ErrorString) do
    local Block     = Editor:getblock(BlockIndex)
    local BeginLine = Block.BeginLine
    -- Block context: input lines, current output, directory
    local NewContext = {
      Directory     = Directory,
      CommentPrefix = Block.CommentPrefix,
      Input         = Block.Input,
      Output        = Block.Output,
    }
    -- Evaluate the @BEGIN line as a Lua expression
    local NewEnvironment   = BuildEnvironment(NewContext)
    local LuaCode          = format("return %s", BeginLine)
    local Chunk, LoadError = load(LuaCode, "@BEGIN", "t", NewEnvironment)
    if Chunk then
      local Success, Lines, HandlerErrorString = pcall(Chunk)
      if (not Success) then
        ErrorString = format("Block %d: %s", BlockIndex, Lines)
      elseif (type(Lines) ~= "table") then
        ErrorString = format("Block %d: %s", BlockIndex, HandlerErrorString)
      else
        Block.Output = Lines
        TotalCount   = (TotalCount + #Lines)
      end
    else
      ErrorString = format("Block %d: %s", BlockIndex, LoadError)
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
