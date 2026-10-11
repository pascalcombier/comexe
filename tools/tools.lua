--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- makeheaders.exe
-- buildtool.exe

--------------------------------------------------------------------------------
-- FLAGS                                                                      --
--------------------------------------------------------------------------------

local CompileFlags = {
  "-fvisibility=hidden",
  "--std=c99",
  "-Wall",
  "-Wextra",
  "-ggdb",
  "-Os",
  "-target $TRIPLE",
}

local ToolStaticLibs = {
  "bin/$TRIPLE/libuv/libuv.a",
  "bin/$TRIPLE/luv/libluv.a",
  "bin/$TRIPLE/minizip-ng/libminizipng.a",
  "bin/$TRIPLE/zlib/libz.a",
  "bin/$TRIPLE/lua/liblua.a",
}

local ToolWindowsLibs = {
  "-static",
  "-lws2_32",
  "-liphlpapi",
  "-luserenv",
  "-lpsapi",
  "-lole32",
  "-ldbghelp",
}

local ToolLinuxLibs = {
  "-lpthread",
  "-ldl",
  "-lm",
  "-lrt",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- BuildTool depends
  local MinizipHeaders = {
    "third-party/src/minizip-ng/src/mz.h",
    "third-party/src/minizip-ng/src/mz_os.h",
    "third-party/src/minizip-ng/src/mz_strm_os.h",
    "third-party/src/minizip-ng/src/mz_zip.h",
    "third-party/src/minizip-ng/include/mz_config.h",
    "third-party/src/zlib/src/zlib.h",
    "third-party/src/lua/src/lua.h",
    "third-party/src/lua/src/lauxlib.h",
  }
  local BuildToolNeeds = {
    "tools/src/buildtool.h",
    "tools/src/buildtool-main.lua",
    "tools/src/buildtool-pack.lua",
    "tools/src/buildtool-file-ops.lua",
  }
  -- BuildTool inputs
  local BuildToolInputs = {
    "tools/src/buildtool.c",
    "src/lua-libminizip-ng.c",
  }
  local BuildToolIns = merge(BuildToolInputs, ToolStaticLibs)
  local ToolSystemLibs
  if (Environment.OS == "windows") then
    ToolSystemLibs = ToolWindowsLibs
  else
    ToolSystemLibs = ToolLinuxLibs
  end
  -- Wno-c23-extensions disable #embed warning
  local FlagsString       = concat(CompileFlags, " ")
  local BuildCommandTable = {
    "zig cc",
    FlagsString,
    "-Wno-c23-extensions",
    "-I$Pthird-party/src/lua/src",
    "-I$Pthird-party/src/minizip-ng/include",
    "-I$Pthird-party/src/minizip-ng/src",
    "-I$Pthird-party/src/zlib/src",
    "-D_FILE_OFFSET_BITS=64",
    "$INS",
    "-o",
    "$OUT",
  }
  local BuildCommand       = merge(BuildCommandTable, ToolSystemLibs)
  local BuildCommandString = concat(BuildCommand, " ")
  local BuildToolRule = {
    Needs = merge(MinizipHeaders, BuildToolNeeds),
    Ins   = BuildToolIns,
    Run   = { BuildCommandString },
    Out   = "bin/tools/buildtool.exe",
  }
  -- makeheaders
  local MakeHeadersRule = {
    Ins = { "$DIR/src/makeheaders.c" },
    Run = { "zig cc $IN -o $OUT" },
    Out = "bin/tools/make-headers.exe",
  }
  local Result = {
    Rules     = merge(MakeHeadersRule, BuildToolRule),
    Artifacts = { MakeHeadersRule.Out, BuildToolRule.Out },
  }
  return Result
end

return Render
