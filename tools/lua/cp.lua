local Output = io.stdout
local Error  = io.stderr

local function SlurpFile(Filename)
  local File = io.open(Filename, "rb")
  local Content
  if File then
    Content = File:read("a")
    File:close()
  end
  return Content
end

if (#arg < 2) then
  Error:write("Usage: cp INPUT OUTPUT\n")
  os.exit(1)
end

local InputFile  = arg[1]
local OutputFile = arg[2]
local Content    = SlurpFile(InputFile)

if not Content then
  Error:write(string.format("ERROR: %s could not be read\n", InputFile))
  os.exit(1)
end

local OutputHandle = io.open(OutputFile, "wb")
if not OutputHandle then
  Error:write(string.format("ERROR: %s could not be written\n", OutputFile))
  os.exit(1)
end

OutputHandle:write(Content)
OutputHandle:close()
