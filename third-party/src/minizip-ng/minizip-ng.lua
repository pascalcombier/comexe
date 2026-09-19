--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- History
-- minizip-ng 4.2.2
--

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local CommonSources = {
  "src/mz_crypt.c",
  "src/mz_os.c",
  "src/mz_strm.c",
  "src/mz_strm_buf.c",
  "src/mz_strm_mem.c",
  "src/mz_strm_split.c",
  "src/mz_strm_zlib.c",
  "src/mz_zip.c",
  "src/mz_zip_rw.c",
}

local WindowsSources = {
  "src/mz_os_win32.c",
  "src/mz_strm_os_win32.c",
}

local PosixSources = {
  "src/mz_os_posix.c",
  "src/mz_strm_os_posix.c",
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
  "-Wno-attributes",
  "-Wno-unused-variable",
  "-target $TRIPLE",
}

-- zlib, no crypto
local FeatureDefines = {
  "-DHAVE_ZLIB",
  "-DZLIB_COMPAT",
  "-DMZ_ZIP_NO_CRYPTO",
  "-DMZ_ZIP_NO_ENCRYPTION",
}

local IncludeDirs = {
  "-I$DIR/include",
  "-I$DIR/src",
  "-Ithird-party/src/zlib/src",
}

local WindowsDefines = {
  "-D_CRT_SECURE_NO_DEPRECATE",
  "-D_CRT_NONSTDC_NO_DEPRECATE",
}

local PosixDefines = {
  "-D_POSIX_C_SOURCE=200809L",
  "-D_BSD_SOURCE",
  "-D_DEFAULT_SOURCE",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Return rule output (for map call)
  local function RuleOutput (Rule)
    return Rule.Out
  end
  -- Platform specific sources and defines
  local Sources
  local PlatformDefines
  if (Environment.OS == "windows") then
    Sources         = merge(CommonSources, WindowsSources)
    PlatformDefines = WindowsDefines
  else
    Sources         = merge(CommonSources, PosixSources)
    PlatformDefines = PosixDefines
  end
  -- Evaluate final flags
  local BuildFlags  = merge(GenericFlags, ComponentFlags, FeatureDefines, IncludeDirs, PlatformDefines)
  local FlagsString = concat(BuildFlags, " ")
  -- Create a RULE for a given source file
  local function MakeCompileRule (Source)
    local Path = format("$DIR/%s", Source)
    local Name, Basename, Extension = newpathname(Path):getname()
    assert((Extension == "c"), format("source is not a C file (got %q)", Path))
    local NewRule = {
      Ins = { Path, "$DIR/include/mz_config.h" },
      Run = { format("zig cc %s -c $IN -o $OUT", FlagsString) },
      Out = format("bin/$TRIPLE/$NAME/%s.o", Basename),
    }
    return NewRule
  end
  -- Create a specific target for each source file
  local CompileRules = map(Sources, MakeCompileRule)
  -- Retrieve objects files from Rules[Index].Out
  local ObjectList = map(CompileRules, RuleOutput)
  -- Rule to build the archive
  local ArchiveRule = {
    Ins = ObjectList,
    Run = { "zig ar rcs $OUT $INS" },
    Out = "bin/$TRIPLE/$NAME/libminizipng.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(CompileRules, ArchiveRule),
    Artifacts = { "bin/$TRIPLE/$NAME/libminizipng.a" },
  }
  return Result
end

return Render
