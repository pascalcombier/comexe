--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Lua 5.5: the static library

-- History
-- Update lua-5.4.7
-- Update lua-5.4.8
-- Update lua-5.5.0
-- Update lua-5.5.1

-- The static library is built with -fPIC on Linux so it can be linked against
-- shared libraries
--
-- Do not emit a -flto at link time, it shall be working in principle, but
-- failed to link properly for the Windows PE target, raising an error. Omitting
-- the flag at link time is not a big deal, clang/zig will use FLTO
-- automatically if a given object as been built with -flto flag.

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local LibSources = {
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

--------------------------------------------------------------------------------
-- FLAGS                                                                      --
--------------------------------------------------------------------------------

local GenericFlags = {
  "-fvisibility=hidden",
  "--std=c99",
  "-Wall",
  "-Wextra",
  "-ggdb",
}

local ComponentFlags = {
  "-Os",
  "-target $TRIPLE",
}

local LinuxFlags = {
  "-fPIC",
  "-DLUA_USE_DLOPEN",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Return rule output (for map call)
  local function RuleOutput (Rule)
    return Rule.Out
  end
  -- Evaluate final flags
  local ProjectFlags
  if (Environment.OS == "linux") then
    ProjectFlags = merge(ComponentFlags, LinuxFlags)
  else
    ProjectFlags = ComponentFlags
  end
  -- Compile adds -flto for object files only, NOT for link
  local CompileFlags = merge(GenericFlags, ProjectFlags, "-flto")
  -- Create a RULE for a given source file
  local function MakeCompileRule (Source)
    local FlagsString = concat(CompileFlags, " ")
    local Path        = format("$DIR/%s", Source)
    local Name, Basename, Extension = newpathname(Path):getname()
    assert((Extension == "c"), format("source is not a C file (got %q)", Path))
    local NewRule = {
      Ins = { Path },
      Run = { format("zig cc %s -c $IN -o $OUT", FlagsString) },
      Out = format("bin/$TRIPLE/$NAME/%s.o", Basename),
    }
    return NewRule
  end
  -- Create a specific target for each source file
  local ObjectRules = map(LibSources, MakeCompileRule)
  -- Retrieve objects files
  local LibObjects = map(ObjectRules, RuleOutput)
  -- Rule to build the static archive
  local ArchiveRule = {
    Ins = LibObjects,
    Run = { "zig ar rcs $OUT $INS" },
    Out = "bin/$TRIPLE/$NAME/liblua.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(ObjectRules, ArchiveRule),
    Artifacts = { ArchiveRule.Out },
  }
  return Result
end

return Render
