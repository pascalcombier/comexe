--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Original version: luv-trunk
-- Update            luv-1.51.0-1
--

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local Sources = {
  "src/luv.c",
}

-------------------------------------------------------------------------------
-- FLAGS                                                                      --
-------------------------------------------------------------------------------

local GenericFlags = {
  "-ggdb",
  "-fvisibility=hidden",
  "--std=c99",
  "-Wall",
  "-Wextra",
  "-flto",
}

local ComponentFlags = {
  "-Os",
  "-I$Pthird-party/src/lua/src",
  "-I$Pthird-party/src/libuv/include",
  "-Wno-missing-braces",
  "-Wno-sign-compare",
  "-Wno-unused-function",
  "-Wno-maybe-uninitialized",
  "-target $TRIPLE",
}

local LinuxFlags = {
  "-D_GNU_SOURCE",
  "-D_FILE_OFFSET_BIT=64",
  "-D_LARGEFILE_SOURCE",
  "-pthread",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Return rule output (for map call)
  local function RuleOutput (Rule)
    return Rule.Out
  end
  -- Evaluate final flags per OS
  local BuildFlags
  if (Environment.OS == "linux") then
    BuildFlags = merge(GenericFlags, ComponentFlags, LinuxFlags)
  else
    BuildFlags = merge(GenericFlags, ComponentFlags)
  end
  -- Create a RULE for a given source file
  local function MakeCompileRule (Source)
    local FlagsString = concat(BuildFlags, " ")
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
  local ObjectRules = map(Sources, MakeCompileRule)
  -- Retrieve all the object files (stored in Rules[Index].Out)
  local ObjectList = map(ObjectRules, RuleOutput)
  -- Rule to build the archive
  local ArchiveRule = {
    Ins = ObjectList,
    Run = { "zig ar rcs $OUT $INS" },
    Out = "bin/$TRIPLE/$NAME/libluv.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(ObjectRules, ArchiveRule),
    Artifacts = { ArchiveRule.Out },
  }
  return Result
end

return Render
