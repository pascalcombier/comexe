--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as a static library
--
-- History
-- Original version: luasocket-trunk (after 3.1.0)
--

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local CommonSources = {
  "src/auxiliar.c",
  "src/buffer.c",
  "src/compat.c",
  "src/except.c",
  "src/inet.c",
  "src/io.c",
  "src/luasocket.c",
  "src/mime.c",
  "src/options.c",
  "src/select.c",
  "src/tcp.c",
  "src/timeout.c",
  "src/udp.c",
}

local WindowsSources = {
  "src/wsocket.c",
}

local LinuxSources = {
  "src/usocket.c",
  "src/unix.c",
  "src/serial.c",
  "src/unixdgram.c",
  "src/unixstream.c",
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
  "-Wno-unused-parameter",
  "-I$Pthird-party/src/lua/src",
  "-target $TRIPLE",
}

local LinuxFlags = {
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
  if (Environment.OS == "linux") then
    BuildFlags = merge(GenericFlags, ComponentFlags, LinuxFlags)
    Sources    = merge(CommonSources, LinuxSources)
  else
    BuildFlags = merge(GenericFlags, ComponentFlags)
    Sources    = merge(CommonSources, WindowsSources)
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
    Out = "bin/$TRIPLE/$NAME/libluasocket.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(ObjectRules, ArchiveRule),
    Artifacts = { ArchiveRule.Out },
  }
  return Result
end

return Render
