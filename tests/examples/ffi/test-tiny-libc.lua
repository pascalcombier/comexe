--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.ffi")

--------------------------------------------------------------------------------
-- FFI IMPORTS                                                                --
--------------------------------------------------------------------------------

-- @BEGIN import-c-header
-- @PARAM file tiny-libc.h
-- @PARAM function BindLibrary
-- @PARAM lib libffi
-- @OUTPUT
-- Functions
local free
local malloc
local puts
local qsort
local sprintf
-- Binding function
local function BindLibrary (Library)
  free = Library:bind(libffi.void, "free", libffi.pointer)
  malloc = Library:bind(libffi.pointer, "malloc", libffi.uint64)
  puts = Library:bind(libffi.sint32, "puts", libffi.pointer)
  qsort = Library:bind(libffi.void, "qsort", libffi.pointer, libffi.uint64, libffi.uint64, libffi.pointer)
  sprintf = Library:variadicbind(libffi.sint32, "sprintf", libffi.pointer, libffi.pointer)
end
-- @END

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

-- Load DLL and attach FFI interface
local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so", "linux", "libc.so.6")
BindLibrary(libc)

local Buffer = malloc(1024)

if (Buffer ~= libffi.NULL) then
  local Count = sprintf(Buffer, "Hello, %s! int=%d float=%f", "FFI", 42, 3.14)
  print(string.format("snprintf returned %d", Count))
  puts(Buffer)
  free(Buffer)
  print("OK")
else
  error("sprintf failed")
end
