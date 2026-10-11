--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- History
-- Original libuv-v1.23.2
-- Update   libuv-v1.24.0
-- Update   libuv-v1.26.0
-- Update   libuv-v1.28.0
-- Update   libuv-v1.29.0
-- Update   libuv-v1.29.1
-- Update   libuv-v1.39.0
-- Update   libuv-v1.44.1
-- Update   libuv-v1.44.2
-- Update   libuv-v1.49.2
-- Update   libuv-v1.50.0
-- Update   libuv-v1.51.0

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local CommonSources = {
  "src/fs-poll.c",
  "src/idna.c",
  "src/inet.c",
  "src/random.c",
  "src/strscpy.c",
  "src/strtok.c",
  "src/thread-common.c",
  "src/threadpool.c",
  "src/timer.c",
  "src/uv-common.c",
  "src/uv-data-getter-setters.c",
  "src/version.c",
}

local WindowsSources = {
  "src/win/async.c",
  "src/win/core.c",
  "src/win/detect-wakeup.c",
  "src/win/dl.c",
  "src/win/error.c",
  "src/win/fs.c",
  "src/win/fs-event.c",
  "src/win/getaddrinfo.c",
  "src/win/getnameinfo.c",
  "src/win/handle.c",
  "src/win/loop-watcher.c",
  "src/win/pipe.c",
  "src/win/poll.c",
  "src/win/process.c",
  "src/win/process-stdio.c",
  "src/win/signal.c",
  "src/win/snprintf.c",
  "src/win/stream.c",
  "src/win/tcp.c",
  "src/win/thread.c",
  "src/win/tty.c",
  "src/win/udp.c",
  "src/win/util.c",
  "src/win/winapi.c",
  "src/win/winsock.c",
}

local LinuxSources = {
  -- core
  "src/unix/async.c",
  "src/unix/core.c",
  "src/unix/dl.c",
  "src/unix/fs.c",
  "src/unix/getaddrinfo.c",
  "src/unix/getnameinfo.c",
  "src/unix/loop.c",
  "src/unix/loop-watcher.c",
  "src/unix/pipe.c",
  "src/unix/poll.c",
  "src/unix/process.c",
  "src/unix/proctitle.c",
  "src/unix/signal.c",
  "src/unix/stream.c",
  "src/unix/tcp.c",
  "src/unix/thread.c",
  "src/unix/tty.c",
  "src/unix/udp.c",
  -- linux specific
  "src/unix/linux.c",
  "src/unix/random-getrandom.c",
  "src/unix/random-devurandom.c",
  -- append(LibSources, "src/unix/random-sysctl-linux.c") deprecated, not available in musl
  "src/unix/procfs-exepath.c",
  -- Those are posix (for BSD for exammple), same functions as linux.c
  -- append(LibSources, "src/unix/posix-hrtime.c")
  -- append(LibSources, "src/unix/sysinfo-loadavg.c")
  -- append(LibSources, "src/unix/sysinfo-memory.c")
  -- append(LibSources, "src/unix/random-getentropy.c")
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
  "-Wno-unused-parameter",
  "-Wno-missing-braces",
  "-Wno-sign-compare",
  "-Wno-cast-function-type",
  "-I$P$DIR/include",
  "-I$P$DIR/src",
  "-target $TRIPLE",
}

local LinuxFlags = {
  "-D_GNU_SOURCE",
  "-D_FILE_OFFSET_BIT=64",
  "-D_LARGEFILE_SOURCE",
  "-pthread",
  "-Wno-format-truncation",
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
    BuildFlags = merge(GenericFlags,  ComponentFlags)
    Sources    = merge(CommonSources, WindowsSources)
  end
  -- CompileSourceFile needs BuildFlags
  -- Create a RULE for a given file from CommonSources / WindowsSources / UnixSources
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
    Out = "bin/$TRIPLE/$NAME/libuv.a",
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(ObjectRules, ArchiveRule),
    Artifacts = { ArchiveRule.Out },
  }
  return Result
end

return Render
