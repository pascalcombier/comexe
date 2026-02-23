--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local format = string.format
local open   = io.open
local exit   = os.exit
local gsub   = string.gsub
local append = table.insert
local concat = table.concat

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function MergeTables (...)
  local ResultTable = {}
  local InputTables = { ... }
  for Index1, InputTable in ipairs(InputTables) do
    for Index2, Value in ipairs(InputTable) do
      append(ResultTable, Value)
    end
  end
  return ResultTable
end

local function FunctionalMap (List, Function)
  local Results = {}
  for Index, Value in ipairs(List) do
    Results[Index] = Function(Value)
  end
  return Results
end

local function InterpolateVariables (Template, Environment)
  -- gsub callback
  local function Replacer (Key)
    return Environment[Key]
  end
  -- Call gsub to replace all the $VARIABLES
  local Pattern = "%$([%w_]+)"
  local Result  = gsub(Template, Pattern, Replacer)
  return Result
end

local function NativePathWindows (Pathname)
  local Result = gsub(Pathname, "[/\\\\]", "\\")
  return Result
end

local function NativePathLinux (Pathname)
  local Result = gsub(Pathname, "[/\\\\]", "/")
  return Result
end

local function PathnameFilename (Pathname)
  local Result = Pathname:match("([^/\\ ]+)$")
  return Result
end

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

local function RemoveExtension (Path, Extension)
  local Result
  if (STRING_HasSuffix(Path, Extension)) then
    local StringEnd = (#Path - #Extension)
    Result = Path:sub(1, StringEnd)
  end
  return Result
end

local function WriteFile (Filename, Content)
  local File = open(Filename, "wb")
  if (File) then
    File:write(Content)
    File:close()
  else
    print(format("Error writing to %s", Filename))
    exit(1)
  end
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local Configurations = {
  { Host = "linux",   Target = "linux",   Suffix = "-l-linux" },
  { Host = "linux",   Target = "windows", Suffix = "-l-mingw" },
  { Host = "windows", Target = "windows", Suffix = "-w-mingw" },
}

local InputFile = arg[1]

if (not InputFile) then
  print("Usage: lua55 lua/generate-makefile.lua makefile.lua")
  exit(1)
end

local InputBase = RemoveExtension(InputFile, ".lua")

for Index, Configuration in ipairs(Configurations) do
  -- Retrieve data
  local Host   = Configuration.Host
  local Target = Configuration.Target
  local Suffix = Configuration.Suffix
  -- Generate function
  local function Generate (Env, Template)
    -- Format output
    local Content = InterpolateVariables(Template, Env)
    -- Write file
    local MakefileFilename = format("%s%s", InputBase, Suffix)
    WriteFile(MakefileFilename, Content)
  end
  -- Create the script environment
  local NewEnvironment = {
    -- Data
    HOST   = Host,
    TARGET = Target,
    -- functions
    map         = FunctionalMap,
    filename    = PathnameFilename,
    removeext   = RemoveExtension,
    mergetables = MergeTables,
    append      = append,
    concat      = concat,
    format      = format,
    generate    = Generate,
  }
  -- Optimize the environment
  if (Host == "windows") then
    NewEnvironment.SEP        = "\\"
    NewEnvironment.RM         = "del /F /Q 2>NUL"
    NewEnvironment.CP         = "copy /Y 1>NUL"
    NewEnvironment.nativepath = NativePathWindows
  else
    NewEnvironment.SEP        = "/"
    NewEnvironment.RM         = "rm -f"
    NewEnvironment.CP         = "cp -f"
    NewEnvironment.nativepath = NativePathLinux
  end
  -- Inherits from the global environment
  local Metatable = {
    __index = _G,
  }
  setmetatable(NewEnvironment, Metatable)
  -- Evaluate the input script
  local Chunk, Error = loadfile(InputFile, "t", NewEnvironment)
  if (Chunk) then
    Chunk()
  else
    print(format("Error loading script: %s", Error))
    exit(1)
  end
end
