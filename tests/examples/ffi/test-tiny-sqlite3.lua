--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local format  = string.format
local sqlite3 = require("tiny-sqlite3")

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
    local ColumnType = Statement:ColumnType(ColumnIndex)
    local ValueString
    if (ColumnType == "blob") then
      local BlobData = Statement:ColumnBlob(ColumnIndex)
      if BlobData then
        ValueString = HexDump(BlobData)
      else
        ValueString = "(NULL)"
      end
    else
      local ColumnText = Statement:ColumnText(ColumnIndex)
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
print(format("Last changes: %d", Database:changes()))
print(format("  Last rowid: %d", Database:lastInsertRowid()))

-- Insert row with prepared statement
local InsertStmt = Database:prepare("INSERT INTO people VALUES (?, ?, ?, ?)")
InsertStmt:BindInt(1, 4)
InsertStmt:BindText(2, "Dana")
InsertStmt:BindNull(3)
InsertStmt:BindBlob(4, "\xC0\xFF\xEE\x00\xBE\xEF")
InsertStmt:Step()
print(format("Row with NULL age and BLOB inserted, rowid: %d", Database:lastInsertRowid()))

-- Prepare query
local Statement, PrepareErrorString = Database:prepare("SELECT name, age, data FROM people ORDER BY age")
if (not Statement) then
  print(format("ERROR: %s", PrepareErrorString))
  Database:close()
  os.exit(1)
end

-- Print column names
local ColumnCount = Statement:ColumnCount()
for ColumnIndex = 1, ColumnCount do
  io.write(format("%-12s", Statement:ColumnName(ColumnIndex)))
end
print()

-- Print each row
local Continue = true
while Continue do
  local Success, Status = Statement:Step()
  if (not Success) then
    print(format("ERROR: %s", Status))
    Continue = false
  elseif (Status == "DONE") then
    Continue = false
  else
    PrintRow(Statement, ColumnCount)
    print()
  end
end

-- Show last error
local LastError = Database:lastError()
if LastError then
  print(format("Last error: %s", LastError))
else
  print("Last error: (none)")
end

-- Clean up
Database:close()
