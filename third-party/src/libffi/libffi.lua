--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Original version libffi-3.4.6
-- Update           libffi-3.5.2
-- Update           libffi-3.7.1
--

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local CommonSources = {
  "src/prep_cif.c",
  "src/types.c",
  "src/raw_api.c",
  "src/java_raw_api.c",
  "src/closures.c",
  "src/tramp.c",
}

-- Linux ABI: SysV64
local SysV64Sources = {
  "src/x86/ffi64.c",
  "src/x86/unix64.S",
}

local Win64Sources = {
  "src/x86/ffiw64.c",
  "src/x86/win64.S",
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
  "-flto",
}

local ComponentFlags = {
  "-Os",
  "-fomit-frame-pointer",
  "-DHAVE_CONFIG_H",
  "-I$P$DIR/include",
  "-Wno-unused-parameter",
  "-Wno-deprecated-declarations",
  "-Wno-empty-body",
  "-Wno-implicit-fallthrough",
  "-target $TRIPLE",
}

local WindowsFlags = {
  "-I$P$DIR/config-windows",
  "-DX86_WIN64",
}

local LinuxFlags = {
  "-I$P$DIR/config-linux",
  "-D_GNU_SOURCE",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Return rule output (for map call)
  local function RuleOutput (Rule)
    return Rule.Out
  end
  -- Evaluate final flags and sources
  local BuildFlags
  local Sources
  if (Environment.OS == "windows") then
    BuildFlags = merge(GenericFlags, ComponentFlags, WindowsFlags)
    Sources    = merge(CommonSources, Win64Sources)
  else
    BuildFlags = merge(GenericFlags, ComponentFlags, LinuxFlags)
    Sources    = merge(CommonSources, SysV64Sources, Win64Sources)
  end
  -- Create a RULE for a source file (.c or .S)
  local function MakeCompileRule (Source)
    local FlagsString = concat(BuildFlags, " ")
    local Path        = format("$DIR/%s", Source)
    local Name, Basename, Extension = newpathname(Path):getname()
    assert(((Extension == "c") or (Extension == "S")), format("source is not a C/S file (got %q)", Path))
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
    Out = "bin/$TRIPLE/$NAME/libffi.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(ObjectRules, ArchiveRule),
    Artifacts = { ArchiveRule.Out },
  }
  return Result
end

return Render
