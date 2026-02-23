--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

print("This script requires lua55ce!!!")
print("This script need to be run from ComEXE ROOT directory")
print("This script will update ROOT/src/version.h")

local Runtime = require("com.runtime")

local fileexists = Runtime.fileexists
local readfile   = Runtime.readfile
local writefile  = Runtime.writefile

local format = string.format

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function CreateIsoDate ()
  -- Format date and time (YYYY-MM-DDTHH:MM:SS)
  local Date       = os.date("*t")
  local DateString = format("%04d-%02d-%02d", Date.year, Date.month, Date.day)
  local TimeString = format("%02d:%02d:%02d", Date.hour, Date.min, Date.sec)
  -- Full string
  local FullString = format("%sT%s", DateString, TimeString)
  -- Return value
  return FullString
end

local function GetFossilCommit ()
  local Command1 = [[fossil status 1>NUL 2>NUL]]
  -- Execute a first time to see whether it works or not
  local Success = os.execute(Command1)
  local Checkout
  if Success then
    local Command2 = [[fossil status 2>NUL]]
    local Process = io.popen(Command2)
    if Process then
      local Result = Process:read("*a")
      Process:close()
      local Pattern = "checkout:%s+([0-9a-f]+)"
      if Result then
        Checkout = Result:match(Pattern)
      end
    end
  end
  return Checkout
end

local function GetGitCommit ()
  local Command1 = [[git rev-parse HEAD 1>NUL 2>NUL]]
  local Command2 = [[git rev-parse HEAD 2>NUL]]
  -- Execute a first time to see whether it works or not
  local Success = os.execute(Command1)
  local Checkout
  if Success then
    local Process = io.popen(Command2)
    if Process then
      local Result = Process:read("*a")
      Process:close()
      Checkout = Runtime.stringtrim(Result)
    end
  end
  return Checkout
end

local function UpdateField (Content, FieldName, NewValue)
  local PreviousContent = Content
  local Pattern         = format([[(#define%%s+%s%%s+)"[^"]+"]], FieldName)
  local ReplaceString   = format([[%%1"%s"]], NewValue)
  local NewContent      = Content:gsub(Pattern, ReplaceString)
  local Changed = (NewContent ~= PreviousContent)
  return NewContent, Changed
end

local function UpdateHeader (Filename, NewCheckout, NewDate, NewVersion)
  local FileContents   = readfile(Filename, "string")
  local CommitChanged  = false
  local DateChanged    = false
  local VersionChanged = false
  local ReturnedState
  local NewContent
  if FileContents then
    NewContent = FileContents
    if NewCheckout then
      NewContent, CommitChanged = UpdateField(NewContent, "COMEXE_COMMIT", NewCheckout)
    end
    if NewDate then
      NewContent, DateChanged = UpdateField(NewContent, "COMEXE_BUILD_DATE", NewDate)
    end
    if NewVersion then
      NewContent, VersionChanged = UpdateField(NewContent, "COMEXE_VERSION", NewVersion)
    end
    -- Write file
    if (CommitChanged or VersionChanged) then
      local Success = writefile(Filename, NewContent)
      if Success then
        ReturnedState = "UPDATED"
      else
        ReturnedState = "ERROR-WRITING"
      end
    else
      ReturnedState = "NO-CHANGE"
    end
  else
    ReturnedState = "ERROR-READING"
  end
  return ReturnedState
end

--------------------------------------------------------------------------------
-- MAIN SCRIPT                                                                --
--------------------------------------------------------------------------------

print("=== SUMMARY")

local UserSpecifiedVersion = arg[1]

local VersionHeader = [[src\version.h]]
print(format("HEADER   [%s]", VersionHeader))

if (not fileexists(VersionHeader)) then
  print(format("%s could not be found", VersionHeader))
  os.exit(1)
end

local CurrentDate = CreateIsoDate()
print(format("DATE     [%s]", CurrentDate))

local FossilCheckoutHash = GetFossilCommit()
if FossilCheckoutHash then
  print(format("FOSSIL   [%s]", FossilCheckoutHash))
else
  print("FOSSIL   [NOT DETECTED OR ERROR]")
end

local GitCheckoutHash = GetGitCommit()
if GitCheckoutHash then
  print(format("GIT-HASH [%s]", GitCheckoutHash))
else
  print("GIT HASH [NOT DETECTED OR ERROR]")
end

local NewCommitHash = (GitCheckoutHash or FossilCheckoutHash)
local NewState      = UpdateHeader(VersionHeader, NewCommitHash, CurrentDate, UserSpecifiedVersion)

print(format("HEADER   [%s] %s", VersionHeader, NewState))

-- Print the whole version file at the end only if it changed
if NewState == "UPDATED" then
  print("=== NEW FILE")
  local FinalContents = readfile(VersionHeader, "string")
  if FinalContents then
    print(FinalContents)
  end
end
