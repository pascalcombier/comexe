--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Original version: https://github.com/neoxic/lua-mbedtls (trunk, 0.2.2)
--

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local Sources = {
  "src/base64.c",
  "src/main.c",
  "src/md.c",
  "src/ssl.c",
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
  "-DMBEDTLS_DECLARE_PRIVATE_IDENTIFIERS",
  "-I$Pthird-party/src/lua/src",
  "-I$Pthird-party/src/mbedtls/include",
  "-I$Pthird-party/src/mbedtls/src/tf-psa-crypto/include",
  "-I$Pthird-party/src/mbedtls/src/tf-psa-crypto/drivers/builtin/include",
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
  local BuildFlags = merge(GenericFlags, ComponentFlags)
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
    Needs = {
      "bin/$TRIPLE/lua/liblua.a",
      "bin/$TRIPLE/mbedtls/libtfpsacrypto.a",
      "bin/$TRIPLE/mbedtls/libmbedtls.a",
    },
    Ins = ObjectList,
    Run = { "zig ar rcs $OUT $INS" },
    Out = "bin/$TRIPLE/$NAME/libluambedtls.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(ObjectRules, ArchiveRule),
    Artifacts = { ArchiveRule.Out },
  }
  return Result
end

return Render
