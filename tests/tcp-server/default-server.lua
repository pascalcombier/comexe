--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local format = string.format

--------------------------------------------------------------------------------
-- MAIN FUNCTION                                                              --
--------------------------------------------------------------------------------

-- Common server behaviour shared between luasocket-tcp-server and luv-tcp-server

local function SERVER_HandleRequest (Request)
  local CloseRequest
  local Response
  if (Request == "CLOSE-SERVER") then
    Response     = "OK"
    CloseRequest = true
  else
    Response     = format("UNKNOWN:%s", Request)
    CloseRequest = false
  end
  print(format("RES:[%s]", Response))
  return CloseRequest, Response
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

return SERVER_HandleRequest
