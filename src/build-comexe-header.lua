--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Generate src/comexe.h with make-headers.exe

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

local HeaderFilename        = "src/comexe.h"
local GeneratorFilename     = "bin/tools/make-headers.exe"
local ConfigurationFilename = "src/makeheaders.conf"
local SourceDirectory       = "src"

--------------------------------------------------------------------------------
-- SOURCES                                                                    --
--------------------------------------------------------------------------------

local MakeheadersDeps = {
  GeneratorFilename,
  ConfigurationFilename,
  "src/platform.c",
  "src/lua-application.c",
  "src/bump-allocator.c",
  "src/growing-buffer.c",
  "src/trivial-queue-uint.c",
  "src/trivial-array.c",
  "src/lua-libminizip-ng.c",
  "src/lua-libffi.c",
  "src/lua-libbuffer.c",
  "src/lua-libwin32-service.c",
  "src/lua-libwin32-com.c",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Here we don't use ConfigurationFilename because of the "src/" prefix
  local Command = format("cd %s && $P{../%s} -h -f makeheaders.conf -o $P{../%s}",
                         SourceDirectory,
                         GeneratorFilename,
                         HeaderFilename)
  -- Main rule
  local Rule = {
    Ins      = MakeheadersDeps,
    Run      = { Command },
    Out      = HeaderFilename,
    Preserve = true, -- target comexe.h won't be deleted on "make clean"
  }
  local Result = {
    Rules     = { Rule           },
    Artifacts = { HeaderFilename },
  }
  return Result
end

return Render
