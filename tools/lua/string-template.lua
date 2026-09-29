--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- string-template.lua string template and expansions
--
-- Types of expansions
--
--       simple variables: $IN $TEST $VAR1
-- functions & parameters: rm -f %1 %3+ with %3+ meaning all the parameters after 3
--       native pathnames: $P/tmp/test or $P{/tmp space}
--
-- Examples of use
--
-- local Template       = "$OUT was built from $IN"
-- local Environment    = { IN = "src/a.c", OUT = "bin/a.o" }
-- local Commands       = {}
-- local RenderPath     = nil
-- local StringTemplate = newstringtemplate(Template)
-- StringTemplate:render(Environment, Commands, RenderPath)
-- return "bin/a.o was built from src/a.c"
--
-- local Template       = "kept $MISSING"
-- local Environment    = {}
-- local Commands       = {}
-- local RenderPath     = nil
-- local StringTemplate = newstringtemplate(Template)
-- StringTemplate:render(Environment, Commands, RenderPath)
-- return "kept $MISSING"
--
-- local Template       = "$COPY $IN $OUT"
-- local Environment    = { IN = "a.c", OUT = "o" }
-- local Commands       = { COPY = "copy /Y %1 %2 1>NUL" }
-- local RenderPath     = nil
-- local StringTemplate = newstringtemplate(Template)
-- StringTemplate:render(Environment, Commands, RenderPath)
-- return "copy /Y a.c o 1>NUL"
--
-- local Template       = "$RMFILES bin/o a.o b.o"
-- local Environment    = {}
-- local Commands       = { RMFILES = "if exist %1 del /F /Q %2+ 2>NUL" }
-- local RenderPath     = nil
-- local StringTemplate = newstringtemplate(Template)
-- StringTemplate:render(Environment, Commands, RenderPath)
-- return "if exist bin/o del /F /Q a.o b.o 2>NUL"
--
-- local gsub           = string.gsub
-- local Template       = "zig cc -c $IN -o $OUT -I$Pbin/$TRIPLE/lua"
-- local Environment    = { IN = "src/a.c", OUT = "bin/a.o", TRIPLE = "x86_64-win" }
-- local Commands       = {}
-- local NativePath     = function (Pathname) return (gsub(Pathname, "/", "\\")) end
-- local StringTemplate = newstringtemplate(Template)
-- StringTemplate:render(Environment, Commands, RenderPath)
-- return "zig cc -c src/a.c -o bin/a.o -Ibin\x86_64-win\lua"
--
-- local Template       = "$P{dist/a b.txt}"
-- local Environment    = {}
-- local Commands       = {}
-- local NativePath     = function (Pathname) return (gsub(Pathname, "/", "\\")) end
-- local StringTemplate = newstringtemplate(Template)
-- StringTemplate:render(Environment, Commands, RenderPath)
-- return "dist\a b.txt"
--
-- local Template       = "$COPY a b"
-- local Environment    = {}
-- local Commands       = nil
-- local NativePath     = function (Pathname) return (gsub(Pathname, "/", "\\")) end
-- local StringTemplate = newstringtemplate(Template)
-- StringTemplate:render(Environment, Commands, RenderPath)
-- return "$COPY a b"

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local gsub   = string.gsub
local concat = table.concat
local append = table.insert
local format = string.format

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local EMPTY_TABLE = {}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

-- Represent a $VARIABLE to expand in a template string like "$VAR1 $VAR2"
-- %u is upper-case letter
-- %d is digit
--
-- Same pattern for $VARIABLES or $COMMANDS
local TOKEN_PATTERN       = "%$(%u[%u%d_]*)"
local TOKEN_PATTERN_START = format("^%s", TOKEN_PATTERN)

-- If not found in the Environment, this function will NOT resolve the variable
-- name and unknown "$VAR1" will return "$VAR1" (unresolved)
local function ResolveVariable (Name, Environment)
  local Value = Environment[Name]
  if (Value == nil) then
    Value = format("$%s", Name)
  end
  return Value
end

-- This function is called by TEMPLATE_MethodRender and used to expand variables
-- in a "PATH" or "PATHBRACE" ($P/usr/lib/$MYVAR/test)
--
-- Expand a $VARIABLE in a template string
-- "$VAR1 $VAR2" with environment { "VAR1" = "test1", "VAR2" = "test2" }
-- Will be expanded to "test1 test2"
local function ExpandVariables (Value, Environment)
  -- We use a replace function for gsub, if the $VAR is not part of the
  -- environment, then it will remain unexpanded
  -- Example: "$VAR1 $VAR2" with { "VAR1" = "test" } will resolve to "test $VAR2"
  -- Note that "Name" is the capture from TOKEN_PATTERN
  local function ExpandName (Name)
    return ResolveVariable(Name, Environment)
  end
  -- Perform the variable expansion. The FUNCTION form is required, not a
  -- preference: gsub's table form cannot keep an absent name literal, it leaves
  -- the text untouched by accident, which is not the documented behaviour.
  local ExpandedString = gsub(Value, TOKEN_PATTERN, ExpandName)
  return ExpandedString
end

-- This function is called by ExpandCommands below, it resolve the parameters %1
-- %2 %3 and even lists like %3+ (from argument 3 to the end)
--
-- Parameters not found in Arguments will be resolved as empty string ""
local function ExpandSlots (Text, Arguments)
  -- We use a replace function for gsub
  -- Note that the parameters Index and Plus are the Lua pattern captures
  local function ExpandSlotValue (Index, Plus)
    local Position = tonumber(Index)
    local ExpandedValue
    if (Plus == "+") then
      -- %3+ will return all the parameters after 3
      ExpandedValue = concat(Arguments, " ", Position, #Arguments)
    else
      -- Missing variables will be deleted (expanded to "")
      ExpandedValue = (Arguments[Position] or "")
    end
    return ExpandedValue
  end
  -- Perform the slot expansion
  local ExpandedString = gsub(Text, "%%(%d+)(%+?)", ExpandSlotValue)
  return ExpandedString
end

-- This expansion is done at last, after normal $VARIABLE expansions
-- So Value looks like "$COPY src/a.c src/b.c bin/app.exe"
local function ExpandCommands (Value, Commands)
  local Parts     = {}
  local Position  = 1
  local Expanding = true
  while Expanding do
    -- Search for a token like "$COPY"
    local StartPos, EndPos, Name = Value:find(TOKEN_PATTERN, Position)
    if (not StartPos) then
      local Tail = Value:sub(Position)
      append(Parts, Tail)
      Expanding = false
    else
      local Template = Commands[Name]
      -- Template contains the expanded command with %1 %2 %3 args
      if (Template) then
        -- Collect the arguments values
        local Arguments = {}
        local Scan      = (EndPos + 1) -- Immediatly after "$COPY"
        local Scanning  = true
        while Scanning do
          -- In Lua patterns, "%S" is the negation of "%s", it represent a non-space
          -- Arg will be essentially "next word" after "$COPY"
          local ArgFrom, ArgTo = Value:find("%S+", Scan)
          -- Here, we have special cases:
          --
          -- We might have a previous $VARIABLE which was NOT expanded, so we
          -- stop early the expansion
          -- We might have a second $COMMAND
          --
          -- IsClassicWord is a word not prefixed by "$"
          local IsClassicWord = (ArgFrom and (Value:sub(ArgFrom, ArgFrom) ~= "$"))
          if IsClassicWord then
            local ClassicWord = Value:sub(ArgFrom, ArgTo)
            append(Arguments, ClassicWord)
            Scan = (ArgTo + 1)
          else
            Scanning = false
          end
        end
        -- Scanning is done, we have all the arguments values
        local ExpandedSlots = ExpandSlots(Template, Arguments)
        append(Parts, ExpandedSlots)
        Position = Scan
      else
        -- Just copy without expansion
        local UnexpandedPart = Value:sub(Position, EndPos)
        append(Parts, UnexpandedPart)
        Position = (EndPos + 1)
      end
    end
  end
  return concat(Parts)
end

--------------------------------------------------------------------------------
-- TOKENIZER                                                                  --
--------------------------------------------------------------------------------

-- Tokens
--   { "VERBATIM",  text     }
--   { "VAR",       name     }
--   { "PATH",      pathname }  $Ppathname
--   { "PATHBRACE", pathname }  $P{path}
local function Compile (Source)
  local Tokens   = {}
  local Position = 1
  local Length   = #Source
  local Continue = true
  while Continue do
    local StartPos = Source:find("$", Position, true)
    if (not StartPos) then
      local VerbatimTail = Source:sub(Position)
      append(Tokens, { "VERBATIM", VerbatimTail })
      Continue = false
    else
      if (StartPos > Position) then
        -- We found a new $TOKEN after, so we copy the VERBATIM text in the
        -- middle
        local VerbatimText = Source:sub(Position, (StartPos - 1))
        append(Tokens, { "VERBATIM", VerbatimText })
      end
      -- Deal with $P{/path space} first
      -- Marker1: "$" or nil
      -- Marker2: "P" or something else
      local Marker1 = Source:sub((StartPos + 1), (StartPos + 1))
      local Marker2 = Source:sub((StartPos + 2), (StartPos + 2))
      if (Marker1 == "P") and (Marker2 == "{") then
        local ClosePos = Source:find("}", (StartPos + 3), true)
        assert(ClosePos, format("unclosed $P{: %s", Source))
        local PathValue = Source:sub((StartPos + 3), (ClosePos - 1))
        append(Tokens, { "PATHBRACE", PathValue })
        Position = (ClosePos + 1)
      else
        -- Here we have a $VAR which is not a "$P" pathname
        -- Or a "$P" without braces "{"
        local NameStart, NameEnd, Name = Source:find(TOKEN_PATTERN_START, StartPos)
        -- Handle $P
        -- %u is upper-case letter
        -- %d is digit
        local IsPathname = ((Name == "P") and (Source:find("^[%u%d_]", (StartPos + 2)) == nil))
        if (IsPathname) then
          local NextSpacePos = Source:find("%s", (StartPos + 2))
          local WordEnd      = (NextSpacePos or (Length + 1))
          local PathValue    = Source:sub((StartPos + 2), (WordEnd - 1))
          assert((PathValue ~= ""), format("$P needs a path in recipe: %s", Source))
          append(Tokens, { "PATH", PathValue })
          Position = WordEnd
        elseif (Name) then
          -- Simple variable name
          append(Tokens, { "VAR", Name })
          Position = (NameEnd + 1)
        else
          append(Tokens, { "VERBATIM", "$" })
          Position = (StartPos + 1)
        end
      end
    end
  end
  return Tokens
end

--------------------------------------------------------------------------------
-- STRING TEMPLATE API                                                        --
--------------------------------------------------------------------------------

local function Identity (Value)
  return Value
end

local function TEMPLATE_MethodRender (Template, OptionalEnvironment, OptionalCommands, OptionalRenderPathFunction)
  -- Handle defaults
  local Environment        = (OptionalEnvironment or EMPTY_TABLE)
  local Commands           = (OptionalCommands    or EMPTY_TABLE)
  local RenderPathFunction = (OptionalRenderPathFunction or Identity)
  -- Render the template
  local Tokens = Template.Tokens
  local Parts  = {}
  for Index = 1, #Tokens do
    local Token      = Tokens[Index]
    local TokenType  = Token[1]
    local TokenValue = Token[2]
    if (TokenType == "VERBATIM") then
      append(Parts, TokenValue)
    elseif (TokenType == "VAR") then
      local ResolvedVariable = ResolveVariable(TokenValue, Environment)
      append(Parts, ResolvedVariable)
    elseif (TokenType == "PATH") or (TokenType == "PATHBRACE") then
      -- $P or $P{} tokens are text with potential multiple $VARIABLE inside
      local ExpandedVariables = ExpandVariables(TokenValue, Environment)
      local NativePathString  = RenderPathFunction(ExpandedVariables)
      append(Parts, NativePathString)
    else
      error(format("unknown token type in template: %s", TokenType))
    end
  end
  -- Perform the final expansion
  local ExpandedString   = concat(Parts)
  local ExpandedCommands = ExpandCommands(ExpandedString, Commands)
  return ExpandedCommands
end

local TEMPLATE_Metatable = {
  -- METATABLE_UserDefinedMethods
  __index = {
    render = TEMPLATE_MethodRender,
  },
}

local function newstringtemplate (Source)
  -- Validate inputs
  assert((type(Source) == "string"), format("newstringtemplate expects a string, got %s", type(Source)))
  -- Create the new object
  local NewObject = {
    Tokens = Compile(Source),
  }
  -- Attach metatable
  setmetatable(NewObject, TEMPLATE_Metatable)
  -- Return value
  return NewObject
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  newstringtemplate = newstringtemplate
}

return PUBLIC_API
