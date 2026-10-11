--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Build bin/dist/lua55ce.zip

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local BuildToolFilename = "bin/tools/buildtool.exe"
local ManifestFilename  = "build-manifest-app-dist.lua"
local ZipFilename       = "bin/dist/lua55ce.zip"

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Format commands
  local Commands = {
    format("$P%s pack $P%s $OUT 9", BuildToolFilename, ManifestFilename),
  }
  -- Main pack rule
  local PackRule = {
    Needs = { "bin/app/lua55ce-runtime.zip" },
    Ins   = { ManifestFilename, BuildToolFilename },
    Run   = Commands,
    Out   = ZipFilename,
  }
  local Result = {
    Rules     = { PackRule    },
    Artifacts = { ZipFilename },
  }
  return Result
end

return Render
