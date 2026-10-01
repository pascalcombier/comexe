--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local FileOps = require("buildtool-file-ops")
local Pack    = require("buildtool-pack")

local format = string.format
local remove = table.remove
local stdout = io.stdout
local stderr = io.stderr
local exit   = os.exit

--------------------------------------------------------------------------------
-- CONSTANTS                                                                  --
--------------------------------------------------------------------------------

local EXIT_SUCCESS = 0
local EXIT_ERROR   = 1

local COMMAND_LIST = {
  concat   = FileOps.Concat,
  dos2unix = FileOps.ToUnix,
  unix2dos = FileOps.ToDos,
  pack     = Pack.Run,
}

local BUILDTOOL_USAGE = [[buildtool: build-time helper for ComEXE

USAGE: buildtool <command> [arguments]

commands:
  concat   <input> [input...] <output>          concatenate files
  dos2unix <file> [file...]                     convert CRLF to LF
  unix2dos <file> [file...]                     convert LF to CRLF
  pack     <manifest.lua> <output.zip> [level]  create a zip file
  help                                          print usage
]]

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local Arguments   = { ... }
local CommandName = remove(Arguments, 1)

if (CommandName == nil) or (CommandName == "help") or (CommandName == "--help") then
  stdout:write(BUILDTOOL_USAGE)
  exit(EXIT_SUCCESS)
end

local CommandFunction = COMMAND_LIST[CommandName]
if (CommandFunction == nil) then
  local ErrorString = format("buildtool: unknown command '%s'\n", CommandName)
  stderr:write(ErrorString)
  stderr:write(BUILDTOOL_USAGE)
  exit(EXIT_ERROR)
end

local Success, CommandResult = pcall(CommandFunction, Arguments)
if (not Success) then
  local ErrorString = format("buildtool %s: %s\n", CommandName, CommandResult)
  stderr:write(ErrorString)
  exit(EXIT_ERROR)
end

exit(CommandResult)
