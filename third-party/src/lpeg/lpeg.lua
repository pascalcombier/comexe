--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Library written by Roberto Ierusalimschy
--
-- History
-- LPeg 1.1.0

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local Sources = {
  "src/lpcap.c",
  "src/lpcode.c",
  "src/lpcset.c",
  "src/lpprint.c",
  "src/lptree.c",
  "src/lpvm.c",
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
  "-I$P$DIR/src",
  "-I$Pthird-party/src/lua/src",
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
  -- Evaluate final flags
  local ObjectFlags = merge(GenericFlags, ComponentFlags)
  -- Create a RULE for a given source file
  local function MakeCompileRule (Source)
    local FlagsString = concat(ObjectFlags, " ")
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
    Needs = { "bin/$TRIPLE/lua/liblua.a" },
    Ins   = ObjectList,
    Run   = { "zig ar rcs $OUT $INS" },
    Out   = "bin/$TRIPLE/$NAME/liblpeg.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(ObjectRules, ArchiveRule),
    Artifacts = { ArchiveRule.Out },
  }
  return Result
end

return Render
