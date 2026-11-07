# Using SQLite

* [Introduction](#introduction)
* [Initialization](#initialization)
  * [Opening the database](#opening-the-database)
  * [Configuring the busy timeout](#configuring-the-busy-timeout)
  * [Configuring error handling](#configuring-error-handling)
* [Usage](#usage)
  * [Create a table](#create-a-table)
  * [Insert with exec](#insert-with-exec)
  * [Insert with a prepared statement](#insert-with-a-prepared-statement)
  * [Insert with RETURNING](#insert-with-returning)
  * [Insert multiple rows in a transaction](#insert-multiple-rows-in-a-transaction)
  * [Select](#select)
  * [Update rows](#update-rows)
  * [Delete rows](#delete-rows)
* [Last insert and changes](#last-insert-and-changes)
* [Error handling](#error-handling)
  * [Checking return values](#checking-return-values)
  * [Raising errors](#raising-errors)
* [Closing the database](#closing-the-database)

# Introduction

This example shows how to use `com.sqlite3`. It requires `sqlite3.dll` on Windows and `libsqlite3.so.0` on Linux.

Read further:

- [Listing of the example](../tests/examples/test-sqlite3.lua)
- [SQLite3 Lua interface](./comexe-reference-sqlite3.md)

# Initialization

## Opening the database

```lua
local sqlite3 = require("com.sqlite3")

local Database, ErrorString = sqlite3.open(":memory:")
if (not Database) then
  error(ErrorString)
end
```

The resulting value is a [Database object](./comexe-reference-sqlite3.md#database-objects).

| SQL statements                | Recommended interface            |
|-------------------------------|----------------------------------|
| `CREATE`, `DELETE`            | `Database:exec(SqlString)`       |
| `INSERT`, `SELECT`, `UPDATE`  | `Database:prepare(SqlString)`    |
| `BEGIN`, `COMMIT`, `ROLLBACK` | `Database:transaction(Function)` |

## Configuring the busy timeout

Avoid `SQLITE_BUSY` by increasing [the busy timeout](https://sqlite.org/c3ref/busy_timeout.html).

```lua
Database:setbusytimeout(5000)
```

## Configuring error handling

Enable the raising mode.

```lua
Database:raiseonerror(true)
```

When SQLite returns an error code, the Lua module raises [an error](https://www.lua.org/manual/5.5/manual.html#2.3).

# Usage

## Create a table

```lua
Database:exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score INTEGER, data BLOB)")
```

## Insert with exec

Insert simple values.

```lua
Database:exec("INSERT INTO users VALUES (1, 'user-1', 3,  NULL)")
Database:exec("INSERT INTO users VALUES (2, 'user-2', 12, NULL)")
Database:exec("INSERT INTO users VALUES (3, 'user-3', 7,  NULL)")
```

`Database:exec` is not always recommended because of escaping.

```lua
Database:exec("INSERT INTO users VALUES (4, 'user-4', 7, 'quoted \"string\"')")
```

## Insert with a prepared statement

### Statement creation

```lua
local InsertStatement = Database:prepare("INSERT INTO users VALUES (?, ?, ?, ?)")
```

### Parameter binding

```lua
InsertStatement:setint(1, 5)                  -- id
InsertStatement:settext(2, "user-5")          -- name
InsertStatement:setint(3, 5)                  -- score
InsertStatement:setblob(4, 'quoted "string"') -- data
```

### Execution

```lua
InsertStatement:step()
```

## Insert with RETURNING

| SQL statement          | statement:step()                                               |
|------------------------|----------------------------------------------------------------|
| `INSERT`               | `step()` returns `"DONE"`                                      |
| `INSERT` + `RETURNING` | `step()` first returns `"ROW"`, then `step()` returns `"DONE"` |

### Statement creation

```lua
local ReturnStatement = Database:prepare("INSERT INTO users VALUES (?, ?, ?, ?) RETURNING id, name")
```

### Parameter binding

```lua
ReturnStatement:setint(1, 6)               -- id
ReturnStatement:settext(2, "user-6")       -- name
ReturnStatement:setnull(3)                 -- score
ReturnStatement:setblob(4, "\xC0\xFF\xEE") -- data
```

### Execution

```lua
local ReturnStatusString = ReturnStatement:step()

-- The first call to step() returns "ROW"
if (ReturnStatusString == "ROW") then
  -- Read the returned row
  local InsertedId   = ReturnStatement:getint(1)
  local InsertedName = ReturnStatement:gettext(2)
  print(string.format("1 row id:%d name:%s inserted", InsertedId, InsertedName))
  -- The second call to step() returns "DONE"
  ReturnStatement:step()
end
```

## Insert multiple rows in a transaction

```lua
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

local Success, ErrorString = Database:transaction(TEST_Transaction, Database)
```

`Database:transaction` runs the user callback between `BEGIN` and `COMMIT`, and rolls back when the function raises an error.

The callback raises an error, so the transaction rolls back.

```lua
local function TEST_TransactionRollback (Database)
  error("nothing to insert")
end

local Success, ErrorString, Value = Database:transaction(TEST_TransactionRollback, Database)
-- Success:false, ErrorString:"nothing to insert", Value:nil
```

The callback returns a value, so the transaction commits.

```lua
local function TEST_TransactionSuccess (Database)
  return false
end

local Success, ErrorString, Value = Database:transaction(TEST_TransactionSuccess, Database)
-- Success:true, ErrorString:nil, Value:false
```

Note that `Database:transaction` returns only the first value of the callback and discards the others.

## Select

### Statement creation

```lua
local SelectStatement = Database:prepare("SELECT name, score, hex(data) FROM users WHERE score > ? ORDER BY score")
```

### Parameter binding

```lua
-- SELECT rows WHERE (score > 0)
SelectStatement:setint(1, 0)
```

### Execution

```lua
local ColumnCount  = SelectStatement:getcount()
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
```

### Data types and values

SQLite is dynamically typed: `gettype` reports the type of the value stored in that column for the current row.

```lua
local ValueType = Statement:gettype(ColumnIndex)
```

| ValueType   | Accessor                     | Lua value       | Comment                                        |
|-------------|------------------------------|-----------------|------------------------------------------------|
| `"integer"` | `Statement:getint(Index)`    | number          | 64-bit, exact up to 2^53                       |
| `"float"`   | `Statement:getdouble(Index)` | number          |                                                |
| `"text"`    | `Statement:gettext(Index)`   | string          | `gettext` on a number returns its textual form |
| `"blob"`    | `Statement:getblob(Index)`   | string (binary) | `getbytes(Index)` returns its size in bytes    |
| `"null"`    | n/a                          | `nil`           | every accessor returns `nil` for NULL          |

## Update rows

### Statement creation

```lua
local UpdateStatement = Database:prepare("UPDATE users SET score = ? WHERE name = ?")
```

### Parameter binding

```lua
-- Set Score=25 for rows where name="user-1"
UpdateStatement:setint(1, 25)
UpdateStatement:settext(2, "user-1")
```

### Execution

```lua
UpdateStatement:step()
print(string.format("%d rows updated", Database:getchanges()))
```

## Delete rows

```lua
Database:exec("DELETE FROM users WHERE score > 10")
print(string.format("%d rows deleted", Database:getchanges()))
```

# Last insert and changes

`getlastrowid()` returns the rowid of the last inserted row. It is the simple alternative to `RETURNING` when only the id is needed:

```lua
print(string.format("last rowid: %d", Database:getlastrowid()))
```

`getchanges()` returns the number of rows modified by the most recent `INSERT`, `UPDATE` or `DELETE`:

```lua
print(string.format("changes: %d", Database:getchanges()))
```

Both report on the connection, not on a specific statement.

# Error handling

There are two ways to handle errors.

| Mode                            | Behavior                                      |
|---------------------------------|-----------------------------------------------|
| `raiseonerror(false)` (default) | Each call returns error details when it fails |
| `raiseonerror(true)`            | Any SQLite failure raises an error            |

## Checking return values

```lua
local Success, ErrorString = Database:exec("CREATE TABLE users (...)")
if (not Success) then
  print(string.format("Error: %s", ErrorString))
end
```

API overview:

| Function                | Returns                        | Comment                                                 |
|-------------------------|--------------------------------|---------------------------------------------------------|
| `Database:exec`         | `Success, ErrorString`         | Statements with no result                               |
| `Database:prepare`      | `Statement, ErrorString`       | Returns a statement object                              |
| `Statement:step`        | `StatusString, SqliteCode`     | `SqliteCode` is the integer value from SQLite           |
| `Database:transaction`  | `Success, ErrorString, Result` | `Result` is the first return value of the user callback |
| `Database:getlasterror` | `ErrorString`                  | Returns `"not an error"` when there is no error         |

`StatusString` is `"ROW"`, `"DONE"`, `"BUSY"` or `"ERROR"`.

## Raising errors

```lua
Database:raiseonerror(true)
Database:exec("CREATEXXXtypo TABLE users (...)") -- Invalid SQL: error raised, program exited (1)
Database:exec("CREATE        TABLE users (...)") -- Not executed
```

The way to handle errors here is to use [`pcall`](https://www.lua.org/manual/5.5/manual.html#pdf-pcall).

```lua
Database:raiseonerror(true)

local function TrySql (Database)
  Database:exec("CREATEXXXtypo TABLE users (...)") -- Invalid SQL
  Database:exec("CREATE        TABLE users (...)")
end

local Success, ErrorString = pcall(TrySql, Database)
if (not Success) then
  -- Handle the error: recovery, log, exit, etc.
end
```

# Closing the database

```lua
Database:close()
```
