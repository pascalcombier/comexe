--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- A dedicated script for applying functions to files
-- Usage: lua file-apply.lua <function> <file1> [<file2> ...]

-- Available functions: dos2unix, unix2dos

--------------------------------------------------------------------------------
-- MODULE                                                               --
--------------------------------------------------------------------------------

local format = string.format

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function FileApplyFunction (filename, applyFunction)
  -- local variables
  local InputFile = io.open(filename, "rb")
  local Success
  -- Handle results
  if InputFile then
    -- Read content and close the file ASAP
    local Content = InputFile:read("a")
    InputFile:close()
    -- Apply function on the content
    local NewContent = applyFunction(Content)
    -- Write new file if content changed
    if (NewContent ~= Content) then
      local OutputFile = io.open(filename, "wb")
      if OutputFile then
        OutputFile:write(NewContent)
        OutputFile:close()
        Success = true
      else
        Success = false
      end
    else
      Success = true -- Content didn't change
    end
  else
    Success = false -- File could not be found
  end
  -- Return value
  return Success
end

--------------------------------------------------------------------------------
-- FUNCTIONS                                                                  --
--------------------------------------------------------------------------------

local function Dos2Unix (Filename)
  -- Callback implementation: convert all CRLF to LF
  local function Callback (Content)
    return Content:gsub("\r\n", "\n"):gsub("\r", "\n")
  end
  local Success = FileApplyFunction(Filename, Callback)
  -- Return value
  return Success
end

local function Unix2Dos (Filename)
  --  Callback implementation: convert all line endings to LF first, then to CRLF
  local function Callback (Content)
    return Content:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\n", "\r\n")
  end
  local Success = FileApplyFunction(Filename, Callback)
  -- Return value
  return Success
end

-- Dictionary of available ApplyFunctions
local ApplyFunctions = {
  ["dos2unix"] = Dos2Unix,
  ["unix2dos"] = Unix2Dos
}

--------------------------------------------------------------------------------
-- MAIN SCRIPT                                                                --
--------------------------------------------------------------------------------

local function FileExists (Filename)
  local File = io.open(Filename, "rb")
  local Exists
  if File then
    File:close()
    Exists = true
  else
    Exists = false
  end
  return Exists
end

local function ShowHelp ()
  print("Usage: lua file-apply.lua <function> <file1> [<file2> ...]")
  print("Available functions:")
  for Name, Function in pairs(ApplyFunctions) do
    print(format("  - %s", Name))
  end
end

-- Check command line arguments
if #arg < 2 then
  ShowHelp()
  os.exit(1)
end

local FunctionName    = arg[1]
local FunctionToApply = ApplyFunctions[FunctionName]

if (FunctionToApply == nil) then
  print(format("Error: Function '%s' not recognized", FunctionName))
  ShowHelp()
  os.exit(1)
end

local FileCount  = 0
local ErrorCount = 0

-- Process each file
for Index = 2, #arg do
  local Filename = arg[Index]
  FileCount = FileCount + 1
  -- Check if file exists
  if FileExists(Filename) then
    local Success = FunctionToApply(Filename)
    if not Success then
      print(format("ERROR: Failed to apply '%s' to: %s", FunctionName, Filename))
      ErrorCount = (ErrorCount + 1)
    end
  else
    print(format("ERROR: File not found: %s", Filename))
    ErrorCount = (ErrorCount + 1)
  end
end

-- Print summary only if there were errors
if (ErrorCount > 0) then
  print(format("\nSummary: Processed %d files, %d errors", FileCount, ErrorCount))
  os.exit(1)
else
  os.exit(0)
end
