--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local Sources = {
  "platform.c",
  "bump-allocator.c",
  "lua-application.c",
  "growing-buffer.c",
  "trivial-queue-uint.c",
  "trivial-array.c",
  "lua-libbuffer.c",
  "lua-libminizip-ng.c",
  "lua-libffi.c",
}

local WindowsSources = {
  "lua-libwin32-service.c",
  "lua-libwin32-com.c",
}

--------------------------------------------------------------------------------
-- FLAGS                                                                      --
--------------------------------------------------------------------------------

local GenericFlags = {
  "-target $TRIPLE",
  "-ggdb",
  "-std=c99",
  "-Wall",
  "-Wextra",
  "-Os",
  "-flto",
  "-D_FILE_OFFSET_BITS=64",
  "-D_LARGEFILE_SOURCE",
}

local LinuxDefines = {
  "-D_GNU_SOURCE",
}

-- wprintf(L"comexe-%s-%s", COMEXE_BUILD_TYPE, COMEXE_COMMIT)
-- COMEXE_BUILD_TYPE and COMEXE_COMMIT are NOT UTF-16, they are ANSI
-- On MinGW, wprintf works without issue because defaults to __USE_MINGW_ANSI_STDIO=1
-- That flag allows to mix both UTF-16 and ANSI strings together
-- But on ZIG by default, it use the MSVCRT wprint which treat %s as UTF-16
local WindowsDefines = {
  "-D__USE_MINGW_ANSI_STDIO=1",
}

local WindowsIncludeDirs = {
  "-I$Psrc",
  "-I$Pthird-party/src/mimalloc/include",
  "-I$Pthird-party/src/lua/src",
  "-I$Pthird-party/src/zlib/src",
  "-I$Pthird-party/src/minizip-ng/include",
  "-I$Pthird-party/src/minizip-ng/src",
  "-I$Pthird-party/src/libffi/config-windows",
  "-I$Pthird-party/src/libffi/include",
  "-I$Pthird-party/src/libuv/include",
  "-I$Pthird-party/src/lpeg/src",
  "-I$Pthird-party/src/mbedtls/src/tf-psa-crypto/drivers/builtin/include",
  "-I$Pthird-party/src/mbedtls/src/tf-psa-crypto/include",
}

local LinuxIncludeDirs = {
  "-I$Psrc",
  "-I$Pthird-party/src/mimalloc/include",
  "-I$Pthird-party/src/lua/src",
  "-I$Pthird-party/src/zlib/src",
  "-I$Pthird-party/src/minizip-ng/include",
  "-I$Pthird-party/src/minizip-ng/src",
  "-I$Pthird-party/src/libffi/config-linux",
  "-I$Pthird-party/src/libffi/include",
  "-I$Pthird-party/src/libuv/include",
  "-I$Pthird-party/src/lpeg/src",
  "-I$Pthird-party/src/mbedtls/src/tf-psa-crypto/drivers/builtin/include",
  "-I$Pthird-party/src/mbedtls/src/tf-psa-crypto/include",
}

local LibDirs = {
  "-L$Pbin/$TRIPLE/lua",
  "-L$Pbin/$TRIPLE/zlib",
  "-L$Pbin/$TRIPLE/libffi",
  "-L$Pbin/$TRIPLE/libuv",
  "-L$Pbin/$TRIPLE/luv",
  "-L$Pbin/$TRIPLE/luasocket",
  "-L$Pbin/$TRIPLE/lpeg",
  "-L$Pbin/$TRIPLE/mbedtls",
  "-L$Pbin/$TRIPLE/lua-mbedtls-comexe",
  "-L$Pbin/$TRIPLE/mimalloc",
  "-L$Pbin/$TRIPLE/minizip-ng",
}

local CoreLibs = {
  "-lluv",
  "-luv",
  "-lluasocket",
  "-llpeg",
  "-lluambedtls",
  "-lmbedtls",
  "-ltfpsacrypto",
  "-llua",
  "-lffi",
  "-lminizipng",
  "-lz",
}

local LibArchives = {
  "bin/$TRIPLE/libuv/libuv.a",
  "bin/$TRIPLE/luv/libluv.a",
  "bin/$TRIPLE/luasocket/libluasocket.a",
  "bin/$TRIPLE/lpeg/liblpeg.a",
  "bin/$TRIPLE/lua-mbedtls-comexe/libluambedtls.a",
  "bin/$TRIPLE/mbedtls/libmbedtls.a",
  "bin/$TRIPLE/mbedtls/libtfpsacrypto.a",
  "bin/$TRIPLE/lua/liblua.a",
  "bin/$TRIPLE/libffi/libffi.a",
  "bin/$TRIPLE/minizip-ng/libminizipng.a",
  "bin/$TRIPLE/zlib/libz.a",
  "bin/$TRIPLE/mimalloc/libmimalloc.a",
}

local WindowsSystemLibs = {
  "-loleaut32",
  "-lole32",
  "-lws2_32",
  "-lwinmm",
  "-lpsapi",
  "-liphlpapi",
  "-luserenv",
  "-ldbghelp",
  "-luuid",
  "-lbcrypt",
  "-lmimalloc",
}

local LinuxSystemLibs = {
  "-ldl",
  "-lrt",
  "-lmimalloc",
  "-lpthread",
  "-lm",
}

--------------------------------------------------------------------------------
-- VARIANTS                                                                   --
--------------------------------------------------------------------------------

local WindowsVariants = {
  {
    MainObject = "main-dbg.o",
    Define     = "-DCOMEXE_DBG",
    Base       = "comexe-dbg.exe",
    Launcher   = "lua55ced.exe",
    LinkFlags  = { "-municode", "-mconsole", "-static" },
  },
  {
    MainObject = "main-con.o",
    Define     = "-DCOMEXE_CON",
    Base       = "comexe-con.exe",
    Launcher   = "lua55ce.exe",
    LinkFlags  = { "-s", "-municode", "-mconsole", "-static" },
  },
  {
    MainObject = "main-gui.o",
    Define     = "-DCOMEXE_GUI",
    Base       = "comexe-gui.exe",
    Launcher   = false,
    LinkFlags  = { "-s", "-municode", "-mwindows", "-static" },
  },
}

local LinuxMuslVariants = {
  {
    MainObject = "main-con.o",
    Define     = "-DCOMEXE_CON",
    Base       = "comexe",
    Launcher   = "lua55ce",
    LinkFlags  = { "-s" },
  },
  {
    MainObject = "main-dbg.o",
    Define     = "-DCOMEXE_DBG",
    Base       = "comexe-dbg",
    Launcher   = "lua55ced",
    LinkFlags  = {},
  },
}

local LinuxGnuVariants = {
  {
    MainObject = "main-con.o",
    Define     = "-DCOMEXE_CON",
    Base       = "comexe-dyn",
    Launcher   = "lua55ce-dyn",
    LinkFlags  = { "-s" },
  },
  {
    MainObject = "main-dbg.o",
    Define     = "-DCOMEXE_DBG",
    Base       = "comexe-dbg-dyn",
    Launcher   = "lua55ced-dyn",
    LinkFlags  = {},
  },
}

--------------------------------------------------------------------------------
-- HELPERS                                                                    --
--------------------------------------------------------------------------------

local append = table.insert

-- Return rule output (for map call)
local function RuleOutput (Rule)
  return Rule.Out
end

-- Mark a path for "RUN" commands
local function MarkPath (Path)
  return format("$P%s", Path)
end

local function MarkPaths (Paths)
  return map(Paths, MarkPath)
end

--------------------------------------------------------------------------------
-- WINDOWS                                                                    --
--------------------------------------------------------------------------------

local function BuildWindows (Environment)
  -- Evaluate final flags
  local BuildFlags  = merge(GenericFlags, WindowsIncludeDirs, WindowsDefines)
  local FlagsString = concat(BuildFlags, " ")
  -- Create a RULE for a given source file
  local function MakeCompileRule (Source)
    local SourcePath = format("$DIR/%s", Source)
    local Name, Basename, Extension = newpathname(SourcePath):getname()
    assert((Extension == "c"), format("source is not a C file (got %q)", SourcePath))
    local Rule = {
      Ins = { SourcePath, "src/comexe.h", "src/version.h" },
      Run = { format("zig cc %s -c $IN -o $OUT", FlagsString) },
      Out = format("bin/$TRIPLE/src/%s.o", Basename),
    }
    return Rule
  end
  -- Special RULE FOR MAIN
  local function MakeMainRule (Variant, MainSource)
    local TargetName = format("bin/$TRIPLE/src/%s", Variant.MainObject)
    local SourcePath = format("$DIR/%s", MainSource)
    local Rule = {
      Ins = { SourcePath, "src/comexe.h", "src/version.h" },
      Run = { format("zig cc %s %s -c $IN -o $OUT", FlagsString, Variant.Define) },
      Out = TargetName,
    }
    return Rule
  end
  -- Special RULE FOR LINK
  local function MakeLinkRule (Variant, ObjectPaths, SystemLibs)
    local TargetName = format("bin/$TRIPLE/src/%s", Variant.Base)
    local MainObject = format("bin/$TRIPLE/src/%s", Variant.MainObject)
    local AllObjects = merge(ObjectPaths, { MainObject })
    local Tokens = merge(
      { "zig cc", "-target $TRIPLE" },
      Variant.LinkFlags,
      { "-o", "$OUT" },
      MarkPaths(AllObjects),
      LibDirs,
      CoreLibs,
      SystemLibs
    )
    local Command = concat(Tokens, " ")
    local Rule = {
      Needs = LibArchives,
      Ins   = merge({ "src/comexe.h" }, AllObjects),
      Run   = { Command },
      Out   = TargetName,
    }
    return Rule
  end
  -- Special RULE for standalone executable
  local function MakeLauncherRule (Variant)
    local TargetName     = format("bin/$TRIPLE/src/%s", Variant.Launcher)
    local BaseExecutable = format("bin/$TRIPLE/src/%s", Variant.Base)
    local CommandLines = {
      "$Pbin/tools/buildtool.exe concat $IN $Pbin/app/lua55ce-runtime.zip $OUT",
    }
    local Rule = {
      Needs = { "bin/app/lua55ce-runtime.zip" },
      Ins   = { BaseExecutable, "bin/tools/buildtool.exe" },
      Run   = CommandLines,
      Out   = TargetName,
    }
    return Rule
  end
  -- Win32 resource
  local ResourceObject = "bin/$TRIPLE/src/resources.o"
  local ResourceRule   = {
    Ins = { "src/resources.rc" },
    Run = { "zig rc $Psrc/resources.rc $OUT" },
    Out = ResourceObject,
  }
  -- Group all together
  local WindowsSourceTable = merge(Sources, WindowsSources)
  local ObjectRules        = map(WindowsSourceTable, MakeCompileRule)
  local BaseObjects        = map(ObjectRules, RuleOutput)
  local MainRules          = {}
  local LinkRules          = {}
  local LauncherRules      = {}
  local Artifacts          = {}
  for Index, Variant in ipairs(WindowsVariants) do
    append(MainRules, MakeMainRule(Variant, "main-windows.c"))
    append(LinkRules, MakeLinkRule(Variant, merge(BaseObjects, { ResourceObject }), WindowsSystemLibs))
    append(Artifacts, format("bin/$TRIPLE/src/%s", Variant.Base))
    if Variant.Launcher then
      append(LauncherRules, MakeLauncherRule(Variant))
      append(Artifacts, format("bin/$TRIPLE/src/%s", Variant.Launcher))
    end
  end
  -- Collect all the rules
  local Result = {
    Rules     = merge(ObjectRules, ResourceRule, MainRules, LinkRules, LauncherRules),
    Artifacts = Artifacts,
  }
  return Result
end

--------------------------------------------------------------------------------
-- WINDOWS libtcc.dll                                                         --
--------------------------------------------------------------------------------

local function BuildTccWindows (Environment)
  -- Make tcc-embedded.o from tcc.c
  local function MakeTccEmbeddedObjectRule (LibtccArchive)
    local TargetName = "bin/$TRIPLE/src/tcc-embedded.o"
    -- Compile command
    local CompileCommand = {
      "zig cc",
      "-target $TRIPLE",
      "-Os",
      "-DTCC_TARGET_PE",
      "-DTCC_TARGET_X86_64",
      "-DONE_SOURCE=1",
      "-D_FILE_OFFSET_BITS=64",
      "-I$Pbin/tcc-vio/generated",
      "-I$Pthird-party/src/tcc-vio/src",
      "-c",
      "$IN",
      "-o",
      "$OUT",
    }
    local CompileCommandString = concat(CompileCommand, " ")
    local Rule = {
      Needs = { LibtccArchive },
      Ins   = { "third-party/src/tcc-vio/src/tcc.c", "bin/tcc-vio/generated/config.h" },
      Run   = { CompileCommandString },
      Out   = TargetName,
    }
    return Rule
  end
  -- Make libtcc rule libtcc.dll
  local function MakeLibtccRule (Extension, Archive)
    local TargetName = format("bin/$TRIPLE/src/libtcc.%s", Extension)
    local Object     = "bin/$TRIPLE/src/tcc-embedded.o"
    local LinkCommand = {
      "zig cc",
      "-target $TRIPLE",
      "-shared",
      "-s",
      "-Wl,--export-all-symbols",
      "-I$Psrc",
      "-I$Pthird-party/src/lua/src",
      "-I$Pthird-party/src/tcc-vio/src",
      "-I$Pbin/tcc-vio/generated",
      "-L$Pbin/$TRIPLE/lua",
      "$Psrc/lua-libtcc-module.c",
      MarkPath(Object),
      "-llua",
      "-o",
      "$OUT",
    }
    local LinkCommandString = concat(LinkCommand, " ")
    local Rule = {
      Needs = { Archive },
      Ins   = { "src/lua-libtcc-module.c", Object },
      Run   = { LinkCommandString },
      Out   = TargetName,
    }
    return Rule
  end
  -- Finalize
  local LibtccArchive    = "bin/tcc-vio/libtcc-x86_64-windows-static/libtcc.a"
  local ModuleObjectRule = MakeTccEmbeddedObjectRule(LibtccArchive)
  local ModuleRule       = MakeLibtccRule("dll", LibtccArchive)
  local Result = {
    Rules     = { ModuleObjectRule, ModuleRule },
    Artifacts = { ModuleRule.Out               },
  }
  return Result
end

--------------------------------------------------------------------------------
-- LINUX                                                                      --
--------------------------------------------------------------------------------

local function BuildLinux (Environment)
  -- Extract OS
  local HostTriple = Environment.HOST_TRIPLE
  local HostOs     = (HostTriple:match("^[^-]+%-([^-]+)%-"))
  -- Evaluate final flags
  local BuildFlags  = merge(GenericFlags, LinuxIncludeDirs, LinuxDefines)
  local FlagsString = concat(BuildFlags, " ")
  -- Create a RULE for a given source file
  local function MakeCompileRule (Source)
    local TargetName = format("$DIR/%s", Source)
    local Name, Basename, Extension = newpathname(TargetName):getname()
    assert((Extension == "c"), format("source is not a C file (got %q)", TargetName))
    local Rule = {
      Ins = { TargetName, "src/comexe.h", "src/version.h" },
      Run = { format("zig cc %s -c $IN -o $OUT", FlagsString) },
      Out = format("bin/$TRIPLE/src/%s.o", Basename),
    }
    return Rule
  end
  -- Special RULE FOR MAIN
  local function MakeMainRule (Variant, MainSource)
    local SourceFilename = format("$DIR/%s", MainSource)
    local Rule = {
      Ins = { SourceFilename, "src/comexe.h", "src/version.h" },
      Run = { format("zig cc %s %s -c $IN -o $OUT", FlagsString, Variant.Define) },
      Out = format("bin/$TRIPLE/src/%s", Variant.MainObject),
    }
    return Rule
  end
  -- Special RULE FOR LINK
  local function MakeLinkRule (Variant, ObjectPaths, SystemLibs)
    local TargetName = format("bin/$TRIPLE/src/%s", Variant.Base)
    local MainObject = format("bin/$TRIPLE/src/%s", Variant.MainObject)
    local AllObjects = merge(ObjectPaths, { MainObject })
    local Tokens = merge(
      { "zig cc", "-target $TRIPLE" },
      Variant.LinkFlags,
      { "-o", "$OUT" },
      MarkPaths(AllObjects),
      LibDirs,
      CoreLibs,
      SystemLibs
    )
    local Command = concat(Tokens, " ")
    local Rule = {
      Needs = LibArchives,
      Ins   = merge({ "src/comexe.h" }, AllObjects),
      Run   = { Command },
      Out   = TargetName,
    }
    return Rule
  end
  -- Special RULE for standalone executable
  local function MakeLauncherRule (Variant)
    local TargetName     = format("bin/$TRIPLE/src/%s", Variant.Launcher)
    local BaseExecutable = format("bin/$TRIPLE/src/%s", Variant.Base)
    local CommandLines = {
      "$Pbin/tools/buildtool.exe concat $IN $Pbin/app/lua55ce-runtime.zip $OUT",
    }
    -- chmod for Linux's target on Linux hosts
    if (HostOs == "linux") then
      append(CommandLines, "chmod +x $OUT")
    end
    local Rule = {
      Needs = { "bin/app/lua55ce-runtime.zip"             },
      Ins   = { BaseExecutable, "bin/tools/buildtool.exe" },
      Run   = CommandLines,
      Out   = TargetName,
    }
    return Rule
  end
  -- Group all together
  local ObjectRules = map(Sources, MakeCompileRule)
  local BaseObjects = map(ObjectRules, RuleOutput)
  local Variants
  if (Environment.LIBC == "musl") then
    Variants = LinuxMuslVariants
  else
    Variants = LinuxGnuVariants
  end
  local MainRules     = {}
  local LinkRules     = {}
  local LauncherRules = {}
  local Artifacts     = {}
  for Index, Variant in ipairs(Variants) do
    append(MainRules, MakeMainRule(Variant, "main-linux.c"))
    append(LinkRules, MakeLinkRule(Variant, BaseObjects, LinuxSystemLibs))
    append(Artifacts, format("bin/$TRIPLE/src/%s", Variant.Base))
    if Variant.Launcher then
      append(LauncherRules, MakeLauncherRule(Variant))
      append(Artifacts, format("bin/$TRIPLE/src/%s", Variant.Launcher))
    end
  end
  -- Collect all the rules
  local Result = {
    Rules     = merge(ObjectRules, MainRules, LinkRules, LauncherRules),
    Artifacts = Artifacts,
  }
  return Result
end

--------------------------------------------------------------------------------
-- LINUX libtcc.so                                                            --
--------------------------------------------------------------------------------

local function BuildTccLinux (Environment)
  -- Make tcc-embedded.o from tcc.c
  local function MakeTccEmbeddedObjectRule (LibtccArchive)
    local TargetName = "bin/$TRIPLE/src/tcc-embedded.o"
    -- Compile command
    local CompileCommand = {
      "zig cc",
      "-target $TRIPLE",
      "-Os",
      "-DTCC_TARGET_PE",
      "-DTCC_TARGET_X86_64",
      "-DONE_SOURCE=1",
      "-D_FILE_OFFSET_BITS=64",
      "-I$Pbin/tcc-vio/generated",
      "-I$Pthird-party/src/tcc-vio/src",
      "-c",
      "$IN",
      "-o",
      "$OUT",
    }
    local CompileCommandString = concat(CompileCommand, " ")
    local Rule = {
      Needs = { LibtccArchive },
      Ins   = { "third-party/src/tcc-vio/src/tcc.c", "bin/tcc-vio/generated/config.h" },
      Run   = { CompileCommandString },
      Out   = TargetName,
    }
    return Rule
  end
  -- Make libtcc rule libtcc.so
  local function MakeLibtccRule (Extension, Archive)
    local TargetName = format("bin/$TRIPLE/src/libtcc.%s", Extension)
    local Object     = "bin/$TRIPLE/src/tcc-embedded.o"
      local LinkCommand = {
      "zig cc",
      "-target $TRIPLE",
      "-shared",
      "-s",
      "-Wl,--export-all-symbols",
      "-I$Psrc",
      "-I$Pthird-party/src/lua/src",
      "-I$Pthird-party/src/tcc-vio/src",
      "-I$Pbin/tcc-vio/generated",
      "-L$Pbin/$TRIPLE/lua",
      "$Psrc/lua-libtcc-module.c",
      MarkPath(Object),
      "-llua",
      "-o",
      "$OUT",
    }
    local LinkCommandString = concat(LinkCommand, " ")
    local Rule = {
      Needs = { Archive },
      Ins   = { "src/lua-libtcc-module.c", Object },
      Run   = { LinkCommandString },
      Out   = TargetName,
    }
    return Rule
  end
  -- libtcc module support
  local function LibtccSupported ()
    local Support
    if (Environment.OS == "windows") then
      Support = true
    elseif (Environment.OS == "linux") then
      -- musl is not supported (not working with non trivial case like webgtk)
      Support = (Environment.LIBC == "gnu")
    else
      Support = false
    end
    return Support
  end
  -- Finalize
  local LibtccArchive = "bin/tcc-vio/libtcc-x86_64-linux-static/libtcc.a"
  local Rules
  local Artifacts
  if LibtccSupported() then
    local ModuleObjectRule = MakeTccEmbeddedObjectRule(LibtccArchive)
    local ModuleRule       = MakeLibtccRule("so", LibtccArchive)
    Rules     = { ModuleObjectRule, ModuleRule }
    Artifacts = { ModuleRule.Out               }
  else
    Rules     = {}
    Artifacts = {}
  end
  local Result = {
    Rules     = Rules,
    Artifacts = Artifacts,
  }
  return Result
end

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  local Result
  if (Environment.OS == "windows") then
    local Platform = BuildWindows(Environment)
    local Tcc      = BuildTccWindows(Environment)
    Result = {
      Rules     = merge(Platform.Rules,     Tcc.Rules),
      Artifacts = merge(Platform.Artifacts, Tcc.Artifacts),
    }
  elseif (Environment.OS == "linux") then
    local Platform = BuildLinux(Environment)
    local Tcc      = BuildTccLinux(Environment)
    Result = {
      Rules     = merge(Platform.Rules,     Tcc.Rules),
      Artifacts = merge(Platform.Artifacts, Tcc.Artifacts),
    }
  else
    error(format("unsupported target OS %q for triple %s",
                 Environment.OS,
                 Environment.TRIPLE))
  end
  return Result
end

return Render
