--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local clock = os.clock

--------------------------------------------------------------------------------
-- TIMER UTILITY                                                              --
--------------------------------------------------------------------------------

local function TIMER_MethodStart (Timer)
  if (not Timer.Running) then
    Timer.StartTime = clock()
    Timer.Running   = true
  end
end

local function TIMER_MethodStop (Timer)
  if Timer.Running then
    Timer.Seconds   = Timer.Seconds + (clock() - Timer.StartTime)
    Timer.Running   = false
    Timer.StartTime = nil
  end
end

local function TIMER_MethodGetElapsedSeconds (Timer)
  local ElapsedSeconds
  if Timer.Running then
    ElapsedSeconds = Timer.Seconds + (clock() - Timer.StartTime)
  else
    ElapsedSeconds = Timer.Seconds
  end
  return ElapsedSeconds
end

local function TIMER_MethodReset (Timer)
  Timer.Seconds   = 0
  Timer.Running   = false
  Timer.StartTime = nil
  TIMER_MethodStart(Timer)
end

local TIMER_Metatable = {
  -- Custom methods
  __index = {
    Start             = TIMER_MethodStart,
    Stop              = TIMER_MethodStop,
    GetElapsedSeconds = TIMER_MethodGetElapsedSeconds,
    Reset             = TIMER_MethodReset
  }
}

local function TIMER_NewTimer ()
  -- Create a new object
  local NewTimerObject = {
    Seconds   = 0,
    Running   = false,
    StartTime = nil
  }
  -- Attach methods
  setmetatable(NewTimerObject, TIMER_Metatable)
  -- Return new timer
  return NewTimerObject
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  NewTimer = TIMER_NewTimer
}

return PUBLIC_API