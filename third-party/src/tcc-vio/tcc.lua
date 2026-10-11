--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- This build is special: it produces only ONE Linux build and ONE Windows
-- build, and both are shared by every target in the Triples list. That's why
-- the target flags below are the fixed literals "x86_64-linux-gnu" and
-- "x86_64-windows-gnu" instead of $TRIPLE (with $TRIPLE the Linux build would
-- be made twice: musl and gnu)
--
-- Initial build based on:
--   build-commands-linux.txt
--   build-commands-windows.txt
--
-- atomic.S was failing with clang on Windows, so we created atomic-clang.S
--
--   src/lib/atomic.S       -> runtime-linux/atomic.o
--   src/lib/atomic-clang.S -> runtime-windows/atomic.o
--
-- tccdefs_.h is GENERATED at build time, by the host c2str tool
--

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local LinuxSources = {
  "src/lib/libtcc1.c",
  "src/lib/stdatomic.c",
  "src/lib/builtin.c",
  "src/lib/dsohandle.c",
  "src/lib/atomic.S",
  "src/lib/alloca.S",
  "src/lib/alloca-bt.S",
}

local LinuxSupportSources = {
  "src/lib/bcheck.c",
  "src/lib/bt-exe.c",
  "src/lib/bt-log.c",
  "src/lib/runmain.c",
  "src/lib/tcov.c",
}

local WindowsSources = {
  "src/lib/libtcc1.c",
  "src/lib/stdatomic.c",
  "src/lib/builtin.c",
  "src/lib/dsohandle.c",
  "src/lib/atomic-clang.S",
  "src/lib/alloca.S",
  "src/lib/alloca-bt.S",
  "src/lib/tcov.c",
  "src/win32/lib/chkstk.S",
  "src/win32/lib/crt1.c",
  "src/win32/lib/crt1w.c",
  "src/win32/lib/wincrt1.c",
  "src/win32/lib/wincrt1w.c",
  "src/win32/lib/dllcrt1.c",
  "src/win32/lib/dllmain.c",
}

local WindowsSupportSources = {
  "src/lib/bcheck.c",
  "src/lib/bt-exe.c",
  "src/lib/bt-log.c",
  "src/lib/runmain.c",
}

local WindowsDefSources = {
  "gdi32.def",
  "kernel32.def",
  "msvcrt.def",
  "user32.def",
  "ws2_32.def",
}

local TCC_CONFIG_H = "bin/tcc-vio/generated/config.h"

-- Used for buildtool concat (instead of cmd.exe's copy)
local BuildToolFilename = "bin/tools/buildtool.exe"

--------------------------------------------------------------------------------
-- FLAGS                                                                      --
--------------------------------------------------------------------------------

local EmbeddedCompilerFlags = {
  "-Os",
}

local RuntimeOptimizeFlags = {
  "-Os",
}

local ComponentFlags = {
  "-I$Pbin/tcc-vio/generated",
  "-I$P$DIR/src",
}

-- Windows runtime objects are compiled by the HOST COMPILER
-- (cannot compile from Zig unfortunately due to COFF/ELF container thing)
local HostCompilerFlags = {
  "-B$Pbin/tcc-vio/generated",
  "-I$Pbin/tcc-vio/generated",
  "-I$P$DIR/src/include",
  "-I$P$DIR/src/win32/include",
  "-I$P$DIR/src/win32/include/winapi",
}

local LinuxTargetFlags = {
  "-target x86_64-linux-gnu",
  "-fPIC",
}

local WindowsLibtccDefines = {
  "-DTCC_TARGET_PE",
  "-DTCC_TARGET_X86_64",
}

local HostCompilerDefines = {
  "-DTCC_TARGET_PE",
  "-DTCC_TARGET_X86_64",
  "-D_FILE_OFFSET_BITS=64",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Return rule output (for map call)
  local function RuleOutput (Rule)
    return Rule.Out
  end
  -- To make it easy: on both Linux and Windows, tcc host binary is named
  -- "bin/tcc-vio/tcc-host.exe".
  --
  -- The purpose of that tcc compiler is to generate object files and archives
  -- for Windows.
  --
  -- Tricky: TCC always writes ELF object files, regardless of the target
  -- (Linux, Windows). The Windows runtime needs machine code targeting PE in an
  -- ELF container.
  --
  -- So, when using ZIG to generate TCC binaries for Linux, ZIG also generates
  -- ELF. It's compatible with TCC loader, so we use ZIG to compile TCC runtime
  -- sources. However, when ZIG targets Windows, it generates COFF instead of an
  -- ELF container, which the loader rejects because it does not support
  -- COFF. For that specific reason, we use TCC host binaries to generate the
  -- object files for Windows (ELF container).
  local TccHostCompiler     = "bin/tcc-vio/tcc-host.exe"
  local TccHostCompilerText = format("$P%s", TccHostCompiler)
  local BuildToolText       = format("$P%s", BuildToolFilename)
  -- Compiler needs
  local ZigCompiler      = { Text = "zig cc",            Needs = {}                  }
  local HostCompilerTool = { Text = TccHostCompilerText, Needs = { TccHostCompiler } }
  -- Evaluate final flags
  local LinuxFlags           = merge(RuntimeOptimizeFlags,  ComponentFlags, LinuxTargetFlags)
  local WindowsHostFlags     = merge(RuntimeOptimizeFlags,  HostCompilerFlags)
  local EmbeddedLinuxFlags   = merge(EmbeddedCompilerFlags, ComponentFlags, LinuxTargetFlags)
  local EmbeddedWindowsFlags = merge(EmbeddedCompilerFlags, ComponentFlags, LinuxTargetFlags, WindowsLibtccDefines)
  -- Create a RULE for a given file
  local function MakeCompileRule (Source, Flags, ObjectDir, Compiler)
    local FlagsString = concat(Flags, " ")
    local Path        = format("$DIR/%s", Source)
    local Name, Basename, Extension = newpathname(Path):getname()
    assert((Extension == "c") or (Extension == "S"), format("source is not a C or assembly file (got %q)", Path))
    local NewRule = {
      Needs = merge({ TCC_CONFIG_H }, Compiler.Needs),
      Ins   = { Path },
      Run   = { format("%s %s -c $IN -o $OUT", Compiler.Text, FlagsString) },
      Out   = format("%s/%s.o", ObjectDir, Basename),
    }
    return NewRule
  end
  -- map() callbacks
  local function MakeLinuxRule (Source)
    return MakeCompileRule(Source, LinuxFlags, "bin/tcc-vio/runtime-linux", ZigCompiler)
  end
  local function MakeHostRule (Source)
    return MakeCompileRule(Source, WindowsHostFlags, "bin/tcc-vio/runtime-windows", HostCompilerTool)
  end
  local function MakeHostLibRule (Source)
    return MakeCompileRule(Source, WindowsHostFlags, "bin/tcc-vio/runtime-windows/lib", HostCompilerTool)
  end
  -- c2str is a tool that generates tccdefs_.h from tccdefs.h
  local C2strExecutable = "bin/tcc-vio/generated/c2str.exe"
  local C2strOutputs
  if (Environment.OS == "windows") then
    -- ZIG on windows also generates a .pdb file
    C2strOutputs = { C2strExecutable, "bin/tcc-vio/generated/c2str.pdb" }
  else
    C2strOutputs = { C2strExecutable }
  end
  -- Generate tccdefs_.h generation rule per destination
  local HeaderRules = {
    {
      Ins = { "$DIR/libtcc-config.h", BuildToolFilename },
      Run = { format("%s concat $P$DIR/libtcc-config.h $OUT", BuildToolText) },
      Out = TCC_CONFIG_H,
    },
    {
      Ins = { "$DIR/src/include/tccdefs.h", BuildToolFilename },
      Run = { format("%s concat $P$DIR/src/include/tccdefs.h $OUT", BuildToolText) },
      Out = "bin/tcc-vio/generated/tccdefs.h",
    },
    {
      Ins = { "$DIR/src/conftest.c" },
      Run = { "zig cc -DC2STR=1 $IN -o $OUT" },
      Outs = C2strOutputs,
    },
    -- c2str.exe tccdefs.h OUTPUT for runtime-linux / runtime-windows
    {
      Ins = { "bin/tcc-vio/generated/c2str.exe", "$DIR/src/include/tccdefs.h" },
      Run = { "$INS $OUT" },
      Out = "bin/tcc-vio/generated/tccdefs_.h",
    },
    -- copy tccdefs.h for the LINUX runtime and generate tccdefs_.h
    {
      Ins = { "$DIR/src/include/tccdefs.h", BuildToolFilename },
      Run = { format("%s concat $P$DIR/src/include/tccdefs.h $OUT", BuildToolText) },
      Out = "bin/tcc-vio/runtime-linux/include/tccdefs.h",
    },
    {
      Ins   = { "bin/tcc-vio/generated/c2str.exe", "$DIR/src/include/tccdefs.h" },
      Needs = { "bin/tcc-vio/runtime-linux/include/tccdefs.h" },
      Run   = { "$INS $OUT" },
      Out   = "bin/tcc-vio/runtime-linux/include/tccdefs_.h",
    },
    {
      Ins = { "bin/tcc-vio/generated/c2str.exe", "$DIR/src/include/tccdefs.h" },
      Run = { "$INS $OUT" },
      Out = "bin/tcc-vio/runtime-windows/include/tccdefs_.h",
    },
  }
  -- The HOST COMPILER: host executable, built by zig, PROVIDES the uio_* hooks
  local HostCompilerCommand = {
    "zig cc",
    "-target $HOST_TRIPLE",
    "-Os",
    "-s",
    concat(HostCompilerDefines, " "),
    "-I$Pbin/tcc-vio/generated",
    "-I$P$DIR/src",
    "$INS",
    "-o",
    "$OUT",
  }
  local HostCompilerCommandString = concat(HostCompilerCommand, " ")
  local HostCompilerRule = {
    Needs = { TCC_CONFIG_H, "bin/tcc-vio/generated/tccdefs.h", "bin/tcc-vio/generated/tccdefs_.h" },
    Ins   = { "$DIR/src/tcc.c", "tools/src/tcc-host.c" },
    Run   = { HostCompilerCommandString },
    Out   = TccHostCompiler,
  }
  -- Windows .def files, copied into the runtime tree
  local function MakeDefRule (Name)
    local NewRule = {
      Ins = { format("$DIR/src/win32/lib/%s", Name), BuildToolFilename },
      Run = { format("%s concat $P$DIR/src/win32/lib/%s $OUT", BuildToolText, Name) },
      Out = format("bin/tcc-vio/runtime-windows/lib/%s", Name),
    }
    return NewRule
  end
  local DefRules   = map(WindowsDefSources, MakeDefRule)
  local DefObjects = map(DefRules, RuleOutput)
  -- Rule to build the archive (Linux runtime)
  local LinuxCoreRules    = map(LinuxSources, MakeLinuxRule)
  local LinuxSupportRules = map(LinuxSupportSources, MakeLinuxRule)
  local LinuxCoreObjects  = map(LinuxCoreRules, RuleOutput)
  local LinuxArchiveRule = {
    Ins = LinuxCoreObjects,
    Run = { "zig ar rcs $OUT $INS" },
    Out = "bin/tcc-vio/runtime-linux/libtcc1.a",
  }
  -- Rule to build the archive (Windows runtime): TCC archiver
  local WindowsCoreRules    = map(WindowsSources,        MakeHostRule)
  local WindowsSupportRules = map(WindowsSupportSources, MakeHostLibRule)
  local WindowsCoreObjects  = map(WindowsCoreRules,      RuleOutput)
  local WindowsArchiveRule = {
    Needs = { TccHostCompiler },
    Ins   = WindowsCoreObjects,
    Run   = { format("%s -ar rcs $OUT $INS", TccHostCompilerText) },
    Out   = "bin/tcc-vio/runtime-windows/lib/libtcc1.a",
  }
  -- Embedded compiler (tcc.c as ONE_SOURCE)
  local EmbeddedLinuxObject   = "$Pbin/tcc-vio/libtcc-x86_64-linux-static/tcc.o"
  local EmbeddedWindowsObject = "$Pbin/tcc-vio/libtcc-x86_64-windows-static/tcc.o"
  local EmbeddedLinuxCompile = {
    "zig cc",
    concat(EmbeddedLinuxFlags, " "),
    "-c",
    "$IN",
    "-o",
    EmbeddedLinuxObject,
  }
  local EmbeddedLinuxCompileString = concat(EmbeddedLinuxCompile, " ")
  local EmbeddedLinuxArchive = {
    "zig ar rcs",
    "$OUT",
    EmbeddedLinuxObject,
  }
  local EmbeddedLinuxArchiveString = concat(EmbeddedLinuxArchive, " ")
  local EmbeddedWindowsCompile = {
    "zig cc",
    concat(EmbeddedWindowsFlags, " "),
    "-c",
    "$IN",
    "-o",
    EmbeddedWindowsObject,
  }
  local EmbeddedWindowsCompileString = concat(EmbeddedWindowsCompile, " ")
  local EmbeddedWindowsArchive = {
    "zig ar rcs",
    "$OUT",
    EmbeddedWindowsObject,
  }
  local EmbeddedWindowsArchiveString = concat(EmbeddedWindowsArchive, " ")
  local EmbeddedRules = {
    {
      Ins = {
        "$DIR/src/tcc.c",
        TCC_CONFIG_H,
        "bin/tcc-vio/generated/tccdefs.h",
        "bin/tcc-vio/generated/tccdefs_.h",
      },
      Run = { EmbeddedLinuxCompileString, EmbeddedLinuxArchiveString },
      Out = "bin/tcc-vio/libtcc-x86_64-linux-static/libtcc.a",
    },
    {
      Ins = {
        "$DIR/src/tcc.c",
        TCC_CONFIG_H,
        "bin/tcc-vio/generated/tccdefs.h",
        "bin/tcc-vio/generated/tccdefs_.h",
      },
      Run = { EmbeddedWindowsCompileString, EmbeddedWindowsArchiveString },
      Out = "bin/tcc-vio/libtcc-x86_64-windows-static/libtcc.a",
    },
  }
  -- Those object files are NOT archived
  local LinuxSupportObjects   = map(LinuxSupportRules,   RuleOutput)
  local WindowsSupportObjects = map(WindowsSupportRules, RuleOutput)
  -- Gather everything
  local AllTargets = {
    "bin/tcc-vio/generated/tccdefs_.h",
    "bin/tcc-vio/runtime-linux/include/tccdefs_.h",
    "bin/tcc-vio/runtime-windows/include/tccdefs_.h",
    "bin/tcc-vio/runtime-linux/libtcc1.a",
    "bin/tcc-vio/runtime-windows/lib/libtcc1.a",
    "bin/tcc-vio/libtcc-x86_64-linux-static/libtcc.a",
    "bin/tcc-vio/libtcc-x86_64-windows-static/libtcc.a",
  }
  local AllRules = merge(HeaderRules,
                         HostCompilerRule,
                         DefRules,
                         LinuxCoreRules,
                         LinuxArchiveRule,
                         LinuxSupportRules,
                         WindowsCoreRules,
                         WindowsArchiveRule,
                         WindowsSupportRules,
                         EmbeddedRules)
  local Artifacts = merge(TccHostCompiler, AllTargets, DefObjects, LinuxSupportObjects, WindowsSupportObjects)
  -- Final rule
  local Result = {
    Rules     = AllRules,
    Artifacts = Artifacts,
    CleanDirs = { "bin/tcc-vio" },
  }
  return Result
end

return Render
