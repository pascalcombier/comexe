--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Original version: mimalloc
-- Update to 3.0.3
-- Update to 3.0.11
-- Update to 3.2.8
--

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local CommonSources = {
  "src/alloc-aligned.c",
  "src/alloc.c",
  "src/alloc-posix.c",
  "src/arena.c",
  "src/arena-meta.c",
  "src/bitmap.c",
  "src/heap.c",
  "src/init.c",
  "src/libc.c",
  "src/options.c",
  "src/os.c",
  "src/theap.c",
  "src/threadlocal.c",
  "src/page.c",
  "src/page-map.c",
  "src/random.c",
  "src/stats.c",
}

local PrimSources = {
  "src/prim/prim.c",
}

--------------------------------------------------------------------------------
-- FLAGS                                                                      --
--------------------------------------------------------------------------------

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
  "-I$P$DIR/include",
  "-Wno-unknown-pragmas",
  "-Wno-attributes",
  "-Wno-array-bounds",
  "-Wno-incompatible-pointer-types",
  "-Wno-date-time",
  "-target $TRIPLE",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render ()
  -- Return rule output (for map call)
  local function RuleOutput (Rule)
    return Rule.Out
  end
  -- Evaluate final flags and sources
  local BuildFlags = merge(GenericFlags, ComponentFlags)
  local Sources    = merge(CommonSources, PrimSources)
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
  -- Retrieve objects files from Rules[Index].Out
  local ObjectList = map(ObjectRules, RuleOutput)
  -- Rule to build the archive
  local ArchiveRule = {
    Ins = ObjectList,
    Run = { "zig ar rcs $OUT $INS" },
    Out = "bin/$TRIPLE/$NAME/libmimalloc.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(ObjectRules, ArchiveRule),
    Artifacts = { ArchiveRule.Out },
  }
  return Result
end

return Render
