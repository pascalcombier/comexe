local Error = io.stderr

local function SlurpFile(Filename)
  local File = io.open(Filename, "rb")
  local Content = nil
  if File then
    Content = File:read("a")
    File:close()
  end
  return Content
end

if #arg < 2 then
  Error:write("ERROR: Usage: CAT in-file1 [in-file2 ...] out-file\n")
  os.exit(1)
end

local OutputFilename = arg[#arg]
local OutputFile = io.open(OutputFilename, "wb")
if not OutputFile then
  Error:write(string.format("ERROR: %s could not be opened for writing\n", OutputFilename))
  os.exit(1)
end

for Index = 1, #arg - 1 do
  local Filename = arg[Index]
--  print(Filename)
  local Content  = SlurpFile(Filename)
  if Content then
    OutputFile:write(Content)
  else
    Error:write(string.format("ERROR: %s could not be read\n", Filename))
  end
end

OutputFile:close()
