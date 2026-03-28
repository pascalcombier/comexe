--------------------------------------------------------------------------------
-- NOTES                                                                      --
--------------------------------------------------------------------------------

-- Not supported:
-- Implicit "==" operator like in the string "lua 5.1"
-- Miss "upgrade"

-- NOTE the variable PackageIndex refer to index.lua content
-- NOTE index.lua format:
--
-- fileformat = "apm-index-v1",
-- index = {
--   ZipFilename1 = { ModuleMap }
--   ZipFilename2 = { ModuleMap }
-- }
--
-- with ModuleMap being a map NameVersion -> Details
--
-- EXAMPLE
--
-- fileformat = "apm-index-v1"
-- index = {
--   ["30log.zip"] = {
--     ["30log-0.8.0"] = {
--       dependencies = {
--         "lua >= 5.1"
--       },
--       description = {
--         homepage = "http://yonaba.github.io/30log",
--         license = "MIT <http://www.opensource.org/licenses/mit-license.php>",
--         summary = "30 lines library for object orientation"
--       }
--     }
--   },
--
--
-- Important functions:
-- APM_LoadPackageIndex
--

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime    = require("com.runtime")
local Minizip    = require("lib-minizip")
local Http       = require("socket.http")
local Url        = require("socket.url")
local serializer = require("trivial-serializer")
local apmcommon  = require("apm-common")

local format          = string.format
local sort            = table.sort
local append          = Runtime.append
local stringtrim      = Runtime.stringtrim
local contains        = Runtime.contains
local slice           = Runtime.slice
local writefile       = Runtime.writefile
local hassuffix       = Runtime.hassuffix
local fileexists      = Runtime.fileexists
local directoryexists = Runtime.directoryexists
local newpathname     = Runtime.newpathname
local makedirectory   = Runtime.makedirectory
local request         = Http.request
local IterateRead     = Minizip.IterateRead
local NewReader       = Minizip.NewReader

local APM_LOCAL_PACKAGES    = apmcommon.localpackages
local splitnameversion      = apmcommon.splitnameversion
local parsedependencystring = apmcommon.parsedependencystring
local compareversions       = apmcommon.compareversions

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local APM_INSTALL_DIRECTORY     = "share/lua/5.5"
local APM_CACHE_DIR             = ".comexe/apm"
local APM_CACHE_FILENAME        = format("%s/apm-index.lua",        APM_CACHE_DIR)
local APM_STATUS_CACHE_FILENAME = format("%s/apm-local-state.lua",  APM_CACHE_DIR)
local APM_REPOSITORY_FILENAME   = format("%s/apm-repositories.lua", APM_CACHE_DIR)

--------------------------------------------------------------------------------
-- AWESOME PACKAGE MANAGER: DEPENDENCIES                                      --
--------------------------------------------------------------------------------

local function APM_HaveDependency (Name, Operator, TargetVersion, LocalState)
  -- local data
  local SimplePackage = (Operator == nil) -- dependancies "socket" without version
  local DisplayName
  local Satisfied
  if SimplePackage then
    DisplayName = Name
  else
    DisplayName = format("%s %s %s", Name, Operator, TargetVersion)
  end
  io.write(format("CHECKING %s...", DisplayName))
  -- Check the module/package name:
  -- 1) local packages (socket, copas, etc)
  -- 2) installed package list cache
  -- 3) call require()
  local LocalPackageVersion = APM_LOCAL_PACKAGES[Name]
  if (LocalPackageVersion == nil) and LocalState then
    local StatusEntry = LocalState[Name]
    if StatusEntry then
      LocalPackageVersion = StatusEntry.version
    end
  end
  if LocalPackageVersion then
    Satisfied = compareversions(LocalPackageVersion, Operator, TargetVersion)
  elseif SimplePackage then
    local RequireSuccess = pcall(require, Name)
    Satisfied = RequireSuccess
  else
    Satisfied = false
  end
  -- Display result
  if Satisfied then
    io.write("OK\n")
  else
    io.write("MISSING\n")
  end
  -- Return value
  return Satisfied
end

local function APM_FindPackageFromRules (PackageIndex, PackageName, Rules)
  local BestPackage
  local BestVersion
  -- Traverse all the list to find the highest available version
  for ZipFilename, ModuleMap in pairs(PackageIndex) do
    -- Traverse all embedded packages (one zip can contain multiple versions or even different packages)
    for NameVersion, Details in pairs(ModuleMap) do
      -- Extract name and version (e.g. "30log-0.8.0" -> "30log", "0.8.0")
      local CandidateName, CandidateVersion = splitnameversion(NameVersion)
      -- If we have a candidate that matches the package name we are looking for
      if (CandidateName == PackageName) and CandidateVersion then
        local Success   = true
        local RuleIndex = 1
        -- Check if this candidate matches the rules
        while Success and (RuleIndex <= #Rules) do
          local Rule = Rules[RuleIndex]
          -- Compare version
          Success   = compareversions(CandidateVersion, Rule[2], Rule[3])
          RuleIndex = (RuleIndex + 1)
        end
        -- Select the highest candidate version
        if Success then
          if (BestVersion == nil) or compareversions(CandidateVersion, ">", BestVersion) then
            BestPackage = {
              repository   = Details.repository,
              filename     = ZipFilename,
              nameversion  = NameVersion,
              dependencies = Details.dependencies
            }
            BestVersion = CandidateVersion
          end
        end
      end
    end
  end
  -- Return value
  return BestPackage
end

-- Locate an exact NameVersion in the merged package index
local function APM_FindPackage (PackageIndex, PackageNameVersion)
  local ZipFilename, ModuleMap = next(PackageIndex)
  local ResultPackage
  while (ResultPackage == nil) and ZipFilename do
    local Details = ModuleMap[PackageNameVersion]
    if Details then
      ResultPackage = {
        filename     = ZipFilename,
        repository   = Details.repository,
        dependencies = Details.dependencies
      }
    end
    -- Next entry
    ZipFilename, ModuleMap = next(PackageIndex, ZipFilename)
  end
  -- Return value
  return ResultPackage
end

local function APM_CheckAllRules (Rules, LocalState)
  -- Local counter
  local Satisfied = 0
  -- Check all the rules
  for Index = 1, #Rules do
    local Rule = Rules[Index]
    if APM_HaveDependency(Rule[1], Rule[2], Rule[3], LocalState) then
      Satisfied = (Satisfied + 1)
    end
  end
  -- Evaluate Success
  local Success = (Satisfied == #Rules)
  return Success
end

local function APM_GetPackageState (VisitedState, PackageName)
  local PackageState = VisitedState[PackageName]
  if (not PackageState) then
    local NewPackageState = {
      Name      = PackageName,
      Rules     = {},    -- list of rules from APM_ParseDependencyString
      SeenRules = {},    -- rules cache map: prevent duplicated rules
      Handled   = false, -- package already processed
      Resolving = false, -- resolution started for this package
      Satisfied = false, -- if all rules are currently satisfied
    }
    PackageState = NewPackageState
    VisitedState[PackageName] = NewPackageState
  end
  return PackageState
end

local function APM_MakeRuleKey (Rule)
  local Rule1 = (Rule[1] or "")
  local Rule2 = (Rule[2] or "")
  local Rule3 = (Rule[3] or "")
  local RuleKey = format("%s-%s-%s", Rule1, Rule2, Rule3)
  return RuleKey
end

local function APM_ResolveDependencies (PackageIndex, LocalState, Dependencies, VisitedState, InstallCallback)
  -- local variables
  local Success = true
  local Index   = 1
  -- Main iteration
  while Success and (Index <= #Dependencies) do
    local DepString = Dependencies[Index]
    local NewRules  = parsedependencystring(DepString)
    if NewRules then
      local PackageName  = NewRules[1][1]
      local PackageState = APM_GetPackageState(VisitedState, PackageName)
      local PackageRules = PackageState.Rules
      local PackageSeen  = PackageState.SeenRules
      -- Merge rules with previous rules
      for Index, Rule in ipairs(NewRules) do
        local RuleKey = APM_MakeRuleKey(Rule)
        if (not PackageSeen[RuleKey]) then
          append(PackageRules, Rule)
          PackageSeen[RuleKey] = true
          -- No longer Satisfied: need to test again
          PackageState.Satisfied = false
        end
      end
      -- Check all the rules
      local IsSatisfied = PackageState.Satisfied
      if (not IsSatisfied) then
        IsSatisfied = APM_CheckAllRules(PackageRules, LocalState)
        PackageState.Satisfied = IsSatisfied
      end
      -- Visited & Conflict Detection
      if (not IsSatisfied) then
        if PackageState.Resolving then
          -- Already resolved
          print(format("CONFLICT: %s not satisfied by already resolved version", DepString))
          Success = false
        else
          PackageState.Resolving = true
          io.write(format("RESOLVING %s...", DepString))
          -- Use the merged rules to find the best package (pass explicit name)
          -- we already know the package name from the dependency string
          local NewPackage = APM_FindPackageFromRules(PackageIndex, PackageName, PackageRules)
          if NewPackage then
            -- The package passed to InstallCallback is be the exact NameVersion
            -- from the index, which APM_FindPackageFromRules already identified
            local DepNameVersion  = NewPackage.nameversion
            local NewDependencies = NewPackage.dependencies
            io.write(format("%s\n", DepNameVersion))
            -- Recursive resolution of dependencies
            if (NewDependencies == nil) or APM_ResolveDependencies(PackageIndex, LocalState, NewDependencies, VisitedState, InstallCallback) then
              InstallCallback(DepNameVersion)
            else
              Success = false
            end
          else
            print("ERROR\n")
            Success = false
          end
        end
      end
    end
    Index = (Index + 1)
  end
  return Success
end

--------------------------------------------------------------------------------
-- AWESOME PACKAGE MANAGER: PRIVATE FUNCTIONS                                 --
--------------------------------------------------------------------------------

local function APM_PrintError (...)
  local FormattedString = format(...)
  io.stderr:write(format("ERROR: %s\n", FormattedString))
end

local function APM_FatalError (...)
  APM_PrintError(...)
  os.exit(1)
end

local function APM_VerboseFetch (Uri)
  io.write(format("FETCHING %s...", Uri))
  local Body, HttpCode, Headers, StatusLine = request(Uri)
  if (Body and (HttpCode >= 200) and (HttpCode < 300)) then
    io.write("OK\n")
  else
    io.write(format("ERROR: %s\n", StatusLine))
  end
  return Body, HttpCode, Headers, StatusLine
end

local function APM_VerboseEnsureDirectory (Directory)
  local Exists = directoryexists(Directory)
  if (not Exists) then
    io.write(format("CREATING DIRECTORY %s...", Directory))
    local Success, ErrorMessage = makedirectory(Directory)
    if Success then
      io.write("OK\n")
    else
      io.write(format("ERROR: %s\n", ErrorMessage))
    end
    Exists = Success
  end
  if (not Exists) then
    APM_FatalError("ERROR: DIRECTORY %s could not be created", Directory)
  end
end

local function APM_VerboseWriteFile (Filename, EntryContent)
  -- Ensure directory exists
  local Pathname        = newpathname(Filename)
  local ParentDirectory = Pathname:parent():convert()
  APM_VerboseEnsureDirectory(ParentDirectory)
  -- Write the file
  io.write(format("WRITING %s...", Filename))
  local Success, ErrorString = writefile(Filename, EntryContent)
  if Success then
    io.write("OK\n")
  else
    io.write(format("ERROR: %s\n", ErrorString))
  end
end

local function APM_LoadLuaTable (Filename, DefaultValue)
  local Table, ErrorString = serializer.readfile(Filename)
  local ResultValue
  if Table then
    ResultValue = Table
  elseif (not fileexists(Filename)) then
    ResultValue = DefaultValue
  else
    APM_FatalError("Failed to load %s: %s", Filename, ErrorString)
  end
  return ResultValue
end

local function APM_SaveLuaTable (Filename, LuaTable)
  local Success, ErrorString = serializer.writefile(Filename, LuaTable)
  if (not Success) then
    APM_FatalError("Failed to save %s: %s", Filename, ErrorString)
  end
end

--------------------------------------------------------------------------------
-- REPO MANAGEMENT                                                            --
--------------------------------------------------------------------------------

local function FindStringInList (List, String)
  local Found = false
  local Index = 1
  local Count = #List
  while (not Found) and (Index <= Count) do
    local Value = List[Index]
    if (Value == String) then
      Found = true
    else
      Index = (Index + 1)
    end
  end
  return Found
end

local EMPTY_REPO_LIST = {
  repositories = {
    "https://raw.githubusercontent.com/pascalcombier/comlib/refs/heads/main/packages/lua/5.5/index.zip"
  }
}

local EMPTY_LOCAL_STATE = {
  installed = {}
}

local function APM_SafeCleanUri (Uri)
  if (Uri == nil) then
    APM_FatalError("Invalid URI: %q", Uri)
  end
  local CleanUri = stringtrim(Uri)
  if (CleanUri == nil) or (CleanUri == "") then
    APM_FatalError("Invalid URI: %q", Uri)
  end
  return CleanUri
end

local function HandleApmRepoList ()
  local Environment  = APM_LoadLuaTable(APM_REPOSITORY_FILENAME, EMPTY_REPO_LIST)
  local Repositories = Environment.repositories
  for Index, Uri in ipairs(Repositories) do
    print(Uri)
  end
  print(format("(%d repositories)", #Repositories))
end

local function HandleApmRepoAdd (RepositoryUri)
  local Environment  = APM_LoadLuaTable(APM_REPOSITORY_FILENAME, EMPTY_REPO_LIST)
  local Repositories = Environment.repositories
  local CleanUri     = APM_SafeCleanUri(RepositoryUri)
  local Found        = FindStringInList(Repositories, CleanUri)
  if (not Found) then
    append(Repositories, CleanUri)
    APM_SaveLuaTable(APM_REPOSITORY_FILENAME, Environment)
  end
end

local function HandleApmRepoRemove (RepositoryUri)
  local Environment  = APM_LoadLuaTable(APM_REPOSITORY_FILENAME, { repositories = EMPTY_REPO_LIST })
  local Repositories = Environment.repositories
  local CleanUri     = APM_SafeCleanUri(RepositoryUri)
  local NewList      = {}
  for Index, ExistingUri in ipairs(Repositories) do
    if (ExistingUri ~= CleanUri) then
      append(NewList, ExistingUri)
    end
  end
  if (#NewList == #Repositories) then
    APM_FatalError("Repository not found: %s", CleanUri)
  end
  -- Update environment
  Environment.repositories = NewList
  -- Save file
  APM_SaveLuaTable(APM_REPOSITORY_FILENAME, Environment)
end

local function HandleApmRepoCommand (Arguments)
  local Subcommand = Arguments[1]
  local Argument   = Arguments[2]
  if (Subcommand == "list") then
    HandleApmRepoList()
  elseif (Subcommand == "add") then
    HandleApmRepoAdd(Argument)
    HandleApmRepoList()
  elseif (Subcommand == "remove") then
    HandleApmRepoRemove(Argument)
    HandleApmRepoList()
  else
    APM_FatalError("Unknown apm repo subcommand: %q (expected add, remove or list)", Subcommand)
  end
end

--------------------------------------------------------------------------------
-- MODULE MANAGEMENT                                                          --
--------------------------------------------------------------------------------

-- From http://pascalcombier.github.io/apm/packages/lua/5.5/index.zip
-- Give "index.lua"
local function APM_GetZipEntryName (RepositoryUri)
  local Parsed = Url.parse(RepositoryUri)
  local ZipEntryName
  if Parsed and Parsed.path then
    -- Handle Uri like it was Unix pathname
    local UrlPath  = Parsed.path
    local Pathname = newpathname(UrlPath)
    -- Extract basename and extension
    local Filename, Basename, Extension = Pathname:getname()
    -- The ZIP contains a Lua index file with the same basename
    -- my-repo.zip will contain my-repo.lua ZIP entry
    if Basename and (Extension == "zip") then
      ZipEntryName = format("%s.lua", Basename)
    end
  end
  return ZipEntryName
end

-- From "https://repo.com/archive.zip", "pkg-1.0.zip"
-- Give "https://repo.com/pkg-1.0.zip"
local function APM_GetPackageUri (RepositoryUri, PackageFilename)
  local BaseUri = RepositoryUri:match("^(.*)/[^/]+$")
  local PackageUri
  if BaseUri then
    PackageUri = format("%s/%s", BaseUri, PackageFilename)
  end
  return PackageUri
end

local function APM_ParseIndexLuaString (IndexLuaContent, ChunkName)
  local Environment, ErrorString = serializer.readstring(IndexLuaContent, ChunkName)
  local PackageIndex
  local FileFormat
  if Environment then
    FileFormat   = Environment.fileformat
    PackageIndex = Environment.index
    if (FileFormat ~= "apm-index-v1") or (PackageIndex == nil) then
      APM_FatalError("Failed: index.lua invalid format (Expected 'apm-index-v1') (%q, %q)", FileFormat, PackageIndex)
    end
  else
    APM_FatalError("Failed to load index: %s", ErrorString)
  end
  return PackageIndex
end

-- The RepositoryIndex is just used for naming the fetched file
-- apm-repository-01.zip, apm-repository-02.zip, etc
local function APM_FetchAndParseRepository (RepositoryUri, RepositoryIndex)
  -- Fetch the repository
  local Body, StatusCode = APM_VerboseFetch(RepositoryUri)
  local IndexLuaContent
  if (Body == nil) or (StatusCode ~= 200) then
    APM_FatalError("Failed to download index from %s", RepositoryUri)
  end
  -- Check the extension
  if hassuffix(RepositoryUri, ".lua") then
    IndexLuaContent = Body
  elseif hassuffix(RepositoryUri, ".zip") then
    -- Write ZIP file
    local TargetZipFilename = format("%s/apm-repository-%2.2d.zip", APM_CACHE_DIR, RepositoryIndex)
    APM_VerboseWriteFile(TargetZipFilename, Body)
    -- Read ZIP entry
    local LuaEntryName         = APM_GetZipEntryName(RepositoryUri)
    local Reader, ErrorMessage = NewReader(TargetZipFilename)
    if (not Reader) then
      APM_FatalError(ErrorMessage)
    end
    IndexLuaContent = Reader:Read(LuaEntryName)
    Reader:Close()
    if (not IndexLuaContent) then
      APM_FatalError("%s not found in %s", LuaEntryName, RepositoryUri)
    end
  else
    APM_FatalError("Unsupported repository URI: %s", RepositoryUri)
  end
  -- At this stage we have IndexLuaContent which is a string
  local ChunkName   = format("@%s", RepositoryUri)
  local Environment = APM_ParseIndexLuaString(IndexLuaContent, ChunkName)
  return Environment
end

local function APM_MergePackageIndex (MergeIndex, RepositoryIndex, RepositoryUri)
  for ZipFilename, ModuleMap in pairs(RepositoryIndex) do
    if MergeIndex[ZipFilename] then
      APM_FatalError("Duplicate package archive across repositories: %s", ZipFilename)
    end
    local NewModuleMap = {}
    for NameVersion, Details in pairs(ModuleMap) do
      -- Add the repository info to the module map
      Details.repository = RepositoryUri
      NewModuleMap[NameVersion] = Details
    end
    -- Save the module map
    MergeIndex[ZipFilename] = NewModuleMap
  end
end

local function HandleApmUpdate ()
  -- Load repositories
  local Environment  = APM_LoadLuaTable(APM_REPOSITORY_FILENAME, EMPTY_REPO_LIST)
  local Repositories = Environment.repositories
  -- Check repositories
  if (#Repositories == 0) then
    APM_PrintError("No repository configured\n")
    APM_FatalError("Use 'lua55ce -x --apm repo add URL'")
  end
  local PackageIndex = {}
  -- Merge all the configured repositories
  for Index, Uri in ipairs(Repositories) do
    local RepositoryIndex = APM_FetchAndParseRepository(Uri, Index)
    APM_MergePackageIndex(PackageIndex, RepositoryIndex, Uri)
  end
  -- Write file
  local FileContents = {
    fileformat = "apm-index-v1",
    index      = PackageIndex
  }
  APM_SaveLuaTable(APM_CACHE_FILENAME, FileContents)
  -- Summary
  print(format("APM cache updated: %s", APM_CACHE_FILENAME))
end

local function APM_LoadPackageIndex ()
  -- Automatically fetch the index
  if (not fileexists(APM_CACHE_FILENAME)) then
    HandleApmUpdate()
  end
  local Environment  = APM_LoadLuaTable(APM_CACHE_FILENAME, { index = {} })
  local PackageIndex = Environment.index
  -- Return value
  return PackageIndex
end

local function HandleApmPrintList (SearchString)
  -- Load local cache
  local PackageIndex = APM_LoadPackageIndex()
  local MatchCount   = 0
  local TotalCount   = 0
  local Keys         = {}
  local Map          = {}
  -- Collect package versions
  for ZipFilename, ModuleMap in pairs(PackageIndex) do
    for NameVersion, Details in pairs(ModuleMap) do
      local Name, Version = splitnameversion(NameVersion)
      if Version then
        -- Print the entry if needed
        local PrintEntry = (SearchString == nil) or contains(NameVersion, SearchString)
        if PrintEntry then
          local NewKey   = format("%s-%s", Name, Version)
          local NewValue = NewKey
          append(Keys, NewKey)
          Map[NewKey] = NewValue
          MatchCount = (MatchCount + 1)
        end
        TotalCount = (TotalCount + 1)
      end
    end
  end
  -- Print the version in alphanumerical order
  sort(Keys)
  for KeyIndex, KeyValue in pairs(Keys) do
    local NameVersion = Map[KeyValue]
    print(NameVersion)
  end
  -- Summary
  if SearchString then
    print(format("%d/%d package found", MatchCount, TotalCount))
  else
    print(format("%d packages available", TotalCount))
  end
end

local function APM_DownloadPackage (PackageRepository, PackageFilename, PackageNameVersion)
  local CachedZipFilename = format("%s/%s", APM_CACHE_DIR, PackageFilename)
  if (not fileexists(CachedZipFilename)) then
    local PackageUri = APM_GetPackageUri(PackageRepository, PackageFilename)
    if (PackageUri == nil) then
      APM_FatalError("Invalid repository URI for package %s", PackageNameVersion)
    end
    local Body, StatusCode = APM_VerboseFetch(PackageUri)
    if (Body == nil) or (StatusCode ~= 200) then
      APM_FatalError("Failed to download package from %s", PackageUri)
    end
    APM_VerboseWriteFile(CachedZipFilename, Body)
  end
  -- Return the filename of the written file
  return CachedZipFilename
end

local function APM_ExtractPackageFiles (ZipFilename)
  -- List of installed files
  local InstalledFiles = {}
  -- local callback
  local function ReadEntryCallback (EntryName, ReadFunction, StopIterationFunction)
    if hassuffix(EntryName, ".lua") then
      -- Directory structure: package-name/version/files-or-directories
      -- We want to remove the first two components
      local EntryPathname = newpathname(EntryName)
      EntryPathname:remove(1) -- Remove package-name
      EntryPathname:remove(1) -- Remove version
      -- Merge the 2 pathnames
      local TargetPathname = newpathname(APM_INSTALL_DIRECTORY)
      local FilePathname   = (TargetPathname .. EntryPathname)
      -- Extract ZIP entry and write file
      local EntryContent = ReadFunction()
      if EntryContent then
        local Filename = FilePathname:convert("native")
        APM_VerboseWriteFile(Filename, EntryContent)
        append(InstalledFiles, Filename)
      end
    end
  end
  -- Start the iteration
  IterateRead(ZipFilename, ReadEntryCallback)
  -- Return the list of filenames
  return InstalledFiles
end

local function APM_RecordInstalledPackage (PackageName, PackageVersion, InstalledFiles)
  -- Load the current state
  local Environment = APM_LoadLuaTable(APM_STATUS_CACHE_FILENAME, EMPTY_LOCAL_STATE)
  local Installed   = Environment.installed
  -- Update the state
  local NewPackage = {
    version = PackageVersion,
    files   = InstalledFiles
  }
  Installed[PackageName] = NewPackage
  -- Save the file
  APM_SaveLuaTable(APM_STATUS_CACHE_FILENAME, Environment)
end

-- This function could be called manually from HandleApmInstall
-- or called recursively
local function HandleApmInstall (PackageNameVersion, VisitedState, LocalState, PackageIndex)
  -- Find package in the local cache
  local TargetPackage = APM_FindPackage(PackageIndex, PackageNameVersion)
  -- Error handling
  if (TargetPackage == nil) then
    APM_FatalError("Package not found: %s", PackageNameVersion)
  end
  -- Retrieve data
  local PackageFilename     = TargetPackage.filename
  local PackageRepository   = TargetPackage.repository
  local PackageDependencies = TargetPackage.dependencies
  -- Split name and version using APM_SplitNameVersion
  local PackageName, PackageVersion = splitnameversion(PackageNameVersion)
  -- Error handling
  if (not (PackageFilename and PackageName and PackageVersion)) then
    APM_FatalError("Invalid package name/version/file: %q %q %q", PackageName, PackageVersion, PackageNameVersion)
  end
  -- Check package state: list of rules and flags
  local PackageState   = APM_GetPackageState(VisitedState, PackageName)
  local ExistingStatus = LocalState[PackageName]
  local AlreadyInstalled
  if ExistingStatus and (ExistingStatus.version == PackageVersion) then
    PackageState.Satisfied = true
    PackageState.Handled   = true
    PackageState.Resolving = true
    print(format("ALREADY INSTALLED %s-%s", PackageName, PackageVersion))
    AlreadyInstalled = true
  else
    AlreadyInstalled = false
  end
  if (not AlreadyInstalled) and (not PackageState.Handled) then
    -- Mark early as visited to prevent APM_ResolveDependencies to loop
    PackageState.Handled   = true
    PackageState.Resolving = true
    -- Resolve dependencies
    if PackageDependencies then
      -- Local callback with reference to VisitedState
      local function InstallCallback (DependencyPackageName)
        HandleApmInstall(DependencyPackageName, VisitedState, LocalState, PackageIndex)
      end
      local Success = APM_ResolveDependencies(PackageIndex, LocalState, PackageDependencies, VisitedState, InstallCallback)
      if (not Success) then
        APM_FatalError("some dependencies could not be resolved")
      end
    end
    -- Download, extract and record
    local CachedZipFilename = APM_DownloadPackage(PackageRepository, PackageFilename, PackageNameVersion)
    local InstalledFiles    = APM_ExtractPackageFiles(CachedZipFilename)
    APM_RecordInstalledPackage(PackageName, PackageVersion, InstalledFiles)
    -- Package is now satisfied
    PackageState.Satisfied = true
    print(format("INSTALLED %s-%s", PackageName, PackageVersion))
  end
end

local function HandleApmUninstall (PackageName, LocalState)
  -- Check package status
  local PackageStatus = LocalState[PackageName]
  if (not PackageStatus) then
    APM_FatalError("Package not installed: %s", PackageName)
  end
  -- Retrieve package files
  local Files = PackageStatus.files
  -- Delete the files
  for Index, Filename in ipairs(Files) do
    if fileexists(Filename) then
      io.write(format("REMOVING %s...", Filename))
      local Success, ErrorString = os.remove(Filename)
      if Success then
        io.write("OK\n")
      else
        io.write(format("ERROR: %s\n", ErrorString))
      end
    end
  end
  -- Remove entry from the cache
  local Environment = APM_LoadLuaTable(APM_STATUS_CACHE_FILENAME, EMPTY_LOCAL_STATE)
  local Installed   = Environment.installed
  Installed[PackageName] = nil
  -- Update status cache
  APM_SaveLuaTable(APM_STATUS_CACHE_FILENAME, Environment)
  print(format("UNINSTALLED %s", PackageName))
end

local function HandleApmInstalled (Verbose, LocalState)
  local Count = 0
  for Name, Entry in pairs(LocalState) do
    local Version     = Entry.version
    local Files       = Entry.files
    local NameVersion = format("%s-%s", Name, Version)
    print(NameVersion)
    if Verbose and Files then
      for Index, Filename in ipairs(Files) do
        print(format("  %s", Filename))
      end
    end
    Count = (Count + 1)
  end
  print(format("%d packages installed", Count))
end

--------------------------------------------------------------------------------
-- REPO MANAGEMENT                                                            --
--------------------------------------------------------------------------------

local function APM_PrintUsage ()
  print("USAGE: lua55ce -x --apm COMMAND [ARGUMENTS]")
  print("    repo: add URL, remove URL, list")
  print("commands: update, list, search NAME, install NAME, uninstall NAME, installed")
end

local function HandleApmCommand (Arguments)
  local Subcommand = Arguments[1]
  local SubArgs    = slice(Arguments, 2, #Arguments)
  if (Subcommand == nil) or (Subcommand == "help") then
    APM_PrintUsage()
  elseif (Subcommand == "repo") then
    local RepoArgs = SubArgs
    HandleApmRepoCommand(RepoArgs)
  elseif (Subcommand == "update") then
    HandleApmUpdate()
  elseif (Subcommand == "list") then
    HandleApmPrintList()
  elseif (Subcommand == "search") then
    local SearchString = SubArgs[1]
    assert(SearchString, "usage: lua55ce -x --apm search NAME")
    HandleApmPrintList(SearchString)
  elseif (Subcommand == "install") then
    local PackageName = SubArgs[1]
    assert(PackageName, "usage: lua55ce -x --apm install NAME")
    local NewState     = {} -- In-memory state to store travsersing state
    local Environment  = APM_LoadLuaTable(APM_STATUS_CACHE_FILENAME, EMPTY_LOCAL_STATE)
    local Installed    = Environment.installed
    local PackageIndex = APM_LoadPackageIndex()
    HandleApmInstall(PackageName, NewState, Installed, PackageIndex)
    print("Note: Packages are third-party software with their own LICENSES")
  elseif (Subcommand == "uninstall") then
    local PackageNameVersion = SubArgs[1]
    assert(PackageNameVersion, "usage: lua55ce -x --apm uninstall NAME")
    local PackageName, PackageVersion = splitnameversion(PackageNameVersion)
    local PackageToRemove = (PackageName or PackageNameVersion)
    local Environment     = APM_LoadLuaTable(APM_STATUS_CACHE_FILENAME, EMPTY_LOCAL_STATE)
    local Installed       = Environment.installed
    HandleApmUninstall(PackageToRemove, Installed)
  elseif (Subcommand == "installed") then
    local Verbose     = (SubArgs[1] == "-v")
    local Environment = APM_LoadLuaTable(APM_STATUS_CACHE_FILENAME, EMPTY_LOCAL_STATE)
    local Installed   = Environment.installed
    HandleApmInstalled(Verbose, Installed)
  else
    APM_FatalError("Unknown apm subcommand: %q (expected update, list, search, install, uninstall, installed or repo)", Subcommand)
  end
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  HandleApmCommand = HandleApmCommand
}

return PUBLIC_API
