local ffi = require("com.ffi")

local libc = ffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so")

-- Attach the interface (multiple interface can be attached)
libc:load("tiny-libc-ffi")

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
