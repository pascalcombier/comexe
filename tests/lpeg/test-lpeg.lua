--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local lpeg = require("lpeg")

local P = lpeg.P -- literal string
local R = lpeg.R -- range
local S = lpeg.S -- set

--------------------------------------------------------------------------------
-- VERY BASIC LPEG TEST                                                       --
--------------------------------------------------------------------------------

-- Integer
local Digit        = R("09")
local Integer      = Digit^1 -- 1+ repetition
local EndPosition1 = Integer:match("42")
assert((EndPosition1 == 3))

-- String literal
local Hello        = P("hello")
local EndPosition2 = Hello:match("hello world")
assert((EndPosition2 == 6))

-- Character set
local Set          = S("aeiou")
local EndPosition3 = Set:match("example")
assert((EndPosition3 == 2))

--------------------------------------------------------------------------------
-- VERY BASIC LPEG "RE" TEST                                                  --
--------------------------------------------------------------------------------

-- REGEX Regular Expressions

local re           = require("re")
local EndPosition4 = re.match("42", "%d+")
assert((EndPosition4 == 3))
