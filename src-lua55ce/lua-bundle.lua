--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- This code won't use ComEXE API such as Runtime.readfile, string functions,
-- etc, so that we can reuse this file to generate a standalone Lua standard
-- script.
--
-- For that reason, lua-bundle won't benefits from ComEXE strengths and won't
-- work with filenames with unicode characters.

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local format = string.format
local append = table.insert
local concat = table.concat

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function readfile (Filename)
  local File = io.open(Filename, "rb")
  local Result
  local ErrorString
  if File then
    Result = File:read("*a")
    File:close()
  else
    ErrorString = format("cannot open %s", Filename)
  end
  return Result, ErrorString
end

-- Copied from runtime.lua
local function STRING_HasSuffix (String, Suffix)
  local SuffixLen = #Suffix
  local Result
  local StartPos = (#String - SuffixLen + 1)
  if (StartPos < 1) then
    Result = false
  else
    Result = (String:find(Suffix, StartPos, true) == StartPos)
  end
  return Result
end

-- Extract the file name from a path
-- "src-lua55ce/lua-bundle.lua" -> "lua-bundle.lua"
local function GetBasename (Filename)
  local Match = Filename:match("([^/\\]+)$")
  local Result
  if Match then
    Result = Match
  else
    Result = Filename
  end
  return Result
end

-- Recursive function
local function TraverseRequires (LuaCode, Visited, Entries)
  -- require("test")
  -- require('test')
  -- require "test"
  local PATTERN = "require%s*%(?%s*['\"]([^'\"]+)"
  -- Find all the require calls
  for RequiredItem in LuaCode:gmatch(PATTERN) do
    local Filename
    if STRING_HasSuffix(RequiredItem, ".lua") then
      Filename = RequiredItem
    else
      Filename = format("%s.lua", RequiredItem)
    end
    -- Process file
    if (not Visited[RequiredItem]) then
      local FileContents, ErrorString = readfile(Filename)
      if ErrorString then
        local NewEntry = { type = "ignored", name = RequiredItem }
        append(Entries, NewEntry)
      else
        local NewEntry = { type = "bundled", name = RequiredItem, code = FileContents, filename = Filename }
        append(Entries, NewEntry)
        Visited[RequiredItem] = true
        TraverseRequires(FileContents, Visited, Entries)
      end
    end
  end
end

local function GenerateOutputScript (LuaCode, Entries, MainFilename)
  -- Easy function
  local OutputLines = {}
  local function newline (...)
    local String = format(...)
    append(OutputLines, String)
  end
  -- Timestamp
  local Timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
  newline("-- Generated on %s by ComEXE Bundle", Timestamp)
  -- SUMMARY section
  for Index, Entry in ipairs(Entries) do
    if (Entry.type == "ignored") then
      newline("-- IGNORED %q", Entry.name)
    else
      newline("--  BUNDLE %q %s", Entry.name, Entry.filename)
    end
  end
  -- CONTENT section
  for Index, Entry in ipairs(Entries) do
    if (Entry.type == "bundled") then
      newline("-- CONTENT %q %s", Entry.name, Entry.filename)
      newline("package.preload[\"%s\"] = function ()", Entry.name)
      newline("%s", Entry.code)
      newline("end")
    end
  end
  -- MAIN section
  newline("-- MAIN %s", MainFilename)
  newline("%s", LuaCode)
  -- Concatenate
  local FormattedCode = concat(OutputLines, "\n")
  return FormattedCode
end

local function Bundle (InputFilename)
  -- Read input file
  local LuaScript, ErrorString = readfile(InputFilename)
  if ErrorString then
    error(ErrorString)
  end
  local MainFilename = GetBasename(InputFilename)
  -- Traverse
  local Visited = {}
  local Entries = {}
  TraverseRequires(LuaScript, Visited, Entries)
  -- Generate output
  local Output = GenerateOutputScript(LuaScript, Entries, MainFilename)
  -- Return value
  return Output
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  bundle = Bundle,
}

return PUBLIC_API
