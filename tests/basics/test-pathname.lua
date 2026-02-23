--------------------------------------------------------------------------------
-- TESTS BOILERPLATE FOR PACKAGE.PATH                                         --
--------------------------------------------------------------------------------

-- This kind of code should not appear in the real use of ComEXE
--
-- Initialize package.path to include ..\lib\xxx because test libraries are in
-- this directory

local function TEST_UpdatePackagePath (RelativeDirectory)
  -- Retrieve package confiuration (file loadlib.c, function luaopen_package)
  local Configuration = package.config
  local LUA_DIRSEP    = Configuration:sub(1, 1)
  local LUA_PATH_SEP  = Configuration:sub(3, 3)
  local LUA_PATH_MARK = Configuration:sub(5, 5)
  -- Load required modules
  local Runtime   = require("com.runtime")
  local Directory = Runtime.getrelativepath(RelativeDirectory) -- relative to arg[0] directory
  -- Prepend path in a Linux/Windows compatible way
  package.path = string.format("%s%s%s.lua%s%s", Directory, LUA_DIRSEP, LUA_PATH_MARK, LUA_PATH_SEP, package.path)
end

TEST_UpdatePackagePath("../lib")

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime  = require("com.runtime")
local reporter = require("mini-reporter")

local newpathname = Runtime.newpathname

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local Reporter = reporter.new()

local function nativepathname (Pathname)
  local NativeDirectorySeparator = package.config:sub(1, 1)
  return Pathname:gsub("/", NativeDirectorySeparator)
end

local function EXPECT (TestCase, ResultValue, ExpectedValue)
  local Success = (ResultValue == ExpectedValue)
  if (not Success) then
    Reporter:writef("TEST %s FAIL", TestCase)
    Reporter:writef("  GOT    [%s]", tostring(ResultValue))
    Reporter:writef("  EXPECT [%s]", tostring(ExpectedValue))
  end
  Reporter:expect(TestCase, Success)
end

--------------------------------------------------------------------------------
-- NOMINAL                                                                    --
--------------------------------------------------------------------------------

Reporter:block("NOMINAL")

local Pathname
local ExpectedDir
local GotDirectory
local Name, Basename, Ext
local InternalPathname
local NativePathname
local Depth, IsAbsolute, IsRelative
local Cloned

Pathname            = newpathname("C:/path/to/file.txt")
GotDirectory        = Pathname:getdirectory()
Name, Basename, Ext = Pathname:getname()

EXPECT("NOM-001-name",      Name,     "file.txt")
EXPECT("NOM-002-basename",  Basename, "file")
EXPECT("NOM-003-extension", Ext,      "txt")
EXPECT("NOM-004-directory", GotDirectory, nativepathname("C:/path/to"))

Pathname            = newpathname("a/b/../c.txt")
InternalPathname    = Pathname:convert("internal")
NativePathname      = Pathname:convert("native")
Name, Basename, Ext = Pathname:getname()

EXPECT("NOM-005-name",      Name,     "c.txt")
EXPECT("NOM-006-basename",  Basename, "c")
EXPECT("NOM-007-extension", Ext,      "txt")
EXPECT("NOM-008-convert-internal", InternalPathname, "a/c.txt")
EXPECT("NOM-009-convert-native",   NativePathname, nativepathname("a/c.txt"))

Pathname            = newpathname("/foo/bar")
GotDirectory        = Pathname:getdirectory()
Name, Basename, Ext = Pathname:getname()

EXPECT("NOM-010-name",      Name,     "bar")
EXPECT("NOM-011-basename",  Basename, "bar")
EXPECT("NOM-012-extension", Ext,      nil)
EXPECT("NOM-013-directory", GotDirectory, nativepathname("/foo"))

Pathname       = newpathname("x/y/z.txt"):parent()
ExpectedDir    = nativepathname("x/y")
NativePathname = Pathname:convert("native")
Name, Basename, Ext = Pathname:getname()

EXPECT("NOM-014-name",      Name,     "y")
EXPECT("NOM-015-basename",  Basename, "y")
EXPECT("NOM-016-extension", Ext,      nil)
EXPECT("NOM-017-parent",    NativePathname, ExpectedDir)

Pathname     = newpathname("/"):parent()
ExpectedDir  = nativepathname("/")
GotDirectory = Pathname:convert("native")
EXPECT("NOM-018-parent-root", GotDirectory, ExpectedDir)

Pathname     = newpathname("C:"):parent()
ExpectedDir  = nativepathname("C:/")
GotDirectory = Pathname:convert("native")
EXPECT("NOM-019-parent-drive", GotDirectory, ExpectedDir)

Pathname = newpathname("dir/sub"):child("file.bin")
Name, Basename, Ext = Pathname:getname()
InternalPathname = Pathname:convert("internal")

EXPECT("NOM-020-name",      Name,     "file.bin")
EXPECT("NOM-021-basename",  Basename, "file")
EXPECT("NOM-022-extension", Ext,      "bin")
EXPECT("NOM-023-child-convert", InternalPathname, "dir/sub/file.bin")

Pathname = newpathname("noext")
Name, Basename, Ext = Pathname:getname()

EXPECT("NOM-024-name-noext",      Name,     "noext")
EXPECT("NOM-025-basename-noext",  Basename, "noext")
EXPECT("NOM-026-extension-noext", Ext,      nil)

Pathname = newpathname("C:")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
Name, Basename, Ext = Pathname:getname()

EXPECT("NOM-027-drive-name",      Name,     "C")
EXPECT("NOM-028-drive-basename",  Basename, "C")
EXPECT("NOM-029-drive-extension", Ext,      nil)
EXPECT("NOM-030-drive-internal",  InternalPathname, "C:/")
EXPECT("NOM-031-drive-native",    NativePathname,   nativepathname("C:/"))

Pathname = newpathname("C:")
InternalPathname = Pathname:convert("internal")
EXPECT("NOM-031-drive-only-internal", InternalPathname, "C:/")

Pathname            = newpathname("/")
Name, Basename, Ext = Pathname:getname()

EXPECT("NOM-032-root-name",      Name,     nil)
EXPECT("NOM-033-root-basename",  Basename, nil)
EXPECT("NOM-034-root-extension", Ext,      nil)

Pathname     = newpathname("C:/test.txt")
GotDirectory = Pathname:getdirectory("internal")
EXPECT("NOM-035-getdirectory-drive-file", GotDirectory, "C:/")

Pathname     = newpathname("C:/")
GotDirectory = Pathname:getdirectory("internal")
EXPECT("NOM-036-getdirectory-drive-root", GotDirectory, "C:/")

Pathname     = newpathname("/test.txt")
GotDirectory = Pathname:getdirectory("internal")
EXPECT("NOM-037-getdirectory-root-file",  GotDirectory, "/")

Pathname     = newpathname("/")
GotDirectory = Pathname:getdirectory("internal")
EXPECT("NOM-038-getdirectory-root", GotDirectory, "/")

Pathname   = newpathname("/")
Depth      = Pathname:depth()
IsAbsolute = Pathname:isabsolute()
EXPECT("NOM-039-root-depth",       Depth,      1)
EXPECT("NOM-040-root-isabsolute",  IsAbsolute, true)

Pathname   = newpathname("C:")
Depth      = Pathname:depth()
IsAbsolute = Pathname:isabsolute()
EXPECT("NOM-041-drive-depth",      Depth,      1)
EXPECT("NOM-042-drive-isabsolute", IsAbsolute, true)

Pathname   = newpathname("a/b/c.txt")
Depth      = Pathname:depth()
IsRelative = Pathname:isrelative()
EXPECT("NOM-043-file-depth",       Depth,      3)
EXPECT("NOM-044-file-isrelative",  IsRelative, true)

Pathname         = newpathname("a/b/c")
Cloned           = Pathname:clone()
InternalPathname = Cloned:convert("internal")
EXPECT("NOM-045-clone-internal",    InternalPathname, "a/b/c")

Cloned:setname("d")
InternalPathname = Pathname:convert("internal")
local ClonedInternal = Cloned:convert("internal")
EXPECT("NOM-046-clone-independent", InternalPathname, "a/b/c")
EXPECT("NOM-047-clone-changed", ClonedInternal, "a/b/d")

Pathname = newpathname("a/b/c")
Pathname:remove(2)
InternalPathname = Pathname:convert("internal")
EXPECT("NOM-048-removeelement", InternalPathname, "a/c")

--------------------------------------------------------------------------------
-- RESOLUTION / EDGE CASES                                                    --
--------------------------------------------------------------------------------

Reporter:block("RESOLUTION / EDGE CASES")

-- relative paths: leading ".." elements are preserved for relative paths
Pathname         = newpathname("../../a")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-001-rel-preserve", InternalPathname, "../../a")

Pathname         = newpathname("../..")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-002-rel-double-preserve", InternalPathname, "../..")

-- relative cancellation: "a/../.." should collapse to ".."
Pathname         = newpathname("a/../..")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-003-rel-cancel", InternalPathname, "..")

-- absolute paths: ".." should not climb above root
Pathname         = newpathname("/..")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("RSL-004-abs-root-up",     InternalPathname, "/")
EXPECT("RSL-005-abs-root-native", NativePathname,   nativepathname("/"))

-- drive paths: "C:/.." resolves to the drive only
Pathname         = newpathname("C:/..")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("RSL-006-drive-up",        InternalPathname, "C:/")
EXPECT("RSL-007-drive-up-native", NativePathname,   nativepathname("C:/"))

-- absolute cancellation: "/a/.." should become root
Pathname         = newpathname("/a/..")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("RSL-008-abs-cancel",        InternalPathname, "/")
EXPECT("RSL-009-abs-cancel-native", NativePathname,   nativepathname("/"))

-- dot handling: "." elements should be removed
Pathname         = newpathname("a/./b.txt")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-010-dot-middle", InternalPathname, "a/b.txt")

-- leading dot: "./a" -> "a"
Pathname         = newpathname("./a")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-011-dot-leading", InternalPathname, "a")

-- Multiple slashes
Pathname         = newpathname("a//////////////b.txt")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-012-dot-multiple-slashes", InternalPathname, "a/b.txt")

Pathname         = newpathname("../test/root/..")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-013-rel-complex", InternalPathname, "../test")

Pathname         = newpathname("../../../TEST")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-014-rel-triple-preserve", InternalPathname, "../../../TEST")

Pathname         = newpathname("../../../TEST/pop/..")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-015-rel-pop", InternalPathname, "../../../TEST")

-- Additional absolute path tests for ".." behavior
Pathname         = newpathname("/a/b/..")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-016-abs-a-b-pop", InternalPathname, "/a")

Pathname         = newpathname("/a/../../b")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-017-abs-a-up-up-b", InternalPathname, "/b")

Pathname         = newpathname("/../b")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-018-abs-up-b", InternalPathname, "/b")

Pathname         = newpathname("/a/./../b")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-019-abs-a-dot-up-b", InternalPathname, "/b")

Pathname         = newpathname("C:/a/..")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-020-drive-a-pop", InternalPathname, "C:/")

Pathname         = newpathname("C:/a/../b")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-021-drive-a-up-b", InternalPathname, "C:/b")

-- Drive-edge cases with many ".." elements
Pathname         = newpathname("C:/a/../b/../../../../c")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-022-drive-many-up-c", InternalPathname, "C:/c")

Pathname         = newpathname("C:/a/../b/../../../..")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-023-drive-many-up-root", InternalPathname, "C:/")

Pathname         = newpathname("C:/a/../b/../../../../")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-024-drive-many-up-trailing", InternalPathname, "C:/")

Pathname         = newpathname("/a/../..")
InternalPathname = Pathname:convert("internal")
EXPECT("RSL-025-abs-a-up-up-root", InternalPathname, "/")

--------------------------------------------------------------------------------
-- SETNAME                                                                    --
--------------------------------------------------------------------------------

Reporter:block("SETNAME")

Pathname         = newpathname("dir/old.txt")
Pathname:setname("new.log")
InternalPathname = Pathname:convert("internal")
EXPECT("SET-001-basic", InternalPathname, "dir/new.log")

Pathname         = newpathname("base")
Pathname:setname("other")
InternalPathname = Pathname:convert("internal")
EXPECT("SET-002-simple", InternalPathname, "other")

Pathname         = newpathname("/")
Pathname:setname("foo")
InternalPathname = Pathname:convert("internal")
EXPECT("SET-003-root", InternalPathname, "foo")

Pathname         = newpathname("C:")
Pathname:setname("foo")
InternalPathname = Pathname:convert("internal")
EXPECT("SET-004-drive", InternalPathname, "foo")

Pathname         = newpathname("")
Pathname:setname("foo")
InternalPathname = Pathname:convert("internal")
EXPECT("SET-005-empty", InternalPathname, "foo")

Pathname         = newpathname("a/b/c"):setname("d"):setname("e")
InternalPathname = Pathname:convert("internal")
EXPECT("SET-006-chaining", InternalPathname, "a/b/e")

--------------------------------------------------------------------------------
-- PARENT (RELATIVE AND ABSOLUTE)                                             --
--------------------------------------------------------------------------------

Reporter:block("PARENT")

Pathname         = newpathname("a/b")
Pathname:parent()
InternalPathname = Pathname:convert("internal")
EXPECT("PAR-001-rel-simple", InternalPathname, "a")

Pathname         = newpathname("a")
Pathname:parent()
InternalPathname = Pathname:convert("internal")
EXPECT("PAR-002-rel-to-empty", InternalPathname, "")

Pathname         = newpathname("")
Pathname:parent()
InternalPathname = Pathname:convert("internal")
EXPECT("PAR-003-rel-empty-to-up", InternalPathname, "..")

Pathname         = newpathname("..")
Pathname:parent()
InternalPathname = Pathname:convert("internal")
EXPECT("PAR-004-rel-up-to-upup", InternalPathname, "../..")

Pathname         = newpathname("/a/b")
Pathname:parent()
InternalPathname = Pathname:convert("internal")
EXPECT("PAR-005-abs-simple", InternalPathname, "/a")

Pathname         = newpathname("/")
Pathname:parent()
InternalPathname = Pathname:convert("internal")
EXPECT("PAR-006-abs-root-nop", InternalPathname, "/")

Pathname         = newpathname("C:/a")
Pathname:parent()
InternalPathname = Pathname:convert("internal")
EXPECT("PAR-007-drive-simple", InternalPathname, "C:/")

Pathname         = newpathname("C:")
Pathname:parent()
InternalPathname = Pathname:convert("internal")
EXPECT("PAR-008-drive-nop", InternalPathname, "C:/")

--------------------------------------------------------------------------------
-- CONCAT                                                                     --
--------------------------------------------------------------------------------

Reporter:block("CONCAT")

Pathname         = newpathname("a/b") .. newpathname("c/d")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("CON-001-rel-rel",        InternalPathname, "a/b/c/d")
EXPECT("CON-002-rel-rel-native", NativePathname,   nativepathname("a/b/c/d"))

Pathname         = newpathname("/a") .. newpathname("b/c")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("CON-003-abs-rel",        InternalPathname, "/a/b/c")
EXPECT("CON-004-abs-rel-native", NativePathname,   nativepathname("/a/b/c"))

Pathname         = newpathname("C:") .. newpathname("a")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("CON-005-drive-rel",        InternalPathname, "C:/a")
EXPECT("CON-006-drive-rel-native", NativePathname,   nativepathname("C:/a"))

Pathname         = newpathname("") .. newpathname("a")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("CON-007-empty-left",        InternalPathname, "a")
EXPECT("CON-008-empty-left-native", NativePathname,   nativepathname("a"))

Pathname         = newpathname("a") .. newpathname("b") .. newpathname("c")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("CON-009-chain",        InternalPathname, "a/b/c")
EXPECT("CON-010-chain-native", NativePathname,   nativepathname("a/b/c"))

Pathname         = newpathname("/") .. newpathname("foo")
InternalPathname = Pathname:convert("internal")
NativePathname   = Pathname:convert("native")
EXPECT("CON-011-root-rel",        InternalPathname, "/foo")
EXPECT("CON-012-root-rel-native", NativePathname,   nativepathname("/foo"))

--------------------------------------------------------------------------------
-- SUMMARY
--------------------------------------------------------------------------------

Reporter:printf("== SUMMARY ==")
Reporter:summary("os.exit")
