--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Build bin/app/lua55ce-runtime.zip

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

local ManifestFilename  = "build-manifest-app-runtime.lua"
local BuildToolFilename = "bin/tools/buildtool.exe"

--------------------------------------------------------------------------------
-- HELPER                                                                     --
--------------------------------------------------------------------------------

local append = table.insert

-- Reuse manifest sources (build-manifest-app-runtime.lua, initially designed
-- for buildtool pack). Here, we will just read the entries, "Tree" is already
-- handled properly by the model.
local function ReadManifest (ManifestFilename)
  local NewEnvironment = {}
  local Chunk, LoadErrorString = loadfile(ManifestFilename, "t", NewEnvironment)
  if (not Chunk) then
    error(format("cannot load %s: %s", ManifestFilename, LoadErrorString))
  end
  local Entries = Chunk()
  assert((type(Entries) == "table"), format("invalid format: %s", ManifestFilename))
  local Files = {}
  local Trees = {}
  for Index = 1, #Entries do
    local Entry = Entries[Index]
    if Entry.File then
      append(Files, Entry.File)
    elseif Entry.Tree then
      append(Trees, Entry.Tree)
    end
  end
  return Files, Trees
end

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Read manifest entries
  local ManifestFiles, ManifestTrees = ReadManifest(ManifestFilename)
  -- Format command
  local CommandLine = format("$P%s pack $P%s $OUT 9", BuildToolFilename, ManifestFilename)
  -- Zip rule
  local ZipRule = {
    Ins   = merge({ ManifestFilename, BuildToolFilename }, ManifestFiles),
    Trees = ManifestTrees,
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
