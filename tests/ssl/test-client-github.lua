local http      = require("socket.http")
local copas     = require("copas")
local copashttp = require("copas.http")

local format = string.format

local function TestHttpsGithub ()
  print("Testing LuaSocket HTTPS to github.com...")
  local Body, Code, Headers, Status = http.request("https://github.com")
  local Success
  if (Code == 200) or (Code == 301) or (Code == 302) then
    print(format("Success: HTTP %s", tostring(Code)))
    Success = true
  else
    print(format("Failed: HTTP %s", tostring(Code)))
    Success = false
  end
  return Success
end

local function TestCopasHttpsGithub ()
  print("Testing Copas HTTPS to github.com...")
  local Success
  copas.loop(function()
    local Body, Code, Headers, Status = copashttp.request("https://github.com")
    if (Code == 200) or (Code == 301) or (Code == 302) then
      print(format("Success (Copas): HTTP %s", tostring(Code)))
      Success = true
    else
      print(format("Failed (Copas): HTTP %s", tostring(Code)))
      Success = false
    end
  end)
  return Success
end

local Success1 = TestHttpsGithub()
local Success2 = TestCopasHttpsGithub()
local ExitCode = 1

if Success1 and Success2 then
  print("ALL TESTS PASSED")
  ExitCode = 0
else
  print("SOME TESTS FAILED")
  ExitCode = 1
end

os.exit(ExitCode)




 