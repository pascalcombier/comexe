--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- This file is a simple program implementing the same commands as lua54.exe
-- command line interface. It is based on lua.c
-- 
-- For compatibility tests, to check if there is any major difference between
-- standard PUC Lua 54 and ComEXE, we have tests\basics\test-arg.lua
--
-- This also implement ExtendedCommands.

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime     = require("com.runtime")
local TrivialRepl = require("trivial-repl")
local Commands    = require("extended-commands")

local insert    = table.insert
local format    = string.format
local stderr    = io.stderr
local getenv    = os.getenv

local getparam  = Runtime.getparam
local slice     = Runtime.slice
local hasprefix = Runtime.hasprefix
local readfile  = Runtime.readfile

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local VERSION_BANNER = format([[Lua %s  Copyright (C) 1994-2025 Lua.org, PUC-Rio, ComEXE %s %s]],
  Runtime.LUA_VERSION,
  Runtime.COMEXE_VERSION,
  Runtime.COMEXE_BUILD_DATE)

-- Favor objects on the file system first
-- Default: FileSystem, ZIP-RUNTIME, LUA-PRELOAD, Lua
--          F               R        1            234
local DEFAULT_COMEXE_LOADER = "FR1234"

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function FatalError (...)
  local String = format(...)
  stderr:write(String)
  stderr:write("\n")
  os.exit(1)
end

local MAIN_WarningState = "@off"

local function PrintWarning (WarningString, Continue)
  -- Filter out control messages
  if (hasprefix(WarningString, "@")) then
    MAIN_WarningState = WarningString
  else
    -- Print warning if needed
    if (MAIN_WarningState == "@on") then
      if Continue then
        stderr:write(WarningString)
        stderr:flush()
      else
        stderr:write(format("Lua warning: %s\n", WarningString))
      end
    end
  end
end

local function PrintUsage ()
  stderr:write("usage: lua55ce [options] [script [args]]\n")
  stderr:write("Available options are:\n")
  stderr:write("  -e stat   execute string 'stat'\n")
  stderr:write("  -i        enter interactive mode after executing 'script'\n")
  stderr:write("  -l mod    require library 'mod' into global 'mod'\n")
  stderr:write("  -l g=mod  require library 'mod' into global 'g'\n")
  stderr:write("  -v        show version information\n")
  stderr:write("  -E        ignore environment variables\n")
  stderr:write("  -W        turn warnings on\n")
  stderr:write("  --        stop handling options\n")
  stderr:write("  -         stop handling options and execute stdin\n")
  stderr:write("  -x        Enable ComEXE extended commands\n")
end

local function PrintVersionBanner ()
  print(VERSION_BANNER)
end

local function TryChunk (Chunk, LoadChunkErrorString)
  if Chunk then
    local Success, ErrorMessage = xpcall(Chunk, debug.traceback, nil, nil, 1)
    if not Success then
      FatalError(ErrorMessage)
    end
  else
    FatalError(LoadChunkErrorString)
  end
end

-- Note: initial implementation was trivial:
--   Load the script with the global environment
--   local Chunk, ErrorString = loadfile(LuaScriptFilename)
--   TryChunk(Chunk, ErrorString)
--
-- It was very close to the initial implementation in lua.c, but the underlying
-- C implementation being basically a fopen, it was not working properly with
-- UTF-8 filenames. For that reason, we use an UTF-8 friendly way to load file.
--
local function LoadFile (LuaScriptFilename, Arguments)
  -- Load chunk
  local ChunkName   = format("@%s", LuaScriptFilename)
  local ChunkString = readfile(LuaScriptFilename, "string")
  if ChunkString then
    local Chunk, ErrorString = load(ChunkString, ChunkName)
    TryChunk(Chunk, ErrorString)
  else
    -- Reproduce the behavior of lua54.exe
    -- > ..\bin\lua54.exe asdfasdf
    -- ..\bin\lua54.exe: cannot open asdfasdf: No such file or directory
    local Exe         = getparam("LUA-EXE")
    local ErrorString = format("%s: cannot open %s: No such file or directory\n", Exe, LuaScriptFilename)
    stderr:write(ErrorString)
    os.exit(1)
  end
end

local function ExecuteString (CodeString, ChunkName)
  local Chunk, ErrorMessage = load(CodeString, ChunkName)
  TryChunk(Chunk, ErrorMessage)
end

local function ExecuteStdin ()
  -- Same as lua.c
  -- dofile(L, NULL); /* executes stdin as a file */
  dofile()
end

local function LUA_CheckEnvironment ()
  -- Search for environment variable
  local Variable = getenv("LUA_INIT_5_4") or getenv("LUA_INIT")
  -- If the environment variable starts with @ it means @filename
  -- else it's a string
  if Variable then
    if (hasprefix(Variable, "@")) then
      local Filename   = Variable:sub(2)
      local Parameters = { Filename }
      LoadFile(Filename, Parameters)
    else
      local LuaString = Variable
      ExecuteString(LuaString, "LUA_INIT")
    end
  end
end

local function LUA_StartRepl ()
  TrivialRepl.Run()
end

local function RequireLibrary (ModuleName, GlobalName)
  local Success, Module = pcall(require, ModuleName)
  if Success then
    if GlobalName then
      _G[GlobalName] = Module
    else
      _G[ModuleName] = Module
    end
  else
    -- Exit with error code 1 to match original lua54.exe behavior
    FatalError("error: %s\n%s", Module, debug.traceback())
  end
end

--------------------------------------------------------------------------------
-- COMMAND LINE ANALYSIS                                                      --
--------------------------------------------------------------------------------

local function MAIN_ProcessOption (Environment, Option, Value)
  if (Option == "-v") then
    Environment.ShowVersion = true
  elseif (Option == "-e") then
    insert(Environment.ExecuteStatements, Value)
  elseif (Option == "-l") then
    local GlobalName, ModuleName = Value:match("^([^=]+)=(.+)$")
    if not ModuleName then
      ModuleName = Value
      GlobalName = nil
    end
    insert(Environment.RequireStatements, {ModuleName, GlobalName})
  elseif (Option == "-W") then
    Environment.EnableWarnings = true
  elseif (Option == "-x") then
    Environment.Extended = true
  elseif (Option == "-i") then
    Environment.IsInteractive = true
  elseif (Option == "-E") then
    debug.getregistry()["LUA_NOENV"] = true
    Environment.IgnoreEnvironment = true
  elseif (Option == "-") then
    Environment.IsExecuteStdin = true
  end
end

-- NOTE:
-- The Lua interpreter is designed to suppress the REPL if -v (version) or -e
-- (execute string) are present, unless -i (interactive) is also specified. The
-- -l (load library) option does not suppress the REPL.

local function MAIN_RunProgram (Environment, Script, Arguments)
  local StdinIsTty = Runtime.isatty(Runtime.stdin)
  local HasE       = (#Environment.ExecuteStatements > 0)
  local HasL       = (#Environment.RequireStatements > 0)
  -- Initialize the ComEXE runtime
  Runtime.setwarningfunction(PrintWarning)
  Runtime.setsearcher(DEFAULT_COMEXE_LOADER)
  -- Handle ignore environment
  if Environment.IgnoreEnvironment then
    debug.getregistry()["LUA_NOENV"] = true
  else
    LUA_CheckEnvironment()
  end
  -- Print version banner -v
  if Environment.ShowVersion then
    PrintVersionBanner()
  end
  -- Enable warnings if requested
  if Environment.EnableWarnings then
    warn("@on")
  end
  -- Run -e and -l options
  for Index, Library in ipairs(Environment.RequireStatements) do
    local ModuleName = Library[1]
    local GlobalName = Library[2]
    RequireLibrary(ModuleName, GlobalName)
  end
  for Index, Statement in ipairs(Environment.ExecuteStatements) do
    ExecuteString(Statement, "command line")
  end
  -- Execute script file if present
  if Script then
    LoadFile(Script, Arguments)
    if Environment.IsInteractive then
      LUA_StartRepl()
    end
  -- Handle interactive mode or stdin execution (mimicking C behavior)
  elseif Environment.IsExecuteStdin then
    ExecuteStdin()
  elseif Environment.IsInteractive then
    LUA_StartRepl()
  elseif (not Script) and not (HasE or Environment.ShowVersion or Environment.IsInteractive) then
    -- Match the code in lua.c
    -- else if (script < 1 && !(args & (has_e | has_v))) 
    if StdinIsTty then
      PrintVersionBanner()
      LUA_StartRepl()
    else
      PrintVersionBanner()
      ExecuteStdin()
    end
  end
end

local INIT_ParserEatRules = {
  ["-e"] =  2,
  ["-i"] =  1,
  ["-l"] =  2,
  ["-v"] =  1,
  ["-E"] =  1,
  ["-W"] =  1,
  ["--"] = -1,
  ["-"]  = -1,
  ["-x"] =  2 -- Extended Commands
}

local function HandleCommandLine ()
  -- Always retrieve RAW arguments first
  local RawArgs = getparam("ARG-RAW")
  -- Parse options for the second time with new EatRules
  local Success, ErrorOption, NewOptions, ScriptIndex, OptionValues = Runtime.parseoptions(RawArgs, INIT_ParserEatRules)
  if not Success then
    stderr:write(format("lua55ce: unrecognized option '%s'\n", ErrorOption))
    PrintUsage()
    os.exit(1)
  end
  -- Check for extended command
  if (RawArgs[2] == "-x") then
    local Arguments = slice(RawArgs, 3, #RawArgs)
    -- Try the command
    local Success, ErrorMessage = pcall(Commands.Command, Arguments)
    if Success then
      os.exit(0)
    else
      print(format("ERROR: %s", ErrorMessage))
      os.exit(1)
    end
  end
  -- Handle options
  local NewEnvironment = {
    ExecuteStatements = {},
    RequireStatements = {},
    EnableWarnings    = false
  }
  if OptionValues then
    local Index    = 1
    while (Index <= #OptionValues) do
      local OptionEntry = OptionValues[Index]
      local OptionName  = OptionEntry[1]
      local OptionValue = OptionEntry[2]
      MAIN_ProcessOption(NewEnvironment, OptionName, OptionValue)
      Index = (Index + 1)
    end
  end
  -- Handle standard Lua commands
  local Script
  local Args
  if ScriptIndex and RawArgs[ScriptIndex] then
    Script = RawArgs[ScriptIndex]
    Args   = slice(RawArgs, (ScriptIndex + 1), #RawArgs)
  else
    Args = {}
  end
  -- Run program
  MAIN_RunProgram(NewEnvironment, Script, Args)
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

HandleCommandLine()
