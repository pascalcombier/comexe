--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local format = string.format
local append = table.insert
local write  = io.write

--------------------------------------------------------------------------------
-- MINI TEST REPORTER                                                         --
--------------------------------------------------------------------------------

local function REPORTER_MethodBlock (Reporter, Name)
  -- finalize current block if present and push into Blocks
  local Blocks       = Reporter.Blocks
  local CurrentBlock = Reporter.CurrentBlock
  -- Finalize any existing current block
  if CurrentBlock then
    append(Blocks, CurrentBlock)
  end
  -- Create a new block
  local NewBlock = {
    Name  = Name,
    Pass  = 0,
    Total = 0,
  }
  Reporter.CurrentBlock = NewBlock
end

local function REPORTER_MethodWritef (Reporter, ...)
  local String = format(...)
  write(String)
end

local function REPORTER_MethodPrintf (Reporter, ...)
  local String = format(...)
  print(String)
end

local function REPORTER_MethodExpect (Reporter, TestName, Condition)
  -- Retrieve data
  local CurrentBlock = Reporter.CurrentBlock
  -- Validate state
  assert(CurrentBlock, "REPORTER: missing Reporter:block('name')")
  -- Update counters
  local Suffix
  CurrentBlock.Total = (CurrentBlock.Total + 1)
  if Condition then
    CurrentBlock.Pass = (CurrentBlock.Pass + 1)
    Status            = "[x]"
    Suffix            = ""
  else
    Status = "[ ]"
    Suffix = " FAILED"
  end
  -- Make sure the result is aliged left
  REPORTER_MethodPrintf(Reporter, "%s %s%s", Status, TestName, Suffix)
end

local function REPORTER_MethodSummary (Reporter, Options)
  -- Retrieve data
  local Blocks = Reporter.Blocks
  -- Flush the current block
  REPORTER_MethodBlock(Reporter, nil)
  -- Show the blocks
  local SummaryPass  = 0
  local SummaryCount = 0
  for Index = 1, #Blocks do
    local Block = Blocks[Index]
    local BlockName = Block.Name
    local Pass      = Block.Pass
    local Total     = Block.Total
    -- Determine status mark and word
    local StatusPrefix
    local StatusSuffix
    if (Pass == Total) then
      StatusPrefix = "[x]"
      StatusSuffix = "PASSED"
    else
      StatusPrefix = "[ ]"
      StatusSuffix = "FAILED"
    end
    -- Print with counts formatted as two-digit inline
    print(format("%s %04d/%04d STEPS %s - %s", StatusPrefix, Pass, Total, StatusSuffix, BlockName))
    SummaryPass  = (SummaryPass  + Pass)
    SummaryCount = (SummaryCount + Total)
  end
  -- Overall summary
  local SummaryStatus
  if (SummaryPass == SummaryCount) then
    SummaryStatus = ": ALL TESTS PASSED"
  else
    SummaryStatus = ": SOME TEST FAILED, NEED TO INVESTIGATE"
  end
  print(format("TOTAL %04d/%04d PASS%s", SummaryPass, SummaryCount, SummaryStatus))
  if (Options == "os.exit") and (SummaryPass < SummaryCount) then
    os.exit(1)
  end
end

local function NewTestReporter ()
  -- Create a new object
  local NewReporter = {
    -- Data
    CurrentBlock  = nil,
    Blocks        = {},
    -- Methods
    block   = REPORTER_MethodBlock,
    writef  = REPORTER_MethodWritef,
    printf  = REPORTER_MethodPrintf,
    expect  = REPORTER_MethodExpect,
    summary = REPORTER_MethodSummary
  }
  -- Return value
  return NewReporter
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  new = NewTestReporter
}

return PUBLIC_API
