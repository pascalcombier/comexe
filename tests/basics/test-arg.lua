--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")
local uv      = require("luv")

local format         = string.format
local insert         = table.insert
local max            = math.max
local ExecuteCommand = Runtime.executecommand

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

-- At the beginning, we found a difference in behaviour related to new lines
-- management between:
--
--  for line in file:lines() do
--  for line in file:lines("L") do
--
-- The difference is on the handling of the last line which is omitted in 1 case.
--
-- So we decided to test with new lines and print with TrimString. Later, we move
-- to uv.spawn and kept the Trim.
--
-- "SAFE" means that we handle nil inputs

local function SAFE_TrimString (String)
  local Result
  if (String == nil) then
    Result = nil
  else
    Result = String:gsub("^%s*(.-)%s*$", "%1")
  end
  return Result
end

-- Same logic as SAFE_Trim, we have any nil we don't print anything.
local function SAFE_Printf (...)
  -- Make arguments easy to parse
  local Arguments = { ... }
  -- Find if any arg is nil
  local ContainsNil = false
  local Index       = 1
  while (not ContainsNil) and (Index <= #Arguments) do
    local Value = Arguments[Index]
    if (Value == nil) then
      ContainsNil = true
    else
      Index = (Index + 1)
    end
  end
  -- Print
  if (not ContainsNil) then
    local String = format(...)
    print(String)
  end
end

local function ConvertToSet (Array)
  local NewSet = {}
  for Index = 1, #Array do
    local SkipValue = Array[Index]
    NewSet[SkipValue] = true
  end
  return NewSet
end

local function CompareExec (StdoutIgnoreSet, StderrIgnoreSet, StdoutA, StdoutB, StderrA, StderrB)
  -- local data
  local TestEquals = 0
  local TestCount  = 0
  local DiffA      = {}
  local DiffB      = {}
  -- Process stdout
  for Index = 1, max(#StdoutA, #StdoutB) do
    local InputLineA   = StdoutA[Index]
    local InputLineB   = StdoutB[Index]
    local TrimmedLineA = SAFE_TrimString(InputLineA)
    local TrimmedLineB = SAFE_TrimString(InputLineB)
    local IgoreLine    = StdoutIgnoreSet[Index]
    -- Analyse
    if IgoreLine then
      SAFE_Printf("A-STDOUT-%2.2d-SKIP [%s]", Index, TrimmedLineA)
      SAFE_Printf("B-STDOUT-%2.2d-SKIP [%s]", Index, TrimmedLineB)
    else
      SAFE_Printf("A-STDOUT-%2.2d      [%s]", Index, TrimmedLineA)
      SAFE_Printf("B-STDOUT-%2.2d      [%s]", Index, TrimmedLineB)
      -- Compare lines
      if (InputLineA == InputLineB) then
        TestEquals = TestEquals + 1
      else
        local Change
        if  (TrimmedLineA == TrimmedLineB) then
          Change = "NewLine"
        else
          Change = ""
        end
        insert(DiffA, format("   [A-OUT-L%2.2d][%s] %s", Index, TrimmedLineA, Change))
        insert(DiffB, format("   [B-OUT-L%2.2d][%s] %s", Index, TrimmedLineB, Change))
      end
      TestCount = TestCount + 1
    end
  end
  -- Process stderr
  for Index = 1, max(#StderrA, #StderrB) do
    local InputLineA   = StderrA[Index]
    local InputLineB   = StderrB[Index]
    local TrimmedLineA = SAFE_TrimString(InputLineA)
    local TrimmedLineB = SAFE_TrimString(InputLineB)
    local IgoreLine    = StderrIgnoreSet[Index]
    -- Analyse
    if IgoreLine then
      SAFE_Printf("A-STDERR-%2.2d-SKIP [%s]", Index, TrimmedLineA)
      SAFE_Printf("B-STDERR-%2.2d-SKIP [%s]", Index, TrimmedLineB)
    else
      SAFE_Printf("A-STDERR-%2.2d      [%s]", Index, TrimmedLineA)
      SAFE_Printf("B-STDERR-%2.2d      [%s]", Index, TrimmedLineB)
      -- Compare lines
      if (InputLineA == InputLineB) then
        TestEquals = TestEquals + 1
      else
        local Change
        if  (TrimmedLineA == TrimmedLineB) then
          Change = "NewLine"
        else
          Change = ""
        end
        insert(DiffA, format("   [A-ERR-L%2.2d][%s] %s", Index, TrimmedLineA, Change))
        insert(DiffB, format("   [B-ERR-L%2.2d][%s] %s", Index, TrimmedLineB, Change))
      end
      TestCount = TestCount + 1
    end
  end
  -- Merge DiffB into DiffA to get LINES-A first and then LINES-B
  for Key, Value in pairs(DiffB) do
    insert(DiffA, Value)
  end
  -- Return values
  return TestEquals, TestCount, DiffA
end

--------------------------------------------------------------------------------
-- TESTS                                                                      --
--------------------------------------------------------------------------------

local function EvalMeaningfulLineCount (StdOutput, IgnoreSet)
  local LineCount = 0
  for Index, Line in ipairs(StdOutput) do
    if (not IgnoreSet[Index]) then
      LineCount = LineCount + 1
    end
  end
  return LineCount
end

-- Test:
-- Generic command line (lua55 or lua55ce will be prefixed automatically)
-- The lines to ignore for STDOUT
-- The lines to ignore for STDERR
-- The string to write to stdin (optional)

local TEST_SCENARIOS = {
  { [[-v]], { 1 } },
  { [[-v -]], { 1 }, { }, ""},
  { [[-]], {}, {}, "" },
  { [[-e print("TEST") -v print-arg.lua arg1 arg2 arg3]], { 1, 3 } },
  { [[print-arg.lua -- TEST1 TEST2 TEST3]], { 1 } },
  { [[-W -e print(_VERSION)]], {} },
  { [[-l lib -e print(type(_G["lib"]))]], {} },
  { [[-l LIB=lib -e print(type(LIB))]], {} },
  { [[-v -E]], {1} },
  { [[-E]], {1}, {} },
  { [[-E -]], {1}, {}, "" },
  { [[-W -e "warn('test')"]], {} },
  { [[-e a=1 -e print(a)]], {} },
  { [[-e print(package.path)]], {} },
  { [[   print-arg.lua --print-warning]], {} },
  { [[-W print-arg.lua --print-warning]], {} },
  { [[-i -v print-arg.lua]], { 1, 2}, {}, ""},
  { [[-z]], {}, { 1, 2, 13 } },
  { [[-- print-arg.lua -e print("hello")]], { 1 } },
  { [[-]], {}, {}, [[print("HELLO")]] },   -- stdout
  { [[-W -]], {}, {}, [[warn("HELLO")]] }, -- stderr
}

print(format("=== START === [PWD=%s]", uv.cwd()))

local BINA = "lua55"
local BINB = "lua55ce"

local TestPassed  = 0
local TestCount   = 0
local TestResults = {}

for TestIndex = 1, #TEST_SCENARIOS do
  local Test              = TEST_SCENARIOS[TestIndex]
  local CommandLine       = Test[1]
  local StdoutIgnoreArray = Test[2] or {}
  local StderrIgnoreArray = Test[3] or {}
  local StdinString       = Test[4]

  local CommandLineA = format("%s %s", BINA, CommandLine)
  local CommandLineB = format("%s      %s", BINB, CommandLine)

  local StdoutIgnoreLinesSet = ConvertToSet(StdoutIgnoreArray)
  local StderrIgnoreLinesSet = ConvertToSet(StderrIgnoreArray)

  print(format("# TEST %2.2d ======================", TestIndex))
  print(CommandLineA)
  print(CommandLineB)
  local ExitCodeA, ExitReasonA, StdoutLinesA, StderrLinesA = ExecuteCommand(CommandLineA, StdinString, "lines")
  local ExitCodeB, ExitReasonB, StdoutLinesB, StderrLinesB = ExecuteCommand(CommandLineB, StdinString, "lines")

  local StdoutLineCountA = EvalMeaningfulLineCount(StdoutLinesA, StdoutIgnoreLinesSet)
  local StderrLineCountA = EvalMeaningfulLineCount(StderrLinesA, StderrIgnoreLinesSet)
  local StdoutLineCountB = EvalMeaningfulLineCount(StdoutLinesB, StdoutIgnoreLinesSet)
  local StderrLineCountB = EvalMeaningfulLineCount(StderrLinesB, StderrIgnoreLinesSet)

  local EqualCount, TestedCount, Differences = CompareExec(StdoutIgnoreLinesSet, StderrIgnoreLinesSet, StdoutLinesA, StdoutLinesB, StderrLinesA, StderrLinesB)

  local Failure = false
  if (ExitCodeA ~= ExitCodeB) then
    print(format("EXIT CODE DIFFERS A=%d B=%d", ExitCodeA, ExitCodeB))
    insert(Differences, format("   [EXITCODE] A=%d B=%d", ExitCodeA, ExitCodeB))
    Failure = true
  end
  if (StdoutLineCountA ~= StdoutLineCountB) then
    print(format("STDOUT LINE COUNT DIFFERS A=%d B=%d", StdoutLineCountA, StdoutLineCountB))
    Failure = true
  end
  if (StderrLineCountA ~= StderrLineCountB) then
    print(format("STDERR LINE COUNT DIFFERS A=%d B=%d", StderrLineCountA, StderrLineCountB))
    Failure = true
  end

  local Success
  if Failure then
    Success = false
  else
    Success = (EqualCount == TestedCount)
  end

  if (Success) then
    insert(TestResults, format("%3.3d pass |lua %s", TestIndex, CommandLine))
    TestPassed = TestPassed + 1
  else
    insert(TestResults, format("%3.3d FAIL |lua %s", TestIndex, CommandLine))
    for Index, Line in pairs(Differences) do
      insert(TestResults, Line)
    end
  end

  TestCount = TestCount + 1
end

print("==== TEST SUMMARY ====")
for Key, Value in pairs(TestResults) do
  print(Value)
end
print(format("%d/%d pass", TestPassed, TestCount))

if (TestPassed == TestCount) then
  os.exit(0)
else
  os.exit(1)
end
