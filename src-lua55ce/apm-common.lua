--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")

local concat     = table.concat
local max        = math.max
local append     = Runtime.append
local stringtrim = Runtime.stringtrim

local LUA_VERSION = _VERSION:match("Lua%s+([%d%.]+)")

-- Those packages are shipped with lua55ce
-- TODO: what about luasec?
local APM_LOCAL_PACKAGES = {
  -- c packages
  comexe = "0.0.1",
  luv    = "1.51.0",
  -- lua packages
  binaryheap = "0.4",
  copas      = "1.37",
  coxpcall   = "1.13",
  fennel     = "1.6.1",
  ltn12      = "1.0.3",
  socket     = "3.1.0", -- TODO socket or luasocket???
  luasocket  = "3.1.0", -- canny-redis use luasocket
  timerwheel = "1.0.2",
  lua        = LUA_VERSION
}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function PARSER_MethodPeek (Parser)
  -- Retrieve data
  local String      = Parser.String
  local Index       = Parser.Index
  local CurrentChar = String:sub(Index, Index)
  -- Return value
  local ReturnValue
  if (#CurrentChar > 0) then
    ReturnValue = CurrentChar
  end
  return ReturnValue
end

local function PARSER_MethodMove (Parser)
  Parser.Index = (Parser.Index + 1)
end

function PARSER_MethodConsume (Parser)
  -- Retrieve data
  local CurrentChar = PARSER_MethodPeek(Parser)
  -- If not EOF append to buffer for later flush
  if CurrentChar then
    local Buffer = Parser.Buffer
    append(Buffer, CurrentChar)
    PARSER_MethodMove(Parser)
  end
end

local function PARSER_MethodFlush (Parser, Options)
  -- Retrieve data
  local Buffer = Parser.Buffer
  -- Flush the buffer
  local String = concat(Buffer)
  Parser.Buffer = {}
  -- Check options
  if (Options == "TRIM") then
    String = stringtrim(String)
  end
  -- Return the flushed string
  return String
end

local function APM_TrivialLexer (String)
  local NewLexer = {
    -- local data
    String = String,
    Index  = 1,
    Buffer = {},
    -- Method
    peek    = PARSER_MethodPeek,
    move    = PARSER_MethodMove,
    consume = PARSER_MethodConsume,
    flush   = PARSER_MethodFlush,
  }
  return NewLexer
end

--------------------------------------------------------------------------------
-- DEPENDENCY PARSER                                                          --
--------------------------------------------------------------------------------

local PARSER_Whitespace = {
  [" "]  = true,
  ["\t"] = true,
  ["\n"] = true,
  ["\r"] = true
}

local PARSER_Operator = {
  [">"] = true,
  ["<"] = true,
  ["="] = true,
  ["~"] = true,
  ["!"] = true
}

-- Examples of valid inputs:
-- "lua >= 5.1"
-- "luasocket"
-- "luasec >= 0.7"
-- "lua >= 5.1, < 5.5",
-- "luafilesystem >= 1.6.0, <= 1.7.0",
-- "inspect >= 3.1.1"
-- Example of invalid inputs:
-- "lua, inspect"
local function APM_ParseDependencyString (DependencyString)
  -- Lexer
  local Lexer        = APM_TrivialLexer(DependencyString)
  local CurrentChar  = Lexer:peek()
  local Dependencies = {}
  -- local data
  local CurrentName     = ""
  local CurrentOperator = ""
  local CurrentVersion  = ""
  local State           = "PARSE_NAME"
  -- Main iteration loop
  while (State ~= "ERROR") and CurrentChar do
    if PARSER_Whitespace[CurrentChar] then
      Lexer:move()
    elseif (State == "PARSE_NAME") then
      if (CurrentChar == ",") then
        State = "ERROR"
      elseif PARSER_Operator[CurrentChar] then
        CurrentName = Lexer:flush("TRIM")
        State = "PARSE_OPERATOR"
        Lexer:consume() -- Initiate OPERATOR
      else
        Lexer:consume() -- Produce NAME
      end
    elseif (State == "PARSE_OPERATOR") then
      if (CurrentChar == ",") then
        State = "ERROR"
      elseif PARSER_Operator[CurrentChar] then
        Lexer:consume() -- Produce OPERATOR
      else
        CurrentOperator = Lexer:flush("TRIM")
        State = "PARSE_VERSION"
      end
    elseif (State == "PARSE_VERSION") then
      if (CurrentChar == ",") then
        CurrentVersion = Lexer:flush("TRIM")
        local NewDependancy = {
          CurrentName,
          CurrentOperator,
          CurrentVersion
        }
        append(Dependencies, NewDependancy)
        CurrentOperator = ""
        Lexer:move() -- skip the comma
        State = "PARSE_OPERATOR" -- Next operator
      else
        Lexer:consume() -- Produce VERSION
      end
    end
    CurrentChar = Lexer:peek()
  end
  -- Final state
  if (State == "PARSE_NAME") then
    CurrentName = Lexer:flush("TRIM")
    if (CurrentName == "") then
      State = "ERROR"
    else
      local NewDependancy = { CurrentName }
      append(Dependencies, NewDependancy)
    end
  elseif (State == "PARSE_VERSION") then
    CurrentVersion = Lexer:flush("TRIM")
    local NewDependancy = {
      CurrentName,
      CurrentOperator,
      CurrentVersion
    }
    append(Dependencies, NewDependancy)
  elseif (State == "PARSE_OPERATOR") then
    State = "ERROR"
  end
  -- Evaluate result
  local ResultValue
  if (State ~= "ERROR") and (#Dependencies > 0) then
    ResultValue = Dependencies
  end
  return ResultValue
end

--------------------------------------------------------------------------------
-- AWESOME PACKAGE MANAGER: DEPENDENCIES                                      --
--------------------------------------------------------------------------------

-- Split name and version
-- Examples:
-- f-strings-0.1
-- f.lua-1.0
-- 30log-0.8.0
-- ac-clientoutput-1.1.1
-- abacatepaysdk-1.0
-- abstk-release-1
-- access-token-introspection-1.0.0
-- uint-0.186
local function APM_SplitNameVersion (NameVersion)
  local Name
  local Version
  local DashIndex = NameVersion:match("()%-[^%-]*$")
  if DashIndex then
    -- name is everything before the dash
    -- version everything after the dash
    Name    = NameVersion:sub(1, (DashIndex - 1))
    Version = NameVersion:sub(DashIndex + 1)
  end
  return Name, Version
end

-- Here VersionString can be nil
-- In the case of simple dependencies like "socket" without version
local function APM_SplitVersionToParts (VersionString)
  local PartList = {}
  if VersionString then
    for Part in VersionString:gmatch("([^%.]+)") do
      local PartNumber = (tonumber(Part) or 0)
      append(PartList, PartNumber)
    end
  end
  return PartList
end

-- Note that "1.2" would be equals to "1.2.0"
-- If VersionB is nil then PartsB will be {} and interpreted as "0.0.0"
local function APM_CompareVersionsSimple (VersionA, Operator, VersionB)
  -- Split versions
  local PartsA = APM_SplitVersionToParts(VersionA)
  local PartsB = APM_SplitVersionToParts(VersionB)
  -- Evaluate
  local MaxLen          = max(#PartsA, #PartsB)
  local ComparisonValue = 0
  local Continue        = true
  local Index           = 1
  -- Iterate and compare, stop at the first difference
  while Continue and (Index <= MaxLen) do
    local PartA = (PartsA[Index] or 0)
    local PartB = (PartsB[Index] or 0)
    if (PartA > PartB) then
      ComparisonValue = 1
      Continue        = false
    elseif (PartA < PartB) then
      ComparisonValue = -1
      Continue        = false
    else
      -- The parts are equal, check the next one
      Index = (Index + 1)
    end
  end
  -- Evaluate result
  local Result
  if (Operator == "==") then
    Result = (ComparisonValue == 0)
  elseif (Operator == "~=") or (Operator == "!=") then
    Result = (ComparisonValue ~= 0)
  elseif (Operator == ">=") then
    Result = (ComparisonValue >= 0)
  elseif (Operator == "<=") then
    Result = (ComparisonValue <= 0)
  elseif (Operator == ">") then
    Result = (ComparisonValue > 0)
  elseif (Operator == "<") then
    Result = (ComparisonValue < 0)
  elseif (Operator == nil) then
    Result = true
  end
  -- Return value
  return Result
end

-- Tricky "Pessimistic comparison" ~>
-- Examples:
-- ~> 1.2.3 means >= 1.2.3 and < 1.3
-- ~> 1.2   means >= 1.2 and < 2
-- ~> 1     means >= 1 and < 2
local function APM_CompareVersionsPessimistic (VersionA, VersionB)
  local Result
  -- check if A >= B, early fail otherwise
  if APM_CompareVersionsSimple(VersionA, ">=", VersionB) then
    -- compute upper bound from VersionB
    local Parts = APM_SplitVersionToParts(VersionB)
    local Upper = {}
    local Count = #Parts
    if (Count > 2) then
      -- Copy until the "avant-dernier"
      for Index = 1, (Count - 2) do
        append(Upper, Parts[Index])
      end
      -- Copy the Version+1 "avant-dernier"
      append(Upper, (Parts[Count - 1]) + 1)
    elseif (Count == 2) then
      append(Upper, Parts[1])
      append(Upper, (Parts[2] + 1))
    else
      append(Upper, (Parts[1] + 1))
    end
    local UpperVersionString = concat(Upper, ".")
    -- final check: versionA < upper bound
    Result = APM_CompareVersionsSimple(VersionA, "<", UpperVersionString)
  else
    Result = false
  end
  return Result
end

local function APM_CompareVersions (VersionA, Operator, VersionB)
  local Result
  if (Operator == "~>") then
    Result = APM_CompareVersionsPessimistic(VersionA, VersionB)
  else
    Result = APM_CompareVersionsSimple(VersionA, Operator, VersionB)
  end
  return Result
end


--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  -- data
  localpackages = APM_LOCAL_PACKAGES,
  -- functions
  splitnameversion      = APM_SplitNameVersion,
  parsedependencystring = APM_ParseDependencyString,
  compareversions       = APM_CompareVersions
}

return PUBLIC_API
