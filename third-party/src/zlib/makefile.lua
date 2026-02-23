--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- zlib 1.3.1
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

local PROJECT_Flags = {
  "-Os",
  "-Wno-attributes",
}

if (HOST == "windows") and (TARGET == "windows") then
  append(PROJECT_Flags, "-fdiagnostics-color=never")
end

local LibSources = {
  "src/adler32.c",
  "src/crc32.c",
  "src/deflate.c",
  "src/infback.c",
  "src/inffast.c",
  "src/inflate.c",
  "src/inftrees.c",
  "src/trees.c",
  "src/zutil.c",
  "src/compress.c",
  "src/uncompr.c",
  "src/gzclose.c",
  "src/gzlib.c",
  "src/gzread.c",
  "src/gzwrite.c",
}

local LibFlags = {
  "-D_LARGEFILE64_SOURCE=1",
}

local MinizipSources = {
  "src/contrib/minizip/ioapi.c",
  "src/contrib/minizip/mztools.c",
  "src/contrib/minizip/unzip.c",
  "src/contrib/minizip/zip.c",
}

local MinizipFlags = {
  header("src"),
  "-D_GNU_SOURCE",
  "-D_LARGEFILE64_SOURCE=1",
}

if (TARGET == "windows") then
  append(MinizipFlags,   "-DUSE_FILE32API")
  append(MinizipSources, "src/contrib/minizip/iowin32.c")
  append(MinizipFlags,   "-Wno-unused-variable")
  append(MinizipFlags,   "-Wno-unused-parameter")
end

--------------------------------------------------------------------------------
-- LOCAL DATA                                                                 --
--------------------------------------------------------------------------------

local Rules = {}

-- libz
local NativeLibSources = map(LibSources, nativepath)
local NativeLibObjects = map(NativeLibSources, SourceToObject)
local LibFlag          = mergetables(GENERIC_Flags, PROJECT_Flags, LibFlags)

appendrules(Rules, LibFlag, NativeLibSources, NativeLibObjects)

-- minizip
local NativeMinizipSources = map(MinizipSources, nativepath)
local NativeMinizipObjects = map(NativeMinizipSources, SourceToObject)
local MinizipFlag          = mergetables(GENERIC_Flags, PROJECT_Flags, MinizipFlags)

appendrules(Rules, MinizipFlag, NativeMinizipSources, NativeMinizipObjects)

--------------------------------------------------------------------------------
-- MAKEFILE                                                                   --
--------------------------------------------------------------------------------

local Environment = {
  RULES           = finalizerules(Rules),
  LIBZ_OBJECTS    = concat(NativeLibObjects, " "),
  MINIZIP_OBJECTS = concat(NativeMinizipObjects, " "),
  LIBZ_LIB        = nativepath("bin/libz.a"),
  LIBMINIZIP_LIB  = nativepath("bin/libminizip.a"),
  RM              = RM,
}

local MakefileTemplate = [[
.PHONY: all clean

all: $LIBZ_LIB $LIBMINIZIP_LIB

$RULES

$LIBZ_LIB: $LIBZ_OBJECTS
	ar rcs $@ $^

$LIBMINIZIP_LIB: $MINIZIP_OBJECTS
	ar rcs $@ $^

clean:
	$RM $LIBZ_OBJECTS $MINIZIP_OBJECTS $LIBZ_LIB $LIBMINIZIP_LIB
]]

generate(Environment, MakefileTemplate)
