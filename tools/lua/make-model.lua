--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- This library is design to help generating makefiles.
-- Confirmed: generating Makefiles is not straightforward

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime  = require("com.runtime")
local Template = require("string-template")

local format = string.format
local concat = table.concat
local append = table.insert
local sort   = table.sort

local newpathname       = Runtime.newpathname
local getparam          = Runtime.getparam
local listfiles         = Runtime.listfiles
local newstringtemplate = Template.newstringtemplate

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local MAKE_MARKER_NAME = "auto-dir-ok"

local EMPTY_LIST = {}

--------------------------------------------------------------------------------
-- USEFUL FUNCTIONS                                                           --
--------------------------------------------------------------------------------

local function MAKE_RemoveDuplicates (Array)
  local NewArray = {}
  local Seen     = {}
  for Index, Value in ipairs(Array) do
    if (Seen[Value] == nil) then
      Seen[Value] = true
      append(NewArray, Value)
    end
  end
  return NewArray
end

local function MAKE_MergeHashMap (Base, Override)
  local Result = {}
  for Name, Value in pairs(Base) do
    Result[Name] = Value
  end
  for Name, Value in pairs(Override) do
    Result[Name] = Value
  end
  return Result
end

local function MAKE_IsEmptyTable (Table)
  return (next(Table) == nil)
end

local function MAKE_SplitTriple (Triple)
  local Arch, OS, Libc = Triple:match("^([^-]+)-([^-]+)-([^-]+)$")
  return Arch, OS, Libc
end

--------------------------------------------------------------------------------
-- HOST-RELATED THINGS                                                        --
--------------------------------------------------------------------------------

local function MAKE_RenderPathLinux (Pathname)
  return newpathname(Pathname):convert("linux")
end

local function MAKE_RenderPathWindows (Pathname)
  return newpathname(Pathname):convert("windows")
end

local MAKE_HostProfiles = {
  linux = {
    Separator    = "/",
    PathRenderer = MAKE_RenderPathLinux,
    Commands     = {
      COPY    = "cp -f %1 %2",
      COPYDIR = "cp -R -f %1 %2",
      RMDIR   = "rm -rf %1",
      RMFILES = "rm -f %2+",
    },
  },
  windows = {
    Separator    = "\\",
    PathRenderer = MAKE_RenderPathWindows,
    Commands     = {
      COPY    = "copy /Y %1 %2 1>NUL",
      COPYDIR = "xcopy /E /I /Y %1 %2 >NUL",
      RMDIR   = "if exist %1 rd /S /Q %1",
      RMFILES = "if exist %1 del /F /Q %2+ 2>NUL",
    },
  },
}

local MAKE_TRIPLE_VALID_LIBC = {
  gnu  = true,
  musl = true,
  msvc = true,
}

local function MAKE_ValidateTriple (Triple)
  local Arch, OS, Libc = MAKE_SplitTriple(Triple)
  assert(Arch and OS and Libc,         format("invalid target triple: %q (expected <arch>-<os>-<libc>, like x86_64-linux-musl)", Triple))
  assert(MAKE_HostProfiles[OS],        format("invalid target os: %s (expected windows or linux)", OS))
  assert(MAKE_TRIPLE_VALID_LIBC[Libc], format("invalid target libc: %s (expected gnu, musl, or msvc)", Libc))
end

--------------------------------------------------------------------------------
-- SANDBOX IMPLEMENTATION                                                     --
--------------------------------------------------------------------------------

local function MAKE_Merge (...)
  local Result = {}
  local Count  = select("#", ...)
  for Index = 1, Count do
    local Item = select(Index, ...)
    if (type(Item) == "table") then
      if (#Item > 0) then
        -- add all items of the array
        for ElementIndex = 1, #Item do
          append(Result, Item[ElementIndex])
        end
      elseif (not MAKE_IsEmptyTable(Item)) then
        -- add standard hashtable as single object
        append(Result, Item)
      end
    else
      -- add item
      append(Result, Item)
    end
  end
  return Result
end

local function MAKE_Map (Array, Function)
  local NewArray = {}
  for Index = 1, #Array do
    NewArray[Index] = Function(Array[Index])
  end
  return NewArray
end

local MAKE_Sandbox = {
  merge       = MAKE_Merge,
  map         = MAKE_Map,
  newpathname = newpathname,
  concat      = concat,
  format      = format,
}

-- It's not really a "sandbox" because it inherits everything from Lua
local SANDBOX_Metatable = {
  -- METATABLE_UserDefinedMethods
  __index = _G
}

setmetatable(MAKE_Sandbox, SANDBOX_Metatable)

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function MAKE_BuildEnvironment (Context, Triple)
  -- Split triple string
  local Arch, OS, Libc = MAKE_SplitTriple(Triple)
  -- Create a new environment
  local NewEnvironment = {
    TRIPLE      = Triple,
    HOST_TRIPLE = Context.Triple,
    OS          = OS,
    ARCH        = Arch,
    LIBC        = Libc,
  }
  -- Return value
  return NewEnvironment
end

local function MAKE_NativePath (Pathname)
  return newpathname(Pathname):convert("native")
end

local function MAKE_InternalDirName (Pathname)
  return newpathname(Pathname):getdirectory("internal")
end

local function MAKE_CollectTreeFiles (Directory)
  -- local data
  local NativeDirectory = MAKE_NativePath(Directory)
  local Files           = {}
  -- local callback
  local function ListFilesCallback (Path, FileType)
    if (FileType ~= "directory") then
      append(Files, newpathname(Path):convert("internal"))
    end
  end
  local Success, ErrorString = listfiles(NativeDirectory, ListFilesCallback)
  if Success then
    sort(Files)
  else
    error(format("failed to list files in %s: %s", Directory, ErrorString))
  end
  return Files, ErrorString
end

local function MAKE_ExpandValue (Context, Value, Environment)
  local NewTemplate = newstringtemplate(Value)
  return NewTemplate:render(Environment, nil, Context.PathRenderer)
end

local function MAKE_ExpandList (Context, List, Environment)
  local NewList  = {}
  local SafeList = (List or EMPTY_LIST)
  for Index, Entry in ipairs(SafeList) do
    local NewString = MAKE_ExpandValue(Context, Entry, Environment)
    append(NewList, NewString)
  end
  return NewList
end

--------------------------------------------------------------------------------
-- DESCRIPTION LOADING                                                        --
--------------------------------------------------------------------------------

local function MAKE_LoadFile (Context, Filename)
  local CacheKey     = MAKE_NativePath(Filename)
  local CachedResult = Context.FileCache[CacheKey]
  if (not CachedResult) then
    local Chunk, LoadErrorString = loadfile(Filename, "t", MAKE_Sandbox)
    if (not Chunk) then
      error(format("cannot load description %s: %s", Filename, LoadErrorString))
    end
    local Success, Value = pcall(Chunk)
    if (not Success) then
      error(format("description error in %s: %s", Filename, Value))
    end
    CachedResult = Value
    Context.FileCache[CacheKey] = CachedResult
  end
  return CachedResult
end

-- Validate a component result { Rules, Artifacts, CleanDirs }
local function MAKE_ValidateComponent (Result, Filename)
  if (type(Result) ~= "table") then
    error(format("component must return a table: %s", Filename))
  end
  if (type(Result.Rules) ~= "table") then
    error(format("component missing Rules list: %s", Filename))
  end
  if (type(Result.Artifacts) ~= "table") then
    error(format("component missing Artifacts list: %s", Filename))
  end
  if (Result.CleanDirs ~= nil) and (type(Result.CleanDirs) ~= "table") then
    error(format("component CleanDirs must be a list: %s", Filename))
  end
end

local function MAKE_ValidateRootDescription (Description, RootFile)
  if (type(Description) ~= "table") then
    error(format("root description must return a table: %s", RootFile))
  end
  if (type(Description.Triples) ~= "table") then
    error(format("root description missing Triples list: %s", RootFile))
  end
  if (type(Description.Components) ~= "table") then
    error(format("root description missing Components list: %s", RootFile))
  end
  for Index, Entry in ipairs(Description.Components) do
    local Scope = Entry[1]
    local File  = Entry[2]
    if (type(Scope) ~= "string") or (type(File) ~= "string") then
      error(format("component entry must be a { scope, file } pair: %s", RootFile))
    end
    if (Scope ~= "ALL") and (Scope ~= "HOST") then
      error(format("invalid component scope: %q (expected ALL or HOST)", Scope))
    end
  end
end

local function MAKE_NormalizeTriples (Context, Description)
  -- Remove duplicates if any
  local Triples = MAKE_RemoveDuplicates(Description.Triples)
  -- Validate
  for Index, Triple in ipairs(Triples) do
    MAKE_ValidateTriple(Triple)
  end
  -- Add the HOST if none
  if (#Triples == 0) then
    append(Triples, Context.Triple)
  end
  return Triples
end

--------------------------------------------------------------------------------
-- RULE INSTANTIATION                                                         --
--------------------------------------------------------------------------------

local function MAKE_RejectPaths (List, Field)
  local SafeList = (List or EMPTY_LIST)
  for Index, Entry in ipairs(SafeList) do
    if (type(Entry) ~= "string") then
      error(format("%s entry must be a path string, got %s", Field, type(Entry)))
    end
    if Entry:find("$P", 1, true) then
      error(format("$P is only valid in Run, not in %s: %s", Field, Entry))
    end
  end
end

local function MAKE_ValidateOuts (Rule)
  -- Retrieve data
  local SingleOut = Rule.Out
  local OutList   = Rule.Outs
  -- Validate inputs: need 1 of the 2 but not both
  assert((SingleOut == nil) or (OutList == nil), "rule must declare Out (string) or Outs (list), but not both")
  assert((SingleOut ~= nil) or (OutList ~= nil), "rule must declare Out or Outs")
  if SingleOut then
    assert((type(SingleOut) == "string"), "rule Out must be a string")
  else
    assert((type(OutList) == "table"), "rule Outs must be a list")
    assert((#OutList > 0),             "rule Outs must not be empty")
    for Index, Entry in ipairs(OutList) do
      assert((type(Entry) == "string"), "rule output must be a string")
    end
  end
end

local function MAKE_ValidateRule (Rule, Filename)
  assert((type(Rule.Run) == "table") and (#Rule.Run > 0), format("rule missing Run list (Out %s): %s", Rule.Outs[1], Filename))
  if Rule.Preserve then
    assert((type(Rule.Preserve) == "boolean"), "rule Preserve must be a boolean")
  end
  MAKE_RejectPaths(Rule.Outs,  "Outs")
  MAKE_RejectPaths(Rule.Ins,   "Ins")
  MAKE_RejectPaths(Rule.Needs, "Needs")
  MAKE_RejectPaths(Rule.Trees, "Trees")
end

local function MAKE_BuildRule (Context, Rule, Environment, Filename)
  -- Validate outs
  MAKE_ValidateOuts(Rule)
  -- Normalize Outs
  local Outs
  if Rule.Out then
    Outs = { Rule.Out }
  else
    Outs = Rule.Outs
  end
  -- New rule
  local NewRule = {
    Outs     = Outs,
    Ins      = Rule.Ins,
    Needs    = Rule.Needs,
    Trees    = Rule.Trees,
    Run      = Rule.Run,
    Host     = Rule.Host,
    Preserve = Rule.Preserve,
  }
  -- Validate first, *then* expand, order is important
  MAKE_ValidateRule(NewRule, Filename)
  -- Expansion
  NewRule.Outs  = MAKE_ExpandList(Context, NewRule.Outs,  Environment)
  NewRule.Ins   = MAKE_ExpandList(Context, NewRule.Ins,   Environment)
  NewRule.Needs = MAKE_ExpandList(Context, NewRule.Needs, Environment)
  NewRule.Trees = MAKE_ExpandList(Context, NewRule.Trees, Environment)
  NewRule.Run   = MAKE_ExpandList(Context, NewRule.Run,   Environment)
  return NewRule
end

local function MAKE_InstantiateComponent (Context, RenderFunction, Environment, Filename)
  -- Render the component and validate
  local RenderOutput = RenderFunction(Environment)
  MAKE_ValidateComponent(RenderOutput, Filename)
  -- Update the $VARIABLES, $COMMAND %1 and $P/tmp/paths (STEP 1)
  local NewRules = {}
  for Index, Rule in ipairs(RenderOutput.Rules) do
    local NewRule = MAKE_BuildRule(Context, Rule, Environment, Filename)
    append(NewRules, NewRule)
  end
  -- Make sure Artifacts and CleanDir don't contain $P/path/dirs
  MAKE_RejectPaths(RenderOutput.Artifacts, "Artifacts")
  MAKE_RejectPaths(RenderOutput.CleanDirs, "CleanDirs")
  -- Update the $VARIABLES, $COMMAND %1 and $P/tmp/paths (STEP 2)
  local NewArtifacts = MAKE_ExpandList(Context, RenderOutput.Artifacts, Environment)
  local NewCleanDirs = MAKE_ExpandList(Context, RenderOutput.CleanDirs, Environment)
  -- Return the rendered component
  local NewComponent = {
    Rules     = NewRules,
    Artifacts = NewArtifacts,
    CleanDirs = NewCleanDirs
  }
  return NewComponent
end

--------------------------------------------------------------------------------
-- PASSES AND MERGE                                                           --
--------------------------------------------------------------------------------

-- String signature for hashtable key
local function MAKE_RuleSignature (Rule)
  local ItemSeparator  = "\x01"
  local FieldSeparator = "\x02"
  local Fields = {
    concat(Rule.Outs,  ItemSeparator),
    concat(Rule.Ins,   ItemSeparator),
    concat(Rule.Needs, ItemSeparator),
    concat(Rule.Trees, ItemSeparator),
    concat(Rule.Run,   ItemSeparator),
    tostring(Rule.Host),
    tostring(Rule.Preserve)
  }
  local Signature = concat(Fields, FieldSeparator)
  return Signature
end

-- Duplicate check is per pass
-- Same output twice in the same pass -> error
-- Same output in different passes    -> ignore
--
-- Example of rule:
-- {
--   Needs = { "bin/tools/make-headers.exe" },
--   Ins   = { "src/app.c" },
--   Run   = { "$CC -c $IN -o $OUT" },
--   Out   = "bin/$TRIPLE/src/app.o" (stored as {  "bin/$TRIPLE/src/app.o" })
--   Host  = true,
-- }
local function MAKE_RegisterRule (Rule, Registration, CurrentPassIndex)
  -- Retrive data
  local RuleByMainOutput  = Registration.RuleByMainOutput
  local PassByRule        = Registration.PassByRule
  local RegistrationOrder = Registration.RegistrationOrder
  -- Retrieve the main output name: Outs[1]
  local MainOutput   = Rule.Outs[1]
  local ExistingRule = RuleByMainOutput[MainOutput]
  if ExistingRule then
    if (PassByRule[ExistingRule] == CurrentPassIndex) then
      error(format("duplicate rule for output %s (twice in pass %d)", MainOutput, CurrentPassIndex))
    end
    local ExistingSignature = MAKE_RuleSignature(ExistingRule)
    local NewSignature      = MAKE_RuleSignature(Rule)
    if (ExistingSignature ~= NewSignature) then
      error(format("conflicting rule for output %s", MainOutput))
      -- Example of issue:
      -- { Out = "bin/version.txt", Ins = { "bin/$TRIPLE/src/version.h" }, Run = { "$COPY $INS $OUT" } }
      -- The target name is the same and the rule identical
    end
  else
    -- "bin/$TRIPLE/src/app.o" -> Rule
    RuleByMainOutput[MainOutput] = Rule
    -- Rule -> Pass 1, 2, 3, etc
    PassByRule[Rule] = CurrentPassIndex
    -- Save the rule
    append(RegistrationOrder, Rule)
  end
end

--------------------------------------------------------------------------------
-- PREREQUISITES                                                              --
--------------------------------------------------------------------------------

-- From the rule:
-- Rule = {
--   Outs  = { "bin/app.o" },
--   Needs = { "bin/headers.exe", "does-not-exist.txt" },
--   Ins   = { "src/app.c", "LICENSE" },
-- }
-- 
-- We add Prerequisites:
-- Rule.Prerequisites = { "bin/headers.exe", "src/app.c", "LICENSE" }
local function MAKE_BuildPrerequisites (Rule, RuleByMainOutput)
  -- local data
  local Prerequisites = {}
  -- Prerequisites refer to Make prerequisites:
  -- target: prerequisites
  --   recipe
  --
  -- Prerequisites contains all the Rule.Needs which are PRODUCED by our build
  -- descriptions. "does-not-exist.txt" is not produced by our build
  -- descriptions, so it won't be append vto Prerequisites
  for Index, Entry in ipairs(Rule.Needs) do
    if RuleByMainOutput[Entry] then
      append(Prerequisites, Entry)
    end
  end
  -- We add all the manual files from "Ins"
  for Index, Entry in ipairs(Rule.Ins) do
    append(Prerequisites, Entry)
  end
  -- Dynamic file discovery
  for Index, Tree in ipairs(Rule.Trees) do
    local Files, ErrorString = MAKE_CollectTreeFiles(Tree)
    assert(Files, format("cannot read source tree %s: %s", Tree, ErrorString))
    for FileIndex, File in ipairs(Files) do
      append(Prerequisites, File)
    end
  end
  -- Update rule
  Rule.Prerequisites = MAKE_RemoveDuplicates(Prerequisites)
end

-- Render all the RUN lines of a Rule
--
-- Rule.Outs[1] is guaranteed to exist (MAKE_ValidateRule)
-- Rule.Ins can be empty table
-- Rule.Ins can contain duplicates
-- 
local function MAKE_RenderRecipe (Context, Rule)
  -- local data
  local MainOutput  = Rule.Outs[1]
  local NamedInputs = MAKE_RemoveDuplicates(Rule.Ins)
  -- Prepare the environment variables for the template
  local Values = {
    OUT = Context.PathRenderer(MainOutput),
  }
  -- Attach the optional $INS and $IN
  if (#NamedInputs > 0) then
    local MainInput  = NamedInputs[1]
    local InputPaths = MAKE_Map(NamedInputs, Context.PathRenderer)
    Values.INS = concat(InputPaths, " ")
    Values.IN  = Context.PathRenderer(MainInput)
  end
  -- Render each RUN line
  local Lines = {}
  for Index, Run in ipairs(Rule.Run) do
    local Template = newstringtemplate(Run)
    local RuleLine = Template:render(Values, Context.CommandText, Context.PathRenderer)
    append(Lines, RuleLine)
  end
  return Lines
end

--------------------------------------------------------------------------------
-- CLEAN MANAGEMENT                                                           --
--------------------------------------------------------------------------------

local function MAKE_BuildCleanCommand (Context, Line)
  local NewTemplate = newstringtemplate(Line)
  return NewTemplate:render(nil, Context.CommandText, Context.PathRenderer)
end

-- If a directory is already handled by a registed parent directory
local function MAKE_IsUnderCleanDir (Directory, CleanDirs)
  local Result = false
  local Index  = 1
  local Count  = #CleanDirs
  while (not Result) and (Index <= Count) do
    local CleanDir = CleanDirs[Index]
    local Prefix   = format("%s/", CleanDir)
    if (Directory == CleanDir) or (Directory:sub(1, #Prefix) == Prefix) then
      Result = true
    else
      Index = (Index + 1)
    end
  end
  return Result
end

-- Merge together
--   User-specified CleanDirs (from the component)
--   Rule-generated Outs
--
-- Care about the "Preserve" flag: when a rule is marked "Preserve", its Outs
-- are not cleaned. Only used today for generated comexe.h
--
-- Example
-- ItemsByDir["bin"] = { "bin/a.exe", "bin/b.exe" }
-- $RMFILES bin bin/a.exe bin/b.exe bin/auto-dir-ok
--   if exist bin del /F /Q bin\a.exe bin\b.exe bin\auto-dir-ok 2>NUL
local function MAKE_BuildCleanCommands (Context, RulesInOrder, CleanDirList)
  -- local data: list of strings commands
  local CleanCommands = {}
  -- User-specified CleanDirs
  for Index, CleanDir in ipairs(CleanDirList) do
    local CleanCommand = MAKE_BuildCleanCommand(Context, format("$RMDIR %s", Context.PathRenderer(CleanDir)))
    append(CleanCommands, CleanCommand)
  end
  -- Order rules output directories
  local ItemsByDir = {} -- memo
  local ItemDirs   = {}
  for Index, Rule in ipairs(RulesInOrder) do
    for Index, Output in ipairs(Rule.Outs) do
      local OutputDir = MAKE_InternalDirName(Output)
      if (not Rule.Preserve) and (not MAKE_IsUnderCleanDir(OutputDir, CleanDirList)) then
        -- Add a new list for that directory if needed
        local Items = ItemsByDir[OutputDir]
        if (not Items) then
          Items = {}
          ItemsByDir[OutputDir] = Items
          append(ItemDirs, OutputDir)
        end
        -- Add that item
        append(Items, Output)
      end
    end
  end
  -- Sort the directories so the clean commands are always in the same order (deterministic)
  sort(ItemDirs)
  -- Merge the grouped items into CleanCommands
  for Index, OutputDir in ipairs(ItemDirs) do
    local Items = ItemsByDir[OutputDir]
    -- Automatically clean the marker file for that directory
    if (OutputDir ~= "") then
      append(Items, format("%s/%s", OutputDir, MAKE_MARKER_NAME))
    end
    -- Add the clean command
    local ItemPaths       = MAKE_Map(Items, Context.PathRenderer)
    local ItemPathsString = concat(ItemPaths, " ")
    -- A root-level output has no directory, so this %1 is "."
    local Line            = format("$RMFILES %s %s", Context.PathRenderer(OutputDir), ItemPathsString)
    local CleanCommand    = MAKE_BuildCleanCommand(Context, Line)
    append(CleanCommands, CleanCommand)
  end
  return CleanCommands
end

--------------------------------------------------------------------------------
-- MODEL BUILDING                                                             --
--------------------------------------------------------------------------------

local function MAKE_InstantiatePasses (Context, RootFile, RootDescription, Triples, Registration)
  -- Local data
  local RootDir      = MAKE_InternalDirName(RootFile)
  local ArtifactList = {}
  local CleanDirList = {}
  -- For each triple
  for PassIndex, Triple in ipairs(Triples) do
    local IsHostPass     = (Triple == Context.Triple)
    local NewEnvironment = MAKE_BuildEnvironment(Context, Triple)
    -- RootDescription.Components EXAMPLE
    -- Components = {
    --   { "HOST", "src/comexe-header.lua" },
    --   { "ALL",  "src/app.lua"           },
    --   { "ALL",  "src/runtime.lua"       },
    --   { "HOST", "src/dist.lua"          },
    -- },
    for Index, Entry in ipairs(RootDescription.Components) do
      local Scope    = Entry[1]
      local Filename = Entry[2]
      local Needed   = ((Scope == "ALL") or IsHostPass)
      if Needed then
        -- Load the ComponentDesc and get the Render function
        local FullPath       = newpathname(RootDir, Filename):convert("internal")
        local RenderFunction = MAKE_LoadFile(Context, FullPath)
        assert((type(RenderFunction) == "function"), format("component must return a function: %s", FullPath))
        -- Collect component's metadata
        -- Retrieve the component directory name (newpathname(""):getname() can return nil)
        local ComponentDir  = MAKE_InternalDirName(Filename)
        local ComponentName = (newpathname(ComponentDir):getname() or "")
        local ComponentDict = { DIR = ComponentDir, NAME = ComponentName }
        local ComponentEnv  = MAKE_MergeHashMap(NewEnvironment, ComponentDict)
        -- Create a new component object
        local Instance = MAKE_InstantiateComponent(Context, RenderFunction, ComponentEnv, FullPath)
        -- Register component's rules
        --  ComponentDescription.Rules EXAMPLE
        --
        --  local function MakeCompileRule (Source)
        --    local FlagsString = concat(BuildFlags, " ")
        --    local Path        = format("$DIR/%s", Source)
        --    local Name, Basename, Extension = newpathname(Path):getname()
        --    assert((Extension == "c"), format("source is not a C file (got %q)", Path))
        --    local NewRule = {
        --      Ins = { Path },
        --      Run = { format("zig cc %s -c $IN -o $OUT", FlagsString) },
        --      Out = format("bin/$TRIPLE/$NAME/%s.o", Basename),
        --    }
        --    return NewRule
        --  end
        --
        -- IsHostPass refer to the current triple being HOST
        -- Rule.Host means a rule to do only for host (even for "ALL", like makeheaders.c in app.lua)
        for RuleIndex, Rule in ipairs(Instance.Rules) do
          if (not Rule.Host) or IsHostPass then
            MAKE_RegisterRule(Rule, Registration, PassIndex)
          end
        end
        -- Register component's artifacts and clean directories
        --  Result = {
        --    Rules     = AllRules,
        --    Artifacts = Artifacts,
        --    CleanDirs = { "bin/tcc-vio" },
        --  }
        for ArtifactIndex, Artifact in ipairs(Instance.Artifacts) do
          append(ArtifactList, Artifact)
        end
        for CleanIndex, CleanDir in ipairs(Instance.CleanDirs) do
          append(CleanDirList, newpathname(CleanDir):convert("internal"))
        end
      end
    end
    -- Top-level RootDescription
    -- RootDescription.CleanDirs EXAMPLE
    --  CleanDirs = {
    --    "bin/$TRIPLE/src",
    --    "bin/app",
    --    "dist",
    --  },
    --
    -- For each directory, replace the embedded variables by their values
    local RootDescriptionCleanDirs = (RootDescription.CleanDirs or EMPTY_LIST)
    for Index, Directory in ipairs(RootDescriptionCleanDirs) do
      local ExpandedValue = MAKE_ExpandValue(Context, Directory, NewEnvironment)
      append(CleanDirList, newpathname(ExpandedValue):convert("internal"))
    end
  end
  -- Remove duplicates
  local NewArtifactList = MAKE_RemoveDuplicates(ArtifactList)
  local NewCleanDirList = MAKE_RemoveDuplicates(CleanDirList)
  return NewArtifactList, NewCleanDirList
end

local function MAKE_BuildModel (Context, RootFilename, RootDescription, Triples)
  -- Rule registration state
  local Registration = {
    RegistrationOrder = {}, -- Rules in declaration order
    RuleByMainOutput  = {}, -- Rules dict Out[1]->Rule
    PassByRule        = {}, -- Rules dict Rule->PassIndex
  }
  -- Extract references
  local RuleByMainOutput = Registration.RuleByMainOutput
  local RulesInOrder     = Registration.RegistrationOrder
  -- Handle passes
  local ArtifactList, CleanDirList = MAKE_InstantiatePasses(Context, RootFilename, RootDescription, Triples, Registration)
  -- Finalize rules (need RuleByMainOutput to be prepared for prerequisites)
  for Index, Rule in ipairs(RulesInOrder) do
    -- target: prerequisites
    --   recipe
    -- A single "recipe" can contain multiple lines
    MAKE_BuildPrerequisites(Rule, RuleByMainOutput)
    -- Rules.Outs[1] is guaranteed to exist by MAKE_ValidateRule
    local MainOutput = Rule.Outs[1]
    -- Add more info
    Rule.OutDir   = MAKE_InternalDirName(MainOutput)
    Rule.RunLines = MAKE_RenderRecipe(Context, Rule)
  end
  -- Make sure artifacts refer to existing rules
  for Index, Artifact in ipairs(ArtifactList) do
    assert(RuleByMainOutput[Artifact], format("artifact is not a rule output: %s", Artifact))
  end
  -- Make it deterministic (don't care the declaration order)
  sort(CleanDirList)
  -- Create the new model
  local NewModel = {
    RootFile      = RootFilename,
    HostOS        = Context.OS,
    HostTriple    = Context.Triple,
    HostSeparator = Context.Separator,
    Triples       = Triples,
    Environment   = (RootDescription.Environment or EMPTY_LIST),
    Rules         = RulesInOrder,
    Artifacts     = ArtifactList,
    CleanCommands = MAKE_BuildCleanCommands(Context, RulesInOrder, CleanDirList),
    MarkerName    = MAKE_MARKER_NAME,
  }
  return NewModel
end

--------------------------------------------------------------------------------
-- HOST-SPECIFIC THINGS                                                       --
--------------------------------------------------------------------------------

local function MAKE_NewContext (OptionalHostTriple)
  local HostTriple
  local HostArch
  local HostOs
  -- Determine host
  if OptionalHostTriple then
    MAKE_ValidateTriple(OptionalHostTriple)
    HostTriple = OptionalHostTriple
    HostArch, HostOs = MAKE_SplitTriple(OptionalHostTriple)
  else
    HostArch   = getparam("ARCH")
    HostOs     = getparam("OS")
    HostTriple = format("%s-%s-gnu", HostArch, HostOs)
  end
  -- Select profile
  local Profile = MAKE_HostProfiles[HostOs]
  assert(Profile, format("unsupported host os: %s", HostOs))
  -- Create the new context
  local NewContext = {
    FileCache    = {},
    OS           = HostOs,
    Separator    = Profile.Separator,
    Triple       = HostTriple,
    CommandText  = Profile.Commands,
    PathRenderer = Profile.PathRenderer,
  }
  -- Return value
  return NewContext
end

local function MAKE_NewBuild (RootFilename, OptionalHostTriple)
  -- Create new objects
  local NewContext  = MAKE_NewContext(OptionalHostTriple)
  local Description = MAKE_LoadFile(NewContext, RootFilename)
  -- Validate
  MAKE_ValidateRootDescription(Description, RootFilename)
  -- Create the model from description files
  local Triples  = MAKE_NormalizeTriples(NewContext, Description)
  local NewModel = MAKE_BuildModel(NewContext, RootFilename, Description, Triples)
  -- Return value
  return NewModel
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  Build = MAKE_NewBuild,
}

return PUBLIC_API
