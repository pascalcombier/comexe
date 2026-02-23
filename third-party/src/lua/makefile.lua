--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Update lua-5.4.7
-- Update lua-5.4.8
-- Update lua-5.5.0
--

--------------------------------------------------------------------------------
-- LUACHECK                                                                   --
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
-- HELPERS                                                                    --
--------------------------------------------------------------------------------

local Sources = {
  "src/lapi.c",
  "src/lauxlib.c",
  "src/lbaselib.c",
  "src/lcode.c",
  "src/lcorolib.c",
  "src/lctype.c",
  "src/ldblib.c",
  "src/ldebug.c",
  "src/ldo.c",
  "src/ldump.c",
  "src/lfunc.c",
  "src/lgc.c",
  "src/linit.c",
  "src/liolib.c",
  "src/llex.c",
  "src/lmathlib.c",
  "src/lmem.c",
  "src/loadlib.c",
  "src/lobject.c",
  "src/lopcodes.c",
  "src/loslib.c",
  "src/lparser.c",
  "src/lstate.c",
  "src/lstring.c",
  "src/lstrlib.c",
  "src/ltable.c",
  "src/ltablib.c",
  "src/ltm.c",
  "src/lundump.c",
  "src/lutf8lib.c",
  "src/lvm.c",
  "src/lzio.c",
}

local GENERIC_Flags = {
  "-fvisibility=hidden",
  "--std=c99",
  "-Wall",
  "-Wextra",
  "-ggdb",
}

-- We use c99 instead of c89 because on Linux gcc complain about the "inline"

local PROJECT_Flags = {
  "-Os",
}

if (HOST == "windows") and (TARGET == "windows") then
  append(PROJECT_Flags, "-fdiagnostics-color=never")
end

--------------------------------------------------------------------------------
-- LOCAL DATA                                                                 --
--------------------------------------------------------------------------------

local Rules = {}

local NativeSources = map(Sources,       nativepath)
local Objects       = map(NativeSources, SourceToObject)
local FlagsTable    = mergetables(GENERIC_Flags, PROJECT_Flags)
local FlagsString   = makeflags(FlagsTable)

appendrules(Rules, FlagsTable, NativeSources, Objects)

-- lua.o rule
local SourceLuaDotC = { nativepath("src/lua.c") }
local LuaObject     = { nativepath("bin/lua.o") }
appendrules(Rules, FlagsTable, SourceLuaDotC, LuaObject)

--------------------------------------------------------------------------------
-- MAKEFILE                                                                   --
--------------------------------------------------------------------------------

local LUA_EXE_FILENAME

if (TARGET == "windows") then
  LUA_EXE_FILENAME = "lua55.exe"
else
  LUA_EXE_FILENAME = "lua55"
end

local Environment = {
  RULES      = finalizerules(Rules),
  OBJECTS    = concat(Objects, " "),
  LUA_OBJECT = concat(LuaObject, " "),
  STATIC_LIB = nativepath("bin/liblua.a"),
  LUA_EXE    = nativepath(format("bin/%s", LUA_EXE_FILENAME)),
  FLAGS      = FlagsString,
  RM         = RM,
}

local MakefileTemplate = [[
.PHONY: all clean

all: $STATIC_LIB $LUA_EXE

$RULES

$STATIC_LIB: $OBJECTS
	ar rcs $@ $^

$LUA_EXE: $OBJECTS $LUA_OBJECT
	$(CC) $FLAGS -o $@ $^ -lm

clean:
	$RM $OBJECTS $STATIC_LIB $LUA_EXE $LUA_OBJECT
]]

generate(Environment, MakefileTemplate)
