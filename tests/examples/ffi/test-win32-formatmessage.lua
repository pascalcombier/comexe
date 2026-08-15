local libffi = require("com.ffi")
local win32  = require("com.win32")

-- @BEGIN FfiDeclarations("BindLibrary", "libffi")
-- int CopyFileA(void *Source, void *Target, int FailIfExists);
-- @OUTPUT
-- Functions
local CopyFileA
-- Binding function
local function BindLibrary (Library)
  CopyFileA = Library:bind(libffi.sint32, "CopyFileA", libffi.pointer, libffi.pointer, libffi.sint32)
end
-- @END

local Kernel32 = libffi.loadlib("kernel32.dll")
BindLibrary(Kernel32)

if (CopyFileA("Z:\\this-file-does-not-exist.txt", "C:\\target.txt", 0) == 0) then
  local ErrorCode = win32.getlasterror()
  print(win32.formatmessage(ErrorCode))
  print("TEST PASSED")
else
  error("CopyFileA should have failed")
end
