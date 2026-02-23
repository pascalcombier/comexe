local Output = io.stdout
local Error  = io.stderr

local SilentErrors = false

-- Handle only positive args
for Index = 1, #arg do
  local Filename = arg[Index]
  if (Filename == "-f") then
    SilentErrors = true
  else
    local Success, ErrorMessage = os.remove(Filename)
    if (not SilentErrors) and (not Success) then
      Error:write(string.format("%s\n", ErrorMessage))
    end
  end
end
