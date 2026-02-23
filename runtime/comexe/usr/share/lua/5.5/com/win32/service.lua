--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local RawService = require("com.raw.win32.service")
local Win32      = require("com.win32")

local format        = string.format
local start         = RawService.start
local setstatus     = RawService.setstatus
local reporterror   = RawService.reporterror
local UTF16         = Win32.utf8to16
local getlasterror  = Win32.getlasterror
local formatmessage = Win32.formatmessage

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

local SERVICE_STATE = {
  SERVICE_STOPPED          = 0x00000001,
  SERVICE_START_PENDING    = 0x00000002,
  SERVICE_STOP_PENDING     = 0x00000003,
  SERVICE_RUNNING          = 0x00000004,
  SERVICE_CONTINUE_PENDING = 0x00000005,
  SERVICE_PAUSE_PENDING    = 0x00000006,
  SERVICE_PAUSED           = 0x00000007,
}

local CONTROL_CODES = {
   SERVICE_CONTROL_STOP           =  1, -- Stop the service
   SERVICE_CONTROL_PAUSE          =  2, -- Pause the service
   SERVICE_CONTROL_CONTINUE       =  3, -- Continue the service
   SERVICE_CONTROL_INTERROGATE    =  4, -- Interrogate the service
   SERVICE_CONTROL_SHUTDOWN       =  5, -- Shutdown the service
   SERVICE_CONTROL_PARAMCHANGE    =  6, -- Parameter change
   SERVICE_CONTROL_NETBINDADD     =  7, -- Network bind add
   SERVICE_CONTROL_NETBINDREMOVE  =  8, -- Network bind remove
   SERVICE_CONTROL_NETBINDENABLE  =  9, -- Network bind enable
   SERVICE_CONTROL_NETBINDDISABLE = 10, -- Network bind disable
}

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

-- SERVICE_Start is a blocking function
local function SERVICE_Start (ServiceNameUtf8, EventFunctionNameUtf8, MainFunctionNameUtf8)
  -- Validate inputs
  assert(type(ServiceNameUtf8)       == "string", "ServiceNameUtf8 must be a string")
  assert(type(EventFunctionNameUtf8) == "string", "EventFunctionNameUtf8 must be a string")
  assert(type(MainFunctionNameUtf8)  == "string", "MainFunctionNameUtf8 must be a string")
  -- Transform string to UTF-16
  local ServiceNameUtf16 = UTF16(ServiceNameUtf8)
  -- Call the C API
  local Success, ErrorCode = start(ServiceNameUtf16, EventFunctionNameUtf8, MainFunctionNameUtf8)
  local ErrorString
  -- Handle errors
  if (not Success) then
    ErrorString = formatmessage(ErrorCode)
  end
  -- Return values
  return Success, ErrorString
end

local function SERVICE_GetControlCode (ControlCodeString)
  -- Format control code
  local ControlCodeValue = CONTROL_CODES[ControlCodeString]
  -- Return value
  return ControlCodeValue
end

local function SERVICE_SetStatus (StatusString, WaitHint)
  -- Handle defaults
  local UsedWaitHint    = (WaitHint or 0)
  local UsedStatusValue = SERVICE_STATE[StatusString]
  assert(UsedStatusValue, format("Unknown service status: '%s'", StatusString))
  -- Call the C API
  local Success = setstatus(UsedStatusValue, UsedWaitHint)
  local ErrorString
  if (not Success) then
    local ErrorCode = getlasterror()
    ErrorString = formatmessage(ErrorCode)
  end
  -- Return values
  return Success, ErrorString
end

local function SERVICE_ReportError (ServiceErrorCode)
  -- Validate inputs
  assert(type(ServiceErrorCode) == "number", "ServiceErrorCode must be a number")
  -- Call the C API
  local ERROR_SERVICE_SPECIFIC_ERROR = 1066
  local Success = reporterror(ERROR_SERVICE_SPECIFIC_ERROR, ServiceErrorCode)
  local ErrorString
  if (not Success) then
    local ReportErrorCode = getlasterror()
    ErrorString = formatmessage(ReportErrorCode)
  end
  -- Return values
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  start          = SERVICE_Start,
  getcontrolcode = SERVICE_GetControlCode,
  setstatus      = SERVICE_SetStatus,
  reporterror    = SERVICE_ReportError,
}

return PUBLIC_API