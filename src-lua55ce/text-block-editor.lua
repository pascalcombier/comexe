--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- This module contains an "Editor" to programmatically update inlined text
-- blocks inside files (a little like BEGIN/END from org-mode). The blocks are
-- delimited by @BEGIN/@PARAM/@END. This implementation shall be
-- language-agnostic, so the prefix before @BEGIN can be Lua comments "-- " as
-- well as "// ", "# " or other prefix.
--
-- C-style delimiters starting with "/*" and finishing by "*/" are not
-- supported.
--
-- The purpose is to programmatically update blocks for our FFI code
-- generation. Typically, INPUT is user-defined and OUTPUT will be be generated
-- by external handler.
--
-- INPUT is typically optional, needed by some handlers by not all of them.
--
-- LINE-1
-- LINE-2
-- LINE-3
-- -- @BEGIN BlockType
-- -- @PARAM key1 value1
-- -- @PARAM key2 value2
-- OPTIONAL INPUT line 1
-- OPTIONAL INPUT line 2
-- -- @OUTPUT
-- content line 1
-- content line 2
-- -- @END
-- LINE-4
-- LINE-5
-- LINE-6
--
-- Usage:
--   local BlockEditor = require("text-block-editor")
--   local Editor      = BlockEditor.load("file.lua")
--   local Block       = Editor:getblock(1)
--   Block.Output[1] = "replacement" -- edit the first line of the block
--   Block.Output[2] = nil           -- remove the second line 
--   Editor:save()
--
-- Would give save (overwrite) the file:
-- LINE-1
-- LINE-2
-- LINE-3
-- -- @BEGIN BlockType
-- -- @PARAM key1 value1
-- -- @PARAM key2 value2
-- OPTIONAL INPUT line 1
-- OPTIONAL INPUT line 2
-- -- @OUTPUT
-- replacement
-- -- @END
-- LINE-4
-- LINE-5
-- LINE-6
--
-- INTERNAL STRUCTURE
--
-- Internally, the editor is an array of items (strings or tables).
--
-- The previous example would look like:
--
-- local Editor = BlockEditor.load("file.lua")
--
-- Editor[1] = "LINE-1\nLINE-2\nLINE-3"
--
-- Editor[2] = {
--   Type          = "BlockType"
--   ParameterKeys = { "key1", "key2" } -- just to preserve read ordering
--   key1          = "value1"
--   key2          = "value2"
--   CommentPrefix = "-- "
--   Input         = { "OPTIONAL INPUT line 1", "OPTIONAL INPUT line 2" }
--   Output        = { "replacement" }
-- }

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")

local format = string.format
local find   = string.find
local insert = table.insert
local concat = table.concat
local gmatch = string.gmatch

local readfile     = Runtime.readfile
local writefile    = Runtime.writefile
local hasprefix    = Runtime.hasprefix
local removeprefix = Runtime.removeprefix

--------------------------------------------------------------------------------
-- DOCUMENT METATABLE                                                         --
--------------------------------------------------------------------------------

-- Assumption: the content array might have been change by the user
-- So we iterate over the whole array again and again
local function TBE_MethodBlockCount (Editor)
  local BlockList = Editor
  local Count     = 0
  for Index = 1, #BlockList do
    local Item = BlockList[Index]
    if (type(Item) == "table") then
      Count = (Count + 1)
    end
  end
  return Count
end

-- Assumption: the content array might have been change by the user
-- So we iterate over the whole array again and again
local function TBE_MethodGetBlock (Editor, BlockIndex)
  local BlockList = Editor
  local Count     = 0
  local Index     = 1
  local ResultBlock
  while (not ResultBlock) and (Index <= #BlockList) do
    local Item = BlockList[Index]
    if (type(Item) == "table") then
      Count = (Count + 1)
      if (Count == BlockIndex) then
        ResultBlock = Item
      end
    end
    Index = (Index + 1)
  end
  return ResultBlock
end

local function TBE_MethodToString (Editor)
  local BlockList = Editor
  local Parts     = {}
  for ItemIndex = 1, #BlockList do
    local Item = BlockList[ItemIndex]
    if (type(Item) == "string") then
      insert(Parts, Item)
    else
      -- Write BEGIN
      local ParameterKeys = Item.ParameterKeys
      local CommentPrefix = Item.CommentPrefix
      local ItemInput     = Item.Input
      local ItemOutput    = Item.Output
      local NewLine       = format("%s@BEGIN %s\n", CommentPrefix, Item.Type)
      insert(Parts, NewLine)
      -- Write the PARAM in the same order as read
      for ParamIndex = 1, #ParameterKeys do
        local Key     = ParameterKeys[ParamIndex]
        local Value   = Item[Key]
        local NewLine = format("%s@PARAM %s %s\n", CommentPrefix, Key, Value)
        insert(Parts, NewLine)
      end
      -- Write the input lines (above @OUTPUT)
      for LineIndex = 1, #ItemInput do
        local Line    = ItemInput[LineIndex]
        local NewLine = format("%s%s\n", CommentPrefix, Line)
        insert(Parts, NewLine)
      end
      -- Write the generated output
      if (#ItemOutput > 0) then
        local OutputLine = format("%s@OUTPUT\n", CommentPrefix)
        insert(Parts, OutputLine)
        for LineIndex = 1, #ItemOutput do
          local Line    = ItemOutput[LineIndex]
          local NewLine = format("%s\n", Line)
          insert(Parts, NewLine)
        end
      end
      -- Wrote END
      local EndLine = format("%s@END\n", CommentPrefix)
      insert(Parts, EndLine)
    end
  end
  local Result = concat(Parts, "")
  return Result
end

local function TBE_MethodChanged (Editor)
  -- Retrieve data
  local InitialContent = Editor.InitialContent
  local CurrentContent = TBE_MethodToString(Editor)
  local HasChanged     = (CurrentContent ~= InitialContent)
  return HasChanged
end

local function TBE_MethodSave (Editor)
  local HasChanged = TBE_MethodChanged(Editor)
  local StatusString
  if HasChanged then
    -- Retrieve data
    local Filename       = Editor.Filename
    local CurrentContent = TBE_MethodToString(Editor)
    -- Write the file
    local WriteSuccess, WriteErrorString = writefile(Filename, CurrentContent)
    if WriteSuccess then
      StatusString = "written"
    else
      StatusString = WriteErrorString
    end
  else
    StatusString = "unchanged"
  end
  -- Evaluate success and return value
  local Success = ((StatusString == "unchanged") or (StatusString == "written"))
  return Success, StatusString
end

local EDITOR_METATABLE = {
  -- METATABLE_LuaDefinedMethods
  __tostring = TBE_MethodToString,
  -- METATABLE_UserDefinedMethods
  __index = {
    changed    = TBE_MethodChanged,
    getblock   = TBE_MethodGetBlock,
    blockcount = TBE_MethodBlockCount,
    save       = TBE_MethodSave,
  },
}

--------------------------------------------------------------------------------
-- PARSE                                                                      --
--------------------------------------------------------------------------------

-- Unefficient, find the line start with backward iteration
local function FindLineStart (Content, Position)
  local Result       = Position
  local FoundNewLine = false
  while (not FoundNewLine) and (Result > 1) do
    local PreviousCharacter = Content:sub((Result - 1), (Result - 1))
    if (PreviousCharacter == "\n") then
      FoundNewLine = true
    else
      Result = (Result - 1)
    end
  end
  return Result
end

local function FindLineEnd (Content, Position)
  local Position = find(Content, "\n", Position)
  if (not Position) then
    Position = (#Content + 1)
  end
  return Position
end

local function ParseBlock (Block, BlockContent)
  local ParameterKeys = Block.ParameterKeys
  local CommentPrefix = Block.CommentPrefix
  local BeforeOutput  = true
  for BlockLine in gmatch(BlockContent, "([^\n]*)\n?") do
    local Key, Value = BlockLine:match("@PARAM%s+(%w+)%s+(.+)")
    if Key then
      Block[Key] = Value
      insert(ParameterKeys, Key) -- Preserve Key order in ParameterKeys array
    elseif BeforeOutput and BlockLine:match("@OUTPUT") then
      BeforeOutput = false
    elseif BeforeOutput then
    -- In the INPUT part we try to remove the comment prefix
      local Line
      if hasprefix(BlockLine, CommentPrefix) then
        Line = removeprefix(BlockLine, CommentPrefix)
      else
        Line = BlockLine
      end
      insert(Block.Input, Line)
    else
      insert(Block.Output, BlockLine)
    end
  end
end

local function ParseContent (Content)
  -- local data
  local Items    = {}
  local Position = 1
  local Done     = false
  local ErrorString
  -- Main iteration
  while (not Done) and (not ErrorString) do
    -- Find a new block
    local BeginPosition = find(Content, "@BEGIN", Position, true)
    if (not BeginPosition) then
      -- Handle last block of text of the file
      local LastStringItem = Content:sub(Position)
      insert(Items, LastStringItem)
      Done = true
    else
      -- Handle a block starting with @BEGIN
      local LineStartPosition = FindLineStart(Content, BeginPosition)
      -- Preserve the text between CURRENT and the @BEGIN marker
      if (BeginPosition > Position) then
        insert(Items, Content:sub(Position, (LineStartPosition - 1)))
      end
      -- CommentPrefix for "-- @BEGIN" is "-- ", for "# @BEGIN" is "# "
      local CommentPrefix = Content:sub(LineStartPosition, (BeginPosition - 1))
      local BeginLineEnd  = FindLineEnd(Content, BeginPosition)
      local BeginLine     = Content:sub(BeginPosition, (BeginLineEnd - 1))
      local BlockType     = BeginLine:match("@BEGIN%s+([%w%-]+)")
      local EndPosition   = find(Content, "@END", BeginLineEnd, true)
      if (not EndPosition) then
        ErrorString = format("@BEGIN '%s' without matching @END", BlockType)
      else
        local EndLineStart = FindLineStart(Content, EndPosition)
        local BlockContent = Content:sub((BeginLineEnd + 1), (EndLineStart - 1))
        local NewBlock = {
          Type          = BlockType,
          ParameterKeys = {},
          CommentPrefix = CommentPrefix,
          Input         = {},
          Output        = {},
        }
        ParseBlock(NewBlock, BlockContent)
        insert(Items, NewBlock)
        -- Next line after @END
        local EndLineEnd = FindLineEnd(Content, EndPosition)
        Position = (EndLineEnd + 1)
      end
    end
  end
  return Items, ErrorString
end

local function BE_LoadTextFile (Filename)
  local Content, ErrorString = readfile(Filename, "string")
  local Result
  if Content then
    local BlockList, ParseError = ParseContent(Content)
    if BlockList then
      -- The items are stored in the array part of the table
      -- We need to append the metadata in the key/value part
      local NewEditor = BlockList
      NewEditor.Filename       = Filename
      NewEditor.InitialContent = Content
      -- Attach metatable
      setmetatable(NewEditor, EDITOR_METATABLE)
      Result = NewEditor
    else
      ErrorString = ParseError
    end
  end
  return Result, ErrorString
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  load = BE_LoadTextFile,
}

return PUBLIC_API
