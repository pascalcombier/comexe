--------------------------------------------------------------------------------
-- NOTES                                                                      --
--------------------------------------------------------------------------------

-- Use serpent to read / write Lua tables files
-- In the format:
-- field1 = {}
-- field2 = {}
-- etc
--
-- Versus:
-- field1 = {},
-- field2 = {},
-- etc
--
-- To address the "return { XXX }" vs LuaRocks manifest question

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")
local Serpent = require("serpent")

local format          = string.format
local concat          = table.concat
local sort            = table.sort
local append          = Runtime.append
local readfile        = Runtime.readfile
local writefile       = Runtime.writefile
local newpathname     = Runtime.newpathname
local directoryexists = Runtime.directoryexists
local makedirectory   = Runtime.makedirectory
local block           = Serpent.block

--------------------------------------------------------------------------------
-- FILE TO STRING                                                             --
--------------------------------------------------------------------------------

local function TS_Evaluate (LuaString, ChunkName, NewEnvironment)
  local Result
  local ErrorString
  -- Try to load the chunk into the provided environment
  local Chunk, LoadErrorString = load(LuaString, ChunkName, "t", NewEnvironment)
  if Chunk then
    local Success, PcallResult = pcall(Chunk)
    if Success then
      Result = NewEnvironment
    else
      ErrorString = format("Unexpected data in %s %q", ChunkName, PcallResult)
    end
  else
    ErrorString = format("Failed to load %s: %s", ChunkName, LoadErrorString)
  end
  -- Return values
  return Result, ErrorString
end

local function TS_ReadFromString (LuaString, ChunkName)
  local NewEnvironment = {}
  local Result, ErrorString = TS_Evaluate(LuaString, ChunkName, NewEnvironment)
  return Result, ErrorString
end

local function TS_ReadFromFile (Filename)
  local FileContent = readfile(Filename, "string")
  local Result
  local ErrorString
  if FileContent then
    -- Prepare load
    local ChunkName = format("@%s", Filename)
    -- Evaluate chunk
    Result, ErrorString = TS_ReadFromString(FileContent, ChunkName)
  else
    ErrorString = format("Could not read %s", Filename)
  end
  return Result, ErrorString
end

--------------------------------------------------------------------------------
-- STRING TO FILE                                                             --
--------------------------------------------------------------------------------

local function TS_IsArray (Table)
  -- Create the iterator
  local IteratorFunc, TableRef, StartIndex = ipairs(Table)
  -- Call the iterator once
  local Index, Value = IteratorFunc(TableRef, StartIndex)
  -- Check if we got a valid index and value
  local IsArray = (Index and Value)
  return IsArray
end
local function TS_CollectKeys (Table)
  local Keys = {}
  for Key, Value in pairs(Table) do
    append(Keys, Key)
  end
  return Keys
end

local SERPENT_OPTIONS = {
  comment = false
}

local NEW_LINE = "\n"

local function TS_FormatLuaTable (Table)
  local FormattedString
  local ErrorString
  if TS_IsArray(Table) then
    ErrorString = "Unexpected: ipairs found array values"
  else
    -- Collect keys
    local Keys = TS_CollectKeys(Table)
    -- Make output predictable
    sort(Keys)
    -- Format each value
    local StringChunks = {}
    for KeyIndex, KeyString in pairs(Keys) do
      local LuaValue       = Table[KeyString]
      local FormattedValue = block(LuaValue, SERPENT_OPTIONS)
      local StringChunk    = format("%s = %s", KeyString, FormattedValue)
      append(StringChunks, StringChunk)
    end
    -- Format the whole block
    local BlockChunkString
    if (#Keys == 0) then
      BlockChunkString = "{}"
    else
      BlockChunkString = concat(StringChunks, NEW_LINE)
    end
    FormattedString = BlockChunkString
  end
  return FormattedString, ErrorString
end

local function TS_EnsureDirectoryExists (Filename)
  -- local data
  local Success
  local ErrorString
  -- Ensure directory exists
  local Pathname = newpathname(Filename)
  -- Move to parent (side-effect)
  Pathname:parent()
  -- Convert to native pathname string
  local ParentDirectory = tostring(Pathname)
  -- Check the directory
  if directoryexists(ParentDirectory) then
    Success = true
  else
    Success, ErrorString = makedirectory(ParentDirectory)
  end
  -- Return value
  return Success, ErrorString
end

local function TS_WriteLuaTable (Filename, Table)
  local FormattedString, ErrorString = TS_FormatLuaTable(Table)
  local Success
  if FormattedString then
    local DirectoryExists
    DirectoryExists, ErrorString = TS_EnsureDirectoryExists(Filename)
    if DirectoryExists then
      Success, ErrorString = writefile(Filename, FormattedString)
    else
      Success = false
    end
  else
    Success = false
  end
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  readstring = TS_ReadFromString,
  readfile   = TS_ReadFromFile,
  writefile  = TS_WriteLuaTable,
}

return PUBLIC_API
