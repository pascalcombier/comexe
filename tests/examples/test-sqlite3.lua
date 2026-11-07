local sqlite3 = require("com.sqlite3")

-- Open in-memory database
local Database, ErrorString = sqlite3.open(":memory:")

-- Skip the test if the DLL is not found
if (not Database) then
  print(string.format("TEST SKIPPED: %s", ErrorString))
  os.exit(0)
end

Database:setbusytimeout(5000)
Database:raiseonerror(true)

-- Create table
Database:exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score INTEGER, data BLOB)")

-- Insert data
Database:exec("INSERT INTO users VALUES (1, 'user-1',  3, NULL)")
Database:exec("INSERT INTO users VALUES (2, 'user-2', 12, NULL)")
Database:exec("INSERT INTO users VALUES (3, 'user-3',  7, NULL)")

-- escaped string
Database:exec("INSERT INTO users VALUES (4, 'user-4',  7, 'quoted \"string\"')")

-- Create INSERT statement
local InsertStatement = Database:prepare("INSERT INTO users VALUES (?, ?, ?, ?)")

-- Insert row with prepared statement
InsertStatement:setint(1, 5)                  -- id
InsertStatement:settext(2, "user-5")          -- name
InsertStatement:setint(3, 5)                  -- score
InsertStatement:setblob(4, 'quoted "string"') -- data

InsertStatement:step()

-- Insert with RETURNING
local ReturnStatement = Database:prepare("INSERT INTO users VALUES (?, ?, ?, ?) RETURNING id, name")

ReturnStatement:setint(1, 6)               -- id
ReturnStatement:settext(2, "user-6")       -- name
ReturnStatement:setnull(3)                 -- score
ReturnStatement:setblob(4, "\xC0\xFF\xEE") -- data

local ReturnStatusString = ReturnStatement:step()

if (ReturnStatusString == "ROW") then
  -- Read the returned row
  local InsertedId   = ReturnStatement:getint(1)
  local InsertedName = ReturnStatement:gettext(2)
  print(string.format("1 row id:%d name:%s inserted", InsertedId, InsertedName))
  -- Second call to step() returns "DONE"
  ReturnStatement:step()
end

-- Insert multiple rows in one transaction
local function TEST_Transaction (Database)
  for NewId = 7, 18 do
    InsertStatement:reset()
    InsertStatement:setint(1, NewId)
    InsertStatement:settext(2, string.format("user-%d", NewId))
    InsertStatement:setint(3, NewId)
    InsertStatement:setnull(4)
    InsertStatement:step()
  end
end

Database:transaction(TEST_Transaction, Database)

-- Prepare SELECT query
local SelectStatement = Database:prepare("SELECT name, score, hex(data) FROM users WHERE score > ? ORDER BY score")

-- Print column names
local ColumnCount = SelectStatement:getcount()
for ColumnIndex = 1, ColumnCount do
  io.write(string.format("%-12s", SelectStatement:getname(ColumnIndex)))
end
io.write("\n")

-- Bind the "score > ?" parameter
SelectStatement:setint(1, 0)

-- Print the rows
local StatusString = SelectStatement:step()

while (StatusString == "ROW") do
  -- Print columns
  for ColumnIndex = 1, ColumnCount do
    local ValueType   = SelectStatement:gettype(ColumnIndex)
    local ValueString = SelectStatement:gettext(ColumnIndex)
    io.write(string.format("%s:%-12s", ValueType, ValueString))
  end
  io.write("\n")
  -- Next row
  StatusString = SelectStatement:step()
end

-- Update rows
local UpdateStatement = Database:prepare("UPDATE users SET score = ? WHERE name = ?")
UpdateStatement:setint(1, 25)
UpdateStatement:settext(2, "user-1")
UpdateStatement:step()
print(string.format("%d rows updated", Database:getchanges()))

-- Delete rows
Database:exec("DELETE FROM users WHERE score > 10")
print(string.format("%d rows deleted", Database:getchanges()))

print("--- manual mode: check return values")

Database:raiseonerror(false)

-- Expect failure: same id
local DuplicateSuccess, DuplicateErrorString = Database:exec("INSERT INTO users VALUES (4, 'duplicate', 3, NULL)")
if (not DuplicateSuccess) then
  print(string.format("EXPECTED ERROR: %s", DuplicateErrorString))
end

-- Check every return value
local function TEST_ManualInsert ()
  local Success, ManualErrorString = Database:exec("BEGIN")
  if (not Success) then
    return false, ManualErrorString
  end

  local InsertSuccess, InsertErrorString = Database:exec("INSERT INTO users VALUES (19, 'user-19', 1, NULL)")
  if (not InsertSuccess) then
    Database:exec("ROLLBACK")
    return false, InsertErrorString
  end

  local CommitSuccess, CommitErrorString = Database:exec("COMMIT")
  if (not CommitSuccess) then
    Database:exec("ROLLBACK")
    return false, CommitErrorString
  end

  return true
end

local ManualOk, ManualErrorString = TEST_ManualInsert()
if (ManualOk) then
  print(string.format("%d row inserted", Database:getchanges()))
else
  print(string.format("ERROR: %s", ManualErrorString))
end

-- Clean up
Database:close()
