--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Original version: libuv-v1.23.2
-- Update:           libuv-v1.24.0
-- Update:           libuv-v1.26.0
-- Update:           libuv-v1.28.0
-- Update:           libuv-v1.29.0
-- Update:           libuv-v1.29.1
-- Update:           libuv-v1.39.0
-- Update:           libuv-v1.44.1
-- Update:           libuv-v1.44.2
-- Update            libuv-v1.49.2
-- Update            libuv-v1.50.0
-- Update            libuv-v1.51.0
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

-- Hide libuv warnings due to MinGW being Tiers-3 platform
-- https://github.com/libuv/libuv/issues/2523

local PROJECT_Flags = {
  "-Os",
  header("include"),
  header("src"),
  "-Wno-unused-parameter",
  "-Wno-missing-braces",
  "-Wno-maybe-uninitialized",
  "-Wno-sign-compare",
  "-Wno-cast-function-type",
}

if (TARGET == "linux") then
  append(PROJECT_Flags, "-D_GNU_SOURCE")
  append(PROJECT_Flags, "-D_FILE_OFFSET_BIT=64")
  append(PROJECT_Flags, "-D_LARGEFILE_SOURCE")
  append(PROJECT_Flags, "-pthread")
  append(PROJECT_Flags, "-Wno-format-truncation")
end

if (HOST == "windows") and (TARGET == "windows") then
  append(PROJECT_Flags, "-fdiagnostics-color=never")
end

local LibSources = {
  "src/fs-poll.c",
  "src/idna.c",
  "src/inet.c",
  "src/random.c",
  "src/strscpy.c",
  "src/strtok.c",
  "src/thread-common.c",
  "src/threadpool.c",
  "src/timer.c",
  "src/uv-common.c",
  "src/uv-data-getter-setters.c",
  "src/version.c",
}

if (TARGET == "windows") then
  append(LibSources, "src/win/async.c")
  append(LibSources, "src/win/core.c")
  append(LibSources, "src/win/detect-wakeup.c")
  append(LibSources, "src/win/dl.c")
  append(LibSources, "src/win/error.c")
  append(LibSources, "src/win/fs.c")
  append(LibSources, "src/win/fs-event.c")
  append(LibSources, "src/win/getaddrinfo.c")
  append(LibSources, "src/win/getnameinfo.c")
  append(LibSources, "src/win/handle.c")
  append(LibSources, "src/win/loop-watcher.c")
  append(LibSources, "src/win/pipe.c")
  append(LibSources, "src/win/poll.c")
  append(LibSources, "src/win/process.c")
  append(LibSources, "src/win/process-stdio.c")
  append(LibSources, "src/win/signal.c")
  append(LibSources, "src/win/snprintf.c")
  append(LibSources, "src/win/stream.c")
  append(LibSources, "src/win/tcp.c")
  append(LibSources, "src/win/thread.c")
  append(LibSources, "src/win/tty.c")
  append(LibSources, "src/win/udp.c")
  append(LibSources, "src/win/util.c")
  append(LibSources, "src/win/winapi.c")
  append(LibSources, "src/win/winsock.c")
elseif (TARGET == "linux") then
  -- core
  append(LibSources, "src/unix/async.c")
  append(LibSources, "src/unix/core.c")
  append(LibSources, "src/unix/dl.c")
  append(LibSources, "src/unix/fs.c")
  append(LibSources, "src/unix/getaddrinfo.c")
  append(LibSources, "src/unix/getnameinfo.c")
  append(LibSources, "src/unix/loop.c")
  append(LibSources, "src/unix/loop-watcher.c")
  append(LibSources, "src/unix/pipe.c")
  append(LibSources, "src/unix/poll.c")
  append(LibSources, "src/unix/process.c")
  append(LibSources, "src/unix/proctitle.c")
  append(LibSources, "src/unix/signal.c")
  append(LibSources, "src/unix/stream.c")
  append(LibSources, "src/unix/tcp.c")
  append(LibSources, "src/unix/thread.c")
  append(LibSources, "src/unix/tty.c")
  append(LibSources, "src/unix/udp.c")
  -- linux specific
  append(LibSources, "src/unix/linux.c")
  append(LibSources, "src/unix/random-getrandom.c")
  append(LibSources, "src/unix/random-devurandom.c")
  -- append(LibSources, "src/unix/random-sysctl-linux.c") deprecated, not available in musl
  append(LibSources, "src/unix/procfs-exepath.c")
  -- Those are posix (for BSD for exammple), same functions as linux.c
  -- append(LibSources, "src/unix/posix-hrtime.c")
  -- append(LibSources, "src/unix/sysinfo-loadavg.c")
  -- append(LibSources, "src/unix/sysinfo-memory.c")
  -- append(LibSources, "src/unix/random-getentropy.c")
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
  STATIC_LIB = nativepath("bin/libuv.a"),
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
