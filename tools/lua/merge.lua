--[[
* merge.lua
* combine lua scripts that requires
* https://github.com/LoukaMB/merge
--]]

-- Heavily modified by Pascal

-- http://lua-users.org/wiki/StringRecipes
local function StringEndsWith (String, Suffix)
  return Suffix == "" or String:sub(-#Suffix) == Suffix
end

local function PrintError (...)
  local String = string.format(...)
  io.stderr:write(String .. "\n")
end

local function PrintMessage (...)
  local String = string.format(...)
  io.stdout:write(String .. "\n")
end

local function SlurpFile (Filename)
	local File = io.open(Filename, "rb")
  local FileContent
  if File then
    FileContent = File:read("*a")
    File:close()
  else
    PrintError("[ERROR] File '%s' could not be found", Filename)
    FileContent = nil
  end
  return FileContent
end

local function GenerateOutputScript (LuaCode, MergedPairs)

  local UnusedIndex
  local FileStruct
  local RequiredItem
  local RequiredLuaCode
  local OutputLines = {}

  local function AddCode (...)
    local String = string.format(...)
    OutputLines[#OutputLines + 1] = String
  end

  -- Process all the require()
  for UnusedIndex, FileStruct in pairs(MergedPairs) do
    RequiredItem    = FileStruct[1]
    RequiredLuaCode = FileStruct[2]
    AddCode("--------------------------------------------------------------------------------")
    AddCode("-- REQUIRED: %s", RequiredItem)
    AddCode("--------------------------------------------------------------------------------")
    AddCode("package.preload['%s'] = function()", RequiredItem)
    AddCode("%s", RequiredLuaCode)
    AddCode("end")
  end

  -- Finally output the main script
  AddCode("--------------------------------------------------------------------------------")
  AddCode("-- MAIN SCRIPT")
  AddCode("--------------------------------------------------------------------------------")
  AddCode("\n")
  AddCode("%s", LuaCode)
    
  return table.concat(OutputLines, "\n")
end

local function Merge (LuaCode)

  --	[MergeMap]    "script" -> non-nil if merged
  --	[MergedPairs]      [1] -> { "script", file-content }
  
  local function MergeRecursive (LuaCode, MergedMap, MergedPairs)

    local REGEX  = "require%s*%(?%s*['\"]([%w-_/\\%.]+)['\"]%s*%)?"
    local Filename
    local RequiredItem

    -- Process all the require()
    for RequiredItem in LuaCode:gmatch(REGEX) do
      if StringEndsWith(RequiredItem, ".lua") then
        Filename = RequiredItem
      else
        Filename = RequiredItem .. ".lua"
      end

      -- Process required() file
      if not MergedMap[RequiredItem] then
        local FileData = SlurpFile(Filename)
        if not FileData then
          PrintError("File '%s' could not be found", Filename)
        else
          PrintMessage("Processing '%s'", Filename)
          MergedPairs[#MergedPairs + 1] = { RequiredItem, FileData }
          MergedMap[RequiredItem]       = true
          MergeRecursive(FileData, MergedMap, MergedPairs)
        end
      end
      
    end -- for
  end -- function
  
  -- Call the recursive merge function
  local MergedMap   = {}
  local MergedPairs = {}
  MergeRecursive(LuaCode, MergedMap, MergedPairs)

  -- Create output
	return GenerateOutputScript(LuaCode, MergedPairs)
end

local function MergeProcess (ScriptInput, ScriptOutput)

  local LuaScript = SlurpFile(ScriptInput)

  if not LuaScript then
    PrintError("File '%s' could not be found", ScriptInput)
  else
    local FileOut = io.open(ScriptOutput, "w+b")
    if not FileOut then
      PrintError("error: failed to open output %s", ScriptOutput)
    else
      FileOut:write(Merge(LuaScript))
      FileOut:close()
    end
  end
end

return MergeProcess(...)
