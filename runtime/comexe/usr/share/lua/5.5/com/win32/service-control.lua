--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")
local Win32   = require("com.win32")

local format         = string.format
local ExecuteCommand = Runtime.executecommand
local shellexecute   = Win32.shellexecute
local formatmessage  = Win32.formatmessage

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function SERVICE_Start (ServiceName)
  -- validate inputs
  assert(ServiceName, "ServiceName is required")
  -- Prepare the call
  local Verb        = "runas"
  local Services    = "sc"
  local Command     = format("start %s", ServiceName)
  local Directory   = nil
  local ShowCommand = "SW_SHOWNORMAL"
  local OptionWait  = true
  -- Call the API
  local ExecuteSuccess, ReturnCode, ErrorString = shellexecute(Verb, Services, Command, Directory, ShowCommand, OptionWait)
  -- Determine success
  local ReturnedSuccess
  if ExecuteSuccess and (ReturnCode == 0) then
    ReturnedSuccess = true
  elseif ErrorString then
    ReturnedSuccess = false
  else
    ErrorString = formatmessage(ReturnCode)
  end
  -- return value
  return ReturnedSuccess, ErrorString
end

-- Example of output: sc query SE-PRINTER
-- 
-- SERVICE_NAME: SE-PRINTER
--        TYPE               : 10  WIN32_OWN_PROCESS
--        STATE              : 1  STOPPED
--        WIN32_EXIT_CODE    : 1077  (0x435)
--        SERVICE_EXIT_CODE  : 0  (0x0)
--        CHECKPOINT         : 0x0
--        WAIT_HINT          : 0x0
--
local function SERVICE_GetState (ServiceName)
  -- Results
  local ResultStateInteger
  local ResultStateString
  -- validate inputs
  assert(ServiceName, "ServiceName is required")
  -- Format command
  local Command = format("sc query %s", ServiceName)
  -- Use sc query <name> and parse the STATE line
  local ExitCode, ExitReason, Stdout, Stderr = ExecuteCommand(Command, nil, "string")
  if (ExitCode == 0) then
    local StateInteger, StateString = Stdout:match("STATE%s*:%s*(%d+)%s*([%w_]+)")
    if StateInteger then
      ResultStateInteger = tonumber(StateInteger)
    end
    if StateString then
      ResultStateString = StateString
    end
  end
  -- return value
  return ResultStateInteger, ResultStateString
end

local function SERVICE_Stop (ServiceName)
  -- validate inputs
  assert(ServiceName, "ServiceName is required")
  -- Prepare the call
  local Verb        = "runas"
  local Services    = "sc"
  local Command     = format("stop %s", ServiceName)
  local Directory   = nil
  local ShowCommand = "SW_HIDE"
  local OptionWait  = true
  -- Call the API
  local ExecuteSuccess, ReturnCode, ErrorString = shellexecute(Verb, Services, Command, Directory, ShowCommand, OptionWait)
  -- Determine success
  local ReturnedSuccess
  if ExecuteSuccess and (ReturnCode == 0) then
    ReturnedSuccess = true
  elseif ErrorString then
    ReturnedSuccess = false
  else
    ErrorString = formatmessage(ReturnCode)
  end
  -- return value
  return ReturnedSuccess, ErrorString
end

-- StartOption: boot | system | auto | demand | disabled
local function SERVICE_Install (ServiceName, ServiceCommand, Description, StartOption)
  -- validate inputs
  assert(ServiceName,    "ServiceName is required")
  assert(ServiceCommand, "ServiceCommand (binPath) is required")
  -- default parameters
  local UsedStartOption = (StartOption or "demand")
  -- Prepare the call
  local Verb        = "runas"
  local Services    = "sc"
  local Command     = format([[create %s binPath= "%s" DisplayName= "%s" start= %s]], ServiceName, ServiceCommand, Description, UsedStartOption)
  local Directory   = nil
  local ShowCommand = "SW_HIDE"
  local OptionWait  = true
  -- Call the API
  local ExecuteSuccess, ReturnCode, ErrorString = shellexecute(Verb, Services, Command, Directory, ShowCommand, OptionWait)
  -- Determine success
  local ReturnedSuccess
  if ExecuteSuccess and (ReturnCode == 0) then
    ReturnedSuccess = true
  elseif ErrorString then
    ReturnedSuccess = false
  else
    ErrorString = formatmessage(ReturnCode)
  end
  -- return value
  return ReturnedSuccess, ErrorString
end

local function SERVICE_Uninstall (ServiceName)
  -- validate inputs
  assert(ServiceName, "ServiceName is required")
  -- Prepare the call
  local Verb        = "runas"
  local Services    = "sc"
  local Command     = format("delete %s", ServiceName)
  local Directory   = nil
  local ShowCommand = "SW_HIDE"
  local OptionWait  = true
  -- Call the API
  local ExecuteSuccess, ReturnCode, ErrorString = shellexecute(Verb, Services, Command, Directory, ShowCommand, OptionWait)
  -- Determine success (match SERVICE_Start model)
  local ReturnedSuccess
  if ExecuteSuccess and (ReturnCode == 0) then
    ReturnedSuccess = true
  elseif ErrorString then
    ReturnedSuccess = false
  else
    ErrorString = formatmessage(ReturnCode)
  end
  -- return value
  return ReturnedSuccess, ErrorString
end

local function SERVICE_LaunchManager ()
  -- Prepare the call
  local Verb        = "runas"
  local File        = "services.msc"
  local Parameters  = nil
  local Directory   = nil
  local ShowCommand = "SW_SHOWNORMAL"
  local OptionWait  = false
  -- Call the API
  local Success, ReturnCode, ErrorString = shellexecute(Verb, File, Parameters, Directory, ShowCommand, OptionWait)
  -- return value
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- FALLBACK: REGISTRY AUTOSTART CURRENT USER                                  --
--------------------------------------------------------------------------------

local CURRENT_USER_RUN = [[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run]]
local SAM_READ         = Win32.newsam("KEY_READ")
local SAM_WRITE        = Win32.newsam("KEY_WRITE")

local function SERVICE_AddAutostart (ServiceName, ServiceCommand)
  -- validate inputs
  assert(ServiceName,    "ServiceName is required")
  assert(ServiceCommand, "ServiceCommand is required")
  -- Open the key
  local Key, ErrorMessage = Win32.regopenkey(CURRENT_USER_RUN, SAM_WRITE)
  if Key then
    local Success, SetErrorMessage = Key:set(ServiceName, ServiceCommand, "REG_SZ")
    if (not Success) then
      ErrorMessage = SetErrorMessage
    end
    Key:close()
  end
  -- Return value
  local Success = (Key and (not ErrorMessage))
  return Success, ErrorMessage
end

local function SERVICE_HasAutostart (ServiceName)
  -- validate inputs
  assert(ServiceName, "ServiceName is required")
  -- Open the key
  local Key, ErrorMessage = Win32.regopenkey(CURRENT_USER_RUN, SAM_READ)
  local HasValue = false
  if Key then
    local Value, GetErrorMessage = Key:get(ServiceName)
    if Value then
      HasValue = true
    elseif GetErrorMessage then
      ErrorMessage = GetErrorMessage
    end
    Key:close()
  end
  -- Return value
  local Success = (Key and (not ErrorMessage))
  return Success, HasValue, ErrorMessage
end

local function SERVICE_RemoveAutostart (ServiceName)
  -- validate inputs
  assert(ServiceName, "ServiceName is required")
  -- Open the key
  local Key, ErrorMessage = Win32.regopenkey(CURRENT_USER_RUN, SAM_WRITE)
  if Key then
    local Success, DeleteError = Key:delete(ServiceName)
    if not Success then
      ErrorMessage = DeleteError
    end
    Key:close()
  end
  -- Return value
  local Success = (Key and (not ErrorMessage))
  return Success, ErrorMessage
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  -- Service management
  start          = SERVICE_Start,
  stop           = SERVICE_Stop,
  getstate       = SERVICE_GetState,
  install        = SERVICE_Install,
  uninstall      = SERVICE_Uninstall,
  launchmanager  = SERVICE_LaunchManager,
  -- Registry fallback
  addautostart   = SERVICE_AddAutostart,
  hasautostart   = SERVICE_HasAutostart,
  removeautostart = SERVICE_RemoveAutostart,
}

return PUBLIC_API
