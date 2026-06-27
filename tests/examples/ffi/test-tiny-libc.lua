local ffi     = require("com.ffi")
local LibcFfi = require("tiny-libc-ffi")

-- Load DLL and attach FFI interface (multiple interface can be attached)
local libc = ffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so", "linux", "libc.so.6")
libc:attach(LibcFfi)

local Buffer = libc.malloc(1024)

if (Buffer ~= ffi.NULL) then
  local Count = libc.sprintf(Buffer, "Hello, %s! int=%d float=%f", "FFI", 42, 3.14)
  print(string.format("snprintf returned %d", Count))
  libc.puts(Buffer)
  libc.free(Buffer)
  print("OK")
else
  error("sprintf failed")
end
