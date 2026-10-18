--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Build bin/app/lua55ce-runtime.zip from build-index.lua

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

local ManifestFilename  = "build-manifest-app-runtime.lua"
local BuildToolFilename = "bin/tools/buildtool.exe"

--------------------------------------------------------------------------------
-- HELPER                                                                     --
--------------------------------------------------------------------------------

local append = table.insert

local function ReadManifestFiles (ManifestFilename)
  local NewEnvironment = {}
  local Chunk, LoadErrorString = loadfile(ManifestFilename, "t", NewEnvironment)
  if (not Chunk) then
    error(format("cannot load %s: %s", ManifestFilename, LoadErrorString))
  end
  local Success, Entries = pcall(Chunk)
  assert(Success, format("manifest error in %s: %s", ManifestFilename, Entries))
  assert((type(Entries) == "table"), format("invalid format: %s", ManifestFilename))
  local Files = {}
  for Index = 1, #Entries do
    local Entry = Entries[Index]
    if Entry.File then
      append(Files, Entry.File)
    end
  end
  return Files
end

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Prerequisites are from:
  -- "runtime" and "tccvio" from build-index.lua
  -- build outputs (bin), listed in ManifestFilename
  local ManifestFiles = ReadManifestFiles(ManifestFilename)
  -- Format command
  local CommandLine = format("$P%s pack $P%s $OUT 9", BuildToolFilename, ManifestFilename)
  -- Zip rule ("runtime" and "tccvio" comes from the build-index.lua file)
  local ZipRule = {
    Ins   = merge({ ManifestFilename, BuildToolFilename }, ManifestFiles),
    Trees = { "runtime", "tccvio" },
    Run   = { CommandLine },
    Out   = "bin/app/lua55ce-runtime.zip",
  }
  -- Finalize rule
  local Result = {
    Rules     = { ZipRule     },
    Artifacts = { ZipRule.Out },
  }
  return Result
end

return Render
