--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local format  = string.format
local sqlite3 = require("com.sqlite3")

--------------------------------------------------------------------------------
-- HELPERS                                                                    --
--------------------------------------------------------------------------------

local function HexDumpChar (Char)
  return format("%02X", string.byte(Char))
end

local function HexDump (Data)
  return (Data:gsub(".", HexDumpChar))
end

local function PrintRow (Statement, ColumnCount)
  for ColumnIndex = 1, ColumnCount do
    local ColumnType = Statement:gettype(ColumnIndex)
    local ValueString
    if (ColumnType == "blob") then
      local BlobData = Statement:getblob(ColumnIndex)
      if BlobData then
        ValueString = HexDump(BlobData)
      else
        ValueString = "(NULL)"
      end
    else
      local ColumnText = Statement:gettext(ColumnIndex)
      ValueString = (ColumnText or "(NULL)")
    end
    io.write(format("%-12s[%-6s] ", ValueString, ColumnType))
  end
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

-- Open in-memory database
local Database, ErrorString = sqlite3.open(":memory:")
if (not Database) then
  print(format("TEST SKIPPED: %s", ErrorString))
  os.exit(0)
end

-- Create table and insert data
Database:exec("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, age INTEGER, data BLOB)")
Database:exec("INSERT INTO people VALUES (1, 'Alice', 30, NULL)")
Database:exec("INSERT INTO people VALUES (2, 'Bob', 25, NULL)")
Database:exec("INSERT INTO people VALUES (3, 'Charlie', 35, NULL)")

-- Show changes and last rowid after inserts
print(format("Last changes: %d", Database:getchanges()))
print(format("  Last rowid: %d", Database:getlastrowid()))

-- Insert row with prepared statement
local InsertStmt = Database:prepare("INSERT INTO people VALUES (?, ?, ?, ?)")
InsertStmt:setint(1, 4)
InsertStmt:settext(2, "Dana")
InsertStmt:setnull(3)
InsertStmt:setblob(4, "\xC0\xFF\xEE\x00\xBE\xEF")
InsertStmt:step()
print(format("Row with NULL age and BLOB inserted, rowid: %d", Database:getlastrowid()))

-- Prepare query
local Statement, PrepareErrorString = Database:prepare("SELECT name, age, data FROM people ORDER BY age")
if (not Statement) then
  print(format("ERROR: %s", PrepareErrorString))
  Database:close()
  os.exit(1)
end

-- Print column names
local ColumnCount = Statement:getcount()
for ColumnIndex = 1, ColumnCount do
  io.write(format("%-12s", Statement:getname(ColumnIndex)))
end
print()

-- Print each row
local Continue = true
while Continue do
  local StatusString = Statement:step()
  if (StatusString == "ROW") then
    PrintRow(Statement, ColumnCount)
    print()
  elseif (StatusString == "DONE") then
    Continue = false
  else
    print(format("ERROR: %s", Database:getlasterror()))
    Continue = false
  end
end

-- Show last error
local LastError = Database:getlasterror()
if LastError then
  print(format("Last error: %s", LastError))
else
  print("Last error: (none)")
end

-- Clean up
Database:close()
