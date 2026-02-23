--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Original version: libffi-3.4.6
-- Update:           libffi-3.5.2
--

--------------------------------------------------------------------------------
-- CHECK                                                                      --
--------------------------------------------------------------------------------

---@diagnostic disable: undefined-global

--------------------------------------------------------------------------------
-- HELPERS                                                                    --
--------------------------------------------------------------------------------

local function SourceToObject2 (Pathname)
  local Filename   = filename(Pathname)
  local Basename   = (removeext(Filename, ".c") or removeext(Filename, ".S"))
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
  "-fvisibility=hidden",
  "--std=c99",
  "-Wall",
  "-Wextra",
  "-ggdb",
}

local PROJECT_Flags = {
  "-O2",
  "-fomit-frame-pointer",
  "-DHAVE_CONFIG_H",
  header("include"),
  "-Wno-unused-parameter",
  "-Wno-deprecated-declarations",
  "-Wno-empty-body",
  "-Wno-implicit-fallthrough",
}

if (TARGET == "linux") then
  append(PROJECT_Flags, header("config-linux"))
  append(PROJECT_Flags, "-D_GNU_SOURCE")
end

if (TARGET == "windows") then
  append(PROJECT_Flags, header("config-windows"))
  append(PROJECT_Flags, "-DX86_WIN64")
end

if (HOST == "windows") and (TARGET == "windows") then
  append(PROJECT_Flags, "-fdiagnostics-color=never")
end

local LibSources = {
  "src/prep_cif.c",
  "src/types.c",
  "src/raw_api.c",
  "src/java_raw_api.c",
  "src/closures.c",
  "src/tramp.c",
}

if (TARGET == "windows") then
  append(LibSources, "src/x86/ffiw64.c")
  append(LibSources, "src/x86/win64.S")
elseif (TARGET == "linux") then
  append(LibSources, "src/x86/ffi64.c")
  append(LibSources, "src/x86/unix64.S")
  append(LibSources, "src/x86/ffiw64.c")
  append(LibSources, "src/x86/win64.S")
end

--------------------------------------------------------------------------------
-- LOCAL DATA                                                                 --
--------------------------------------------------------------------------------

local Rules = {}

local NativeSources = map(LibSources,    nativepath)
local Objects       = map(NativeSources, SourceToObject2)
local FlagsTable    = mergetables(GENERIC_Flags, PROJECT_Flags)

appendrules(Rules, FlagsTable, NativeSources, Objects)

--------------------------------------------------------------------------------
-- MAKEFILE                                                                   --
--------------------------------------------------------------------------------

local Environment = {
  RULES      = finalizerules(Rules),
  OBJECTS    = concat(Objects, " "),
  STATIC_LIB = nativepath("bin/libffi.a"),
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
