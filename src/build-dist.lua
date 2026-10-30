--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Build bin/dist/lua55ce-<version>-<platform>.zip from build-index.lua
--
-- One archive + checksum file per platform
-- Read the version directly from src/version.h

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")

local readfile = Runtime.readfile
local format   = string.format
local append   = table.insert

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local BuildToolFilename = "bin/tools/buildtool.exe"
local VersionHeader     = "src/version.h"
local DistDirectory     = "bin/dist"

local ArchiveList = {
  {
    Suffix   = "windows-x86_64",
    Manifest = "build-manifest-app-dist-windows.lua",
    Needs    = {
      "bin/app/lua55ce-runtime.zip",
      "bin/x86_64-windows-gnu/src/lua55ce.exe",
    },
  },
  {
    Suffix   = "linux-x86_64",
    Manifest = "build-manifest-app-dist-linux.lua",
    Needs    = {
      "bin/app/lua55ce-runtime.zip",
      "bin/x86_64-linux-musl/src/lua55ce-musl",
      "bin/x86_64-linux-gnu/src/lua55ce-gnu",
    },
  },
}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function ReadVersion ()
  local Content = readfile(VersionHeader, "string")
  local Version
  if Content then
    Version = Content:match('COMEXE_VERSION%s+"([^"]+)"')
  end
  return Version
end

-- We will simply use lua55ce -x --checksum
local function GetLua55ceFilename (Environment)
  local Extension
  if (Environment.OS == "windows") then
    Extension = ".exe"
  else
    Extension = ""
  end
  local Filename = format("bin/%s/src/lua55ce%s", Environment.HOST_TRIPLE, Extension)
  return Filename
end

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Version is from src/version.h
  local Version = ReadVersion()
  assert(Version, "cannot read COMEXE_VERSION from src/version.h")
  -- Result
  local Rules     = {}
  local Artifacts = {}
  -- One pack rule and one checksum rule per archive
  local ArchiveIndex
  for ArchiveIndex = 1, #ArchiveList do
    local Archive          = ArchiveList[ArchiveIndex]
    local DistZipName      = format("lua55ce-%s-%s.zip", Version, Archive.Suffix)
    local DistZipFilename  = format("%s/%s", DistDirectory, DistZipName)
    local ChecksumFilename = format("%s.sha256", DistZipFilename)
    -- Main pack rule
    local PackRule = {
      Needs = Archive.Needs,
      Ins   = { Archive.Manifest, BuildToolFilename },
      Trees = { "doc" },
      Run   = { format("$P%s pack $P%s $OUT 9", BuildToolFilename, Archive.Manifest) },
      Out   = DistZipFilename,
    }
    -- lua55ce is used to compute checksums
    local HostLua55ceFilename = GetLua55ceFilename(Environment)
    local ChecksumRule = {
      Ins = { DistZipFilename, HostLua55ceFilename },
      -- We use "cd XX && checksum" so that the filenames do NOT contains the
      -- directory part (like /xx/dir/path/FILE) in the output, only FILE
      Run = { format("cd %s && $P{../../%s} -x --checksum -o %s.sha256 %s", DistDirectory, HostLua55ceFilename, DistZipName, DistZipName) },
      Out = ChecksumFilename,
    }
    -- Add rules and artifacts
    append(Rules,     PackRule)
    append(Rules,     ChecksumRule)
    append(Artifacts, DistZipFilename)
    append(Artifacts, ChecksumFilename)
  end
  -- Result
  local Result = {
    Rules     = Rules,
    Artifacts = Artifacts,
  }
  return Result
end

return Render
