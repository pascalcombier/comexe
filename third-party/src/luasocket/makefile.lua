--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Original version: luasocket-trunk (after 3.1.0)
--

--------------------------------------------------------------------------------
-- CHECK                                                                      --
--------------------------------------------------------------------------------

---@diagnostic disable: undefined-global

--------------------------------------------------------------------------------
-- HELPERS                                                                    --
--------------------------------------------------------------------------------

local function SourceToObject (Pathname)
  local Filename   = filename(Pathname)
  local Basename   = removeext(Filename, ".c")
  local ObjectName = format("bin/%s.o", Basename)
  return nativepath(ObjectName)
end

local function makeflags (FlagsTable)
  local FlagsString = concat(FlagsTable, " ")
  return FlagsString
end

local function CompileCommand (FlagsTable, SourceFilename, ObjectFilename)
  local FlagsString = makeflags(FlagsTable)
  return format("\t$(CC) %s -c %s -o %s", FlagsString, SourceFilename, ObjectFilename)
end

local function header (Pathname)
  local NativePathname = nativepath(Pathname)
  return format("-I%s", NativePathname)
end

local function appendrules (Rules, FlagsTable, Sources, Objects)
  for Index, Source in ipairs(Sources) do
    local Object = Objects[Index]
    append(Rules, format("%s: %s", Object, Source))
    append(Rules, CompileCommand(FlagsTable, Source, Object))
    append(Rules, "")
  end
  return Rules
end

local function finalizerules (Rules)
  -- Remove all the empty lines at the end
  while (#Rules > 0) and (Rules[#Rules] == "") do
    Rules[#Rules] = nil
  end
  -- New lines
  return concat(Rules, "\n")
end

--------------------------------------------------------------------------------
-- CONFIG                                                                     --
--------------------------------------------------------------------------------

local GENERIC_Flags = {
  "-ggdb",
  "-fvisibility=hidden",
  "--std=c99",
  "-Wall",
  "-Wextra",
}

-- We use c99 instead of c89 because we need long long

local PROJECT_Flags = {
  "-Os",
  "-Wno-unused-parameter",
  header("../lua/src"),
}

if (TARGET == "linux") then
  append(PROJECT_Flags, "-D_GNU_SOURCE")
end

if (HOST == "windows") and (TARGET == "windows") then
  append(PROJECT_Flags, "-fdiagnostics-color=never")
end

local LibSources = {
  "src/auxiliar.c",
  "src/buffer.c",
  "src/compat.c",
  "src/except.c",
  "src/inet.c",
  "src/io.c",
  "src/luasocket.c",
  "src/mime.c",
  "src/options.c",
  "src/select.c",
  "src/tcp.c",
  "src/timeout.c",
  "src/udp.c",
}

if (TARGET == "windows") then
  append(LibSources, "src/wsocket.c")
else
  append(LibSources, "src/usocket.c")
  append(LibSources, "src/unix.c")
  append(LibSources, "src/serial.c")
  append(LibSources, "src/unixdgram.c")
  append(LibSources, "src/unixstream.c")
end

--------------------------------------------------------------------------------
-- LOCAL DATA                                                                 --
--------------------------------------------------------------------------------

local Rules = {}

local NativeSources = map(LibSources,    nativepath)
local Objects       = map(NativeSources, SourceToObject)
local FlagsTable    = mergetables(GENERIC_Flags, PROJECT_Flags)

appendrules(Rules, FlagsTable, NativeSources, Objects)

--------------------------------------------------------------------------------
-- MAKEFILE                                                                   --
--------------------------------------------------------------------------------

local Environment = {
  RULES      = finalizerules(Rules),
  OBJECTS    = concat(Objects, " "),
  STATIC_LIB = nativepath("bin/libluasocket.a"),
  RM         = RM,
}

local MakefileTemplate = [[
.PHONY: all clean

all: $STATIC_LIB

$RULES

$STATIC_LIB: $OBJECTS
	ar rcs $@ $^

clean:
	$RM $OBJECTS $STATIC_LIB
]]

generate(Environment, MakefileTemplate)
