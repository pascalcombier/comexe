# SQLite3 Lua interface

* [Overview](#overview)
* [Database objects](#database-objects)
* [Statement objects](#statement-objects)
* [Basic usage](#basic-usage)
* [Example](#example)

# Overview

This module provides a Lua interface to [SQLite3](https://www.sqlite.org/), implemented using [libffi](./comexe-reference-ffi.md). A detailed guide explains [how to build this module](./page-ffi-sqlite.md) step by step.

Features

- Opening and closing databases
- Arbitrary SQL code execution
- Prepared statements
- Idiomatic Lua 1-based indexing

```lua
local sqlite3 = require("com.sqlite3")
```

The `sqlite3` module exposes a single function:

| Function                 | Description                                                    |
|--------------------------|----------------------------------------------------------------|
| `sqlite3.open(Filename)` | Return a ***Database*** object, or `nil, ErrorString` on error |

Notes
- Creates the file if it does not exist
- `sqlite3.open` is a wrapper to [sqlite3_open](https://sqlite.org/c3ref/open.html), so SQLite features like `":memory:"` apply
- Requires `sqlite3.dll` on Windows or `libsqlite3.so.0` on Linux

The ***Database*** type is described in the following chapter.

# Database objects

| Method               | Description                                                                              |
|----------------------|------------------------------------------------------------------------------------------|
| `exec(SqlString)`    | Execute SQL statements (CREATE, INSERT, UPDATE, ...). Returns `Success, ErrorString`     |
| `prepare(SqlString)` | Compile an SQL statement for later execution. Returns `Statement, ErrorString`             |
| `getlasterror()`     | Return the last error message (string)                                                   |
| `getlastrowid()`     | Return the rowid of the most recent successful INSERT                                    |
| `getchanges()`       | Return the number of rows modified by the most recent INSERT, UPDATE or DELETE statement |
| `close()`            | Close the database                                                                       |

Notes
- `prepare(SqlString)` returns a **Statement** object, described in the following chapter.

# Statement objects

| Method                    | Description                                                                                          |
|---------------------------|------------------------------------------------------------------------------------------------------|
| `step()`                  | Execute the statement. Returns `StatusString, StatusInteger`                                         |
| `reset()`                 | Reset the statement for re-execution. Bound parameters keep their values                     |
| `getcount()`              | Number of result columns                                                                             |
| `getname(Index)`          | Name of the column at `Index`                                                                        |
| `gettype(Index)`          | Type of the value at column `Index`: `"integer"`, `"float"`, `"text"`, `"blob"` or `"null"`          |
| `getbytes(Index)`         | Byte length of the value at column `Index`                                                           |
| `gettext(Index)`          | TEXT value at column `Index`, or `nil` for NULL                                                      |
| `getint(Index)`           | INTEGER value at column `Index`                                                                      |
| `getdouble(Index)`        | REAL (float) value at column `Index`                                                                 |
| `getblob(Index)`          | Raw BLOB bytes at column `Index`, or `nil` for NULL                                                  |
| `settext(Index, Value)`   | Bind a TEXT value (UTF-8 string) to parameter `Index`                                                |
| `setint(Index, Value)`    | Bind an INTEGER value to parameter `Index`                                                           |
| `setdouble(Index, Value)` | Bind a REAL (float) value to parameter `Index`                                                       |
| `setblob(Index, Value)`   | Bind a BLOB value (raw binary string) to parameter `Index`                                           |
| `setnull(Index)`          | Bind NULL to parameter `Index`                                                                       |

Notes
- All `Index` arguments are 1-based
- The `get*` methods extract values from the current row (after a call to `step`)
- For NULL values, `gettext`/`getblob` return `nil`; `getint`/`getdouble` return `0` (SQLite C API)
- `step()` returns `StatusString, StatusInteger` where `StatusString` is:
   - `"ROW"` for each result row of a SELECT
   - `"DONE"` when execution is finished
   - `"BUSY"`, `"CONSTRAINT"`, `"MISUSE"` or `"ERROR"` on failure
- `StatusInteger` is the raw SQLite result code

# Basic usage

```lua
local sqlite3 = require("com.sqlite3")

local format = string.format

local Database, ErrorString = sqlite3.open(":memory:")
if (not Database) then
  error(ErrorString)
end

-- Execute SQL without result rows
Database:exec("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, age INTEGER, data BLOB)")
Database:exec("INSERT INTO people VALUES (1, 'Alice', 30, NULL)")
Database:exec("INSERT INTO people VALUES (2, 'Bob', 25, NULL)")

-- Prepared statement with bound parameters
local InsertStatement = Database:prepare("INSERT INTO people VALUES (?, ?, ?, ?)")
InsertStatement:setint(1, 3)
InsertStatement:settext(2, "Charlie")
InsertStatement:setint(3, 35)
InsertStatement:setblob(4, "\xC0\xFF\xEE")
InsertStatement:step()

-- Query with a prepared statement
local SelectStatement = Database:prepare("SELECT name, age FROM people ORDER BY age")
local Continue = true
while Continue do
  local StatusString = SelectStatement:step()
  if (StatusString == "ROW") then
    print(format("%s is %d", SelectStatement:gettext(1), SelectStatement:getint(2)))
  elseif (StatusString == "DONE") then
    Continue = false
  else
    error(Database:getlasterror())
  end
end

-- Read back a BLOB value
local BlobStatement = Database:prepare("SELECT data FROM people WHERE name = ?")
BlobStatement:settext(1, "Charlie")
BlobStatement:step()
local Blob = BlobStatement:getblob(1)
assert(Blob == "\xC0\xFF\xEE")
print(format("Charlie data: %d bytes", BlobStatement:getbytes(1)))

Database:close()
```

# Example

[test-sqlite3.lua](../tests/examples/ffi/test-sqlite3.lua)
