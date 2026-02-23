--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile tcc (TinyCC) and libtcc1.
--
-- History
-- Original version: trunk 2025-03-24
--

--------------------------------------------------------------------------------
-- CHECK                                                                      --
--------------------------------------------------------------------------------

---@diagnostic disable: undefined-global

--------------------------------------------------------------------------------
-- HELPERS                                                                    --
--------------------------------------------------------------------------------

local function SourceToObject2 (Pathname, OutputDirectory)
  local Filename   = filename(Pathname)
  -- Remove extension (handle .c and .S)
  local Basename   = Filename:gsub("%.%w+$", "")
  local ObjectName = format("%s/%s.o", OutputDirectory, Basename)
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

local ConfigHeader = nativepath("src/config.h")

local function appendrules (Rules, FlagsTable, Sources, Objects)
  for Index, Source in ipairs(Sources) do
    local Object = Objects[Index]
    append(Rules, format("%s: %s %s", Object, Source, ConfigHeader))
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
-- SPECIAL FOR TCC                                                            --
--------------------------------------------------------------------------------

-- Used for compiling libtcc1 with the just-built tcc.exe
local function CompileCommandTcc (TccExe, FlagsTable, SourceFilename, ObjectFilename)
  local FlagsString = makeflags(FlagsTable)
  -- Same as CompileCommand but tcc instead of $(CC)
  return format("\t%s %s -c %s -o %s", TccExe, FlagsString, SourceFilename, ObjectFilename)
end

-- Same as appendrules but:
--   create dependancy on tcc.exe
--   call CompileCommandTcc
local function appendrules_tcc (Rules, TccExe, FlagsTable, Sources, Objects)
  for Index, Source in ipairs(Sources) do
    local Object = Objects[Index]
    append(Rules, format("%s: %s %s %s", Object, Source, TccExe, ConfigHeader))
    append(Rules, CompileCommandTcc(TccExe, FlagsTable, Source, Object))
    append(Rules, "")
  end
  return Rules
end

--------------------------------------------------------------------------------
-- CONFIG                                                                     --
--------------------------------------------------------------------------------

local BIN_DIR = "bin"

local RuntimeOutputDir

if (TARGET == "windows") then
  RuntimeOutputDir = "x86-64-windows-tcc-runtime"
elseif (TARGET == "linux") then
  RuntimeOutputDir = "x86-64-linux-tcc-runtime"
end

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local GENERIC_Flags = {
  "-ggdb",
  "-fvisibility=hidden",
  "--std=gnu99",
  "-Wall",
  "-Wextra",
}

local PROJECT_Flags = {
  "-Os",
  "-DTCC_TARGET_X86_64",
  header("src"),
  "-Wno-implicit-fallthrough",
  "-Wno-unused-parameter",
  "-Wno-old-style-declaration",
  "-Wno-sign-compare",
  "-Wno-missing-field-initializers",
  "-Wno-shift-negative-value",
  "-Wno-type-limits",
}

if (TARGET == "windows") then
  append(PROJECT_Flags, "-DTCC_TARGET_PE")
elseif (TARGET == "linux") then
  append(PROJECT_Flags, "-DTCC_TARGET_ELF")
  append(PROJECT_Flags, "-DCONFIG_TCC_SWITCHES=\\\"-static\\\"") --TODO ugly
end

if (HOST == "windows") and (TARGET == "windows") then
  append(PROJECT_Flags, "-fdiagnostics-color=never")
end

local LibTccSources = {
  "src/libtcc.c",
  "src/tccpp.c",
  "src/tccgen.c",
  "src/tccdbg.c",
  "src/tccasm.c",
  "src/tccrun.c",
  "src/x86_64-gen.c",
  "src/x86_64-link.c",
  "src/i386-asm.c",
}

if (TARGET == "windows") then
  append(LibTccSources, "src/tccpe.c")
elseif (TARGET == "linux") then
  append(LibTccSources, "src/tccelf.c")
end

local function LibTccSSourceToObject (Pathname)
  return SourceToObject2(Pathname, BIN_DIR)
end

local function SourceToRuntimeObject (Pathname)
  return SourceToObject2(Pathname, RuntimeOutputDir)
end

--------------------------------------------------------------------------------
-- SOURCES & RULES                                                            --
--------------------------------------------------------------------------------

local Rules = {}

-- Create src/config.h
append(Rules, format("%s: libtcc-config.h", ConfigHeader))
append(Rules, format("\t%s libtcc-config.h %s", CP, ConfigHeader))
append(Rules, "")

local TccOneSourceFalse = {
  "-DONE_SOURCE=0",
}

-- libtcc.a
local LibTccNativeSources = map(LibTccSources, nativepath)
local LibTccObjects       = map(LibTccNativeSources, LibTccSSourceToObject)
local LibTccFlags         = mergetables(GENERIC_Flags, PROJECT_Flags)

appendrules(Rules, LibTccFlags, LibTccNativeSources, LibTccObjects)

-- tcc.o (single object for libtccmain.a)
local TccMainSource = { nativepath("src/tcc.c") }
local TccMainObject = map(TccMainSource, LibTccSSourceToObject)
local TccMainFlags  = mergetables(LibTccFlags, TccOneSourceFalse)

appendrules(Rules, TccMainFlags, TccMainSource, TccMainObject)

-- tcc.exe: needed to build embedded tcc runtime libtcc1.a
local TccExeTarget   = nativepath(format("%s/tcc%s",  BIN_DIR, EXE))
local LibTccTarget   = nativepath(format("%s/libtcc.a", BIN_DIR))
local TccExeSource   = nativepath("src/tcc.c")
local TccFlagsString = makeflags(LibTccFlags)

-- Can't simply call appendrules
append(Rules, format("%s: %s %s", TccExeTarget, TccExeSource, LibTccTarget))
append(Rules, format("\t$(CC) %s %s %s -o %s", TccFlagsString, TccExeSource, LibTccTarget, TccExeTarget))
append(Rules, "")

--------------------------------------------------------------------------------
-- RUNTIME                                                                    --
--------------------------------------------------------------------------------

-- libtcc1 (tcc runttime built by tcc.exe)

local LibTcc1Sources = {
  "src/lib/libtcc1.c",
  "src/lib/alloca.S",
  "src/lib/alloca-bt.S",
  "src/lib/stdatomic.c",
  "src/lib/builtin.c",
  "src/lib/atomic.S",
}

local LibTcc1Flags = {
  "-m64",
  "-Bsrc",
  "-Isrc",
  header("src"),
  header("src/include")
}

if (TARGET == "windows") then
  -- Source
  append(LibTcc1Sources, "src/win32/lib/crt1.c")
  append(LibTcc1Sources, "src/win32/lib/crt1w.c")
  append(LibTcc1Sources, "src/win32/lib/wincrt1.c")
  append(LibTcc1Sources, "src/win32/lib/wincrt1w.c")
  append(LibTcc1Sources, "src/win32/lib/dllcrt1.c")
  append(LibTcc1Sources, "src/win32/lib/dllmain.c")
  append(LibTcc1Sources, "src/win32/lib/chkstk.S")
  -- Flags
  append(LibTcc1Flags, format("-B%s", nativepath("src/win32")))
elseif (TARGET == "linux") then
  append(LibTcc1Sources, "src/lib/dsohandle.c")
  -- We disable tcov.c because it depends on GLIBC internal headers not available
  -- append(LibTcc1Sources, "src/lib/tcov.c")
end

local NativeLibTcc1Sources = map(LibTcc1Sources, nativepath)
local NativeLibTcc1Objects = map(NativeLibTcc1Sources, LibTccSSourceToObject)

appendrules_tcc(Rules, TccExeTarget, LibTcc1Flags, NativeLibTcc1Sources, NativeLibTcc1Objects)

--------------------------------------------------------------------------------
-- EXTRA RUNTIME OBJECTS                                                      --
--------------------------------------------------------------------------------

local ExtraRuntimeSources = {
  "src/lib/runmain.c",
}

if (TARGET == "windows") then
  -- append(ExtraRuntimeSources, "src/lib/bt-dll.c")
  -- On Linux bt-exe need libc headers
  append(ExtraRuntimeSources, "src/lib/bt-exe.c")
  append(ExtraRuntimeSources, "src/lib/bt-log.c")
end

local NativeExtraRuntimeSources = map(ExtraRuntimeSources, nativepath)
local NativeExtraRuntimeObjects = map(NativeExtraRuntimeSources, SourceToRuntimeObject)

appendrules_tcc(Rules, TccExeTarget, LibTcc1Flags, NativeExtraRuntimeSources, NativeExtraRuntimeObjects)

local AllRuntimeObjects
if (TARGET == "windows") then
  -- bcheck.o needs -bt flag

  local BCheckSource       = { "src/lib/bcheck.c" }
  local NativeBCheckSource = map(BCheckSource, nativepath)
  local NativeBCheckObject = map(NativeBCheckSource, SourceToRuntimeObject)
  local BCheckFlags        = mergetables(LibTcc1Flags, { "-bt" })

  appendrules_tcc(Rules, TccExeTarget, BCheckFlags, NativeBCheckSource, NativeBCheckObject)

  AllRuntimeObjects = mergetables(NativeExtraRuntimeObjects, NativeBCheckObject)
else
  AllRuntimeObjects = NativeExtraRuntimeObjects
end

--------------------------------------------------------------------------------
-- WINDOWS DEF FILES                                                          --
--------------------------------------------------------------------------------

local DefTargets = {}

if (TARGET == "windows") then
  local DefNames = {
    "src/win32/lib/gdi32.def",
    "src/win32/lib/kernel32.def",
    "src/win32/lib/msvcrt.def",
    "src/win32/lib/user32.def",
    "src/win32/lib/ws2_32.def",
  }
  for Index, Source in ipairs(DefNames) do
    local SourceFile = nativepath(Source)
    local TargetFile = nativepath(format("%s/%s", RuntimeOutputDir, filename(Source)))
    append(Rules, format("%s: %s", TargetFile, SourceFile))
    append(Rules, format("\t%s %s %s", CP, SourceFile, TargetFile))
    append(Rules, "")
    append(DefTargets, TargetFile)
  end
end

--------------------------------------------------------------------------------
-- MAKEFILE                                                                   --
--------------------------------------------------------------------------------

local Environment = {
  RULES            = finalizerules(Rules),
  RUNTIME_DIR      = nativepath(RuntimeOutputDir),
  CONFIG_HEADER    = ConfigHeader,
  LIBTCC_OBJECTS   = concat(LibTccObjects, " "),
  LIBTCC_LIB       = LibTccTarget,
  LIBTCCMAIN_LIB   = nativepath(format("%s/libtccmain.a", BIN_DIR)),
  TCC_EXE          = TccExeTarget,
  LIBTCC1_LIB      = nativepath(format("%s/libtcc1.a", RuntimeOutputDir)),
  LIBTCC1_OBJECTS  = concat(NativeLibTcc1Objects, " "),
  RUNTIME_OBJECTS  = concat(AllRuntimeObjects, " "),
  TCCMAIN_OBJECT   = concat(TccMainObject, " "),
  RM               = RM,
  RUNTIME_DEF_FILES = concat(DefTargets, " ")
}

local MakefileTemplate = [[
.PHONY: all clean

all: $CONFIG_HEADER $LIBTCC_LIB $LIBTCCMAIN_LIB $TCC_EXE $LIBTCC1_LIB $RUNTIME_OBJECTS $RUNTIME_DEF_FILES

$RULES

$LIBTCC_LIB: $LIBTCC_OBJECTS
	ar rcs $@ $^

$LIBTCCMAIN_LIB: $TCCMAIN_OBJECT
	ar rcs $@ $^

$LIBTCC1_LIB: $LIBTCC1_OBJECTS
	$TCC_EXE -m64 -ar $@ $^

clean:
	$RM $CONFIG_HEADER $LIBTCC_OBJECTS $LIBTCC_LIB $LIBTCCMAIN_LIB $TCC_EXE $LIBTCC1_OBJECTS $LIBTCC1_LIB $TCCMAIN_OBJECT $RUNTIME_OBJECTS $RUNTIME_DEF_FILES
]]

generate(Environment, MakefileTemplate)
