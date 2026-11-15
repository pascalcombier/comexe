# SQLite3 Lua interface

* [Overview](#overview)
  * [Features](#features)
  * [Loading the module](#loading-the-module)
* [Module API](#module-api)
  * [open](#open)
* [Database objects](#database-objects)
  * [Database methods](#database-methods)
  * [Error handling](#error-handling)
    * [Default mode](#default-mode)
    * [Raising mode](#raising-mode)
  * [Busy timeout](#busy-timeout)
  * [Executing SQL](#executing-sql)
  * [Preparing a statement](#preparing-a-statement)
  * [Transactions](#transactions)
  * [Connection attributes](#connection-attributes)
  * [Closing](#closing)
* [Statement objects](#statement-objects)
  * [Statement methods](#statement-methods)
  * [Introspection](#introspection)
  * [Binding parameters](#binding-parameters)
  * [Stepping](#stepping)
  * [Reading rows](#reading-rows)
  * [Reusing a statement](#reusing-a-statement)

# Overview

This module provides a Lua interface to [SQLite3](https://www.sqlite.org/), implemented with [libffi](./comexe-reference-ffi.md). A detailed guide explains [how to build this module](./page-ffi-sqlite.md) step by step.

## Features

- Execute SQL statements
- Prepared statements with parameters
- Transactions
- Consistent 1-based indexing

## Loading the module

```lua
local sqlite3 = require("com.sqlite3")
```

The shared library is loaded at the first call to `sqlite3.open`: `sqlite3.dll` on Windows, `libsqlite3.so.0` on Linux. When the library is missing, `open` returns `nil, "sqlite3 shared library not found"`.

# Module API

## open

`sqlite3.open(Filename)` is the only function of the module. It returns a [Database object](#database-objects), or `nil, ErrorString` on error:

```lua
local Database, ErrorString = sqlite3.open(":memory:")
if (not Database) then
  error(ErrorString)
end
```

Notes
- `sqlite3.open` is a wrapper around [sqlite3_open](https://sqlite.org/c3ref/open.html), so names like `":memory:"` work
- The database file is created when it does not exist
- An invalid path returns `nil, "unable to open database file"`

# Database objects

## Database methods

| Method                         | Description                                                             |
|--------------------------------|-------------------------------------------------------------------------|
| `raiseonerror(Enabled)`        | Raise errors instead of returning a status                              |
| `setbusytimeout(Milliseconds)` | Set the wait time for a locked database, in milliseconds                |
| `exec(SqlString)`              | Execute SQL statements. Returns `Success, ErrorString`                  |
| `prepare(SqlString)`           | Compile an SQL statement. Returns `Statement, ErrorString`              |
| `transaction(Function, ...)`   | Run `Function` in a transaction. Returns `Success, ErrorString, Result` |
| `getlastrowid()`               | Rowid of the most recent successful INSERT                              |
| `getchanges()`                 | Number of rows modified by the most recent INSERT, UPDATE or DELETE     |
| `getlasterror()`               | Error string matching the last result code                              |
| `close()`                      | Close the database                                                      |

## Error handling

### Default mode

Returning errors is the default. Check the return value of every call:

```lua
local Success, ErrorString = Database:exec("CREATE TABLE users (id INTEGER PRIMARY KEY)")
if (not Success) then
  error(ErrorString)
end

local Statement, ErrorString = Database:prepare("SELECT * FROM users")
if (not Statement) then
  error(ErrorString)
end

local StatusString, StatusInteger = Statement:step()
if (StatusString == "ERROR") then
  local ErrorString = Database:getlasterror()
  error(ErrorString)
end
```

Checking every call can be verbose.

### Raising mode

In this mode, failing calls raise an error instead of returning a status. Error handling can then be centralized in one [`pcall`](https://www.lua.org/manual/5.5/manual.html#pdf-pcall):

```lua
Database:raiseonerror(true)

local function InsertRows (Database)
  Database:exec("INSERT INTO users VALUES (1, 'user-1',  3, NULL)")
  Database:exec("INSERT INTO users VALUES (2, 'user-2', 12, NULL)")
  Database:exec("INSERT INTO users VALUES (3, 'user-3',  7, NULL)")
end

local Success, ErrorString = pcall(InsertRows, Database)
if (not Success) then
  print(string.format("insert failed: %s", ErrorString))
end
```

`Database:raiseonerror(false)` returns to the [default mode](#default-mode).

## Busy timeout

When the database is locked, calls fail with `SQLITE_BUSY`. `setbusytimeout(Milliseconds)` gives SQLite enough time to [wait for the lock](https://sqlite.org/c3ref/busy_timeout.html) instead of failing immediately:

```lua
Database:setbusytimeout(5000)
```

`setbusytimeout` returns a SQLite result code, `0` on success.

## Executing SQL

`exec(SqlString)` runs one or more SQL statements:

```lua
local Success, ErrorString = Database:exec([[
  CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
  INSERT INTO users VALUES (1, 'user-1')
]])
```

Returned rows are ignored. Use a [prepared statement](#preparing-a-statement) to read them.

## Preparing a statement

`prepare(SqlString)` compiles an SQL statement:

```lua
local InsertStatement, ErrorString = Database:prepare("INSERT INTO users VALUES (?, ?, ?, ?)")
if (not InsertStatement) then
  error(ErrorString)
end
```

The returned object is described in [Statement objects](#statement-objects).

## Transactions

`transaction(Function, ...)` runs `Function(...)` between `BEGIN` and `COMMIT`:

```lua
local function InsertRows (Database)
  Database:exec("INSERT INTO users VALUES (1, 'user-1',  3, NULL)")
  Database:exec("INSERT INTO users VALUES (2, 'user-2', 12, NULL)")
  Database:exec("INSERT INTO users VALUES (3, 'user-3',  7, NULL)")
  return "inserted"
end

local Success, ErrorString, Result = Database:transaction(InsertRows, Database)
-- Result is "inserted", the first value returned by the function
```

The transaction commits if `Function` returns normally, and rolls back if an error is raised.

## Connection attributes

| Method           | Returns                                                             |
|------------------|---------------------------------------------------------------------|
| `getlastrowid()` | Rowid of the most recent successful INSERT                          |
| `getchanges()`   | Number of rows modified by the most recent INSERT, UPDATE or DELETE |
| `getlasterror()` | Error string matching the last result code                          |

`getlasterror()` returns the error string matching the last [result code](https://sqlite.org/rescode.html). The function can return `nil`, because not every result code has a corresponding string. In some SQLite builds, the string for `SQLITE_OK` is `"not an error"`.

## Closing

```lua
Database:close() -- returns nothing
```

# Statement objects

## Statement methods

| Method                    | Description                                      |
|---------------------------|--------------------------------------------------|
| `getcount()`              | Number of result columns                         |
| `getname(Index)`          | Name of a result column                          |
| `settext(Index, Value)`   | Bind a TEXT value. `nil` binds NULL              |
| `setint(Index, Value)`    | Bind an INTEGER value                            |
| `setdouble(Index, Value)` | Bind a REAL value                                |
| `setblob(Index, Value)`   | Bind a BLOB value (raw bytes)                    |
| `setnull(Index)`          | Bind NULL                                        |
| `step()`                  | Execute the statement or move to the next row    |
| `reset()`                 | Rewind the statement for re-execution            |
| `gettype(Index)`          | Type of the value in the current row             |
| `getbytes(Index)`         | Byte length of the value in the current row      |
| `gettext(Index)`          | TEXT value in the current row, or `nil` for NULL |
| `getint(Index)`           | INTEGER value in the current row                 |
| `getdouble(Index)`        | REAL value in the current row                    |
| `getblob(Index)`          | BLOB bytes in the current row, or `nil` for NULL |

All `Index` arguments are **1-based**.

## Introspection

Right after `prepare`, retrieve the column names:

```lua
local SelectStatement = Database:prepare("SELECT name, score FROM users")

local ColumnCount = SelectStatement:getcount()

for Index = 1, ColumnCount do
  print(SelectStatement:getname(Index))
end
```

## Binding parameters

The setters bind the parameters, starting at 1:

```lua
local InsertStatement = Database:prepare("INSERT INTO users VALUES (?, ?, ?, ?)")

InsertStatement:setint(1, 5)               -- id
InsertStatement:settext(2, "user-5")       -- name
InsertStatement:setint(3, 5)               -- score
InsertStatement:setblob(4, "\xC0\xFF\xEE") -- data
```

Notes
- Each call returns a SQLite result code, `0` on success
- An index out of range returns `25` (`SQLITE_RANGE`)
- `settext(Index, nil)` binds NULL

## Stepping

`step()` executes the statement or moves to the next row:

```lua
local StatusString, StatusInteger = SelectStatement:step()
```

| StatusString | StatusInteger                                             | Meaning                                   |
|--------------|-----------------------------------------------------------|-------------------------------------------|
| `"ROW"`      | [SQLITE_ROW (100)](https://sqlite.org/rescode.html#row)   | A row is ready to read                    |
| `"DONE"`     | [SQLITE_DONE (101)](https://sqlite.org/rescode.html#done) | No more rows, stop iterating              |
| `"BUSY"`     | [SQLITE_BUSY (5)](https://sqlite.org/rescode.html#busy)   | Database locked                           |
| `"ERROR"`    | [Any SQLite error code](https://sqlite.org/rescode.html)  | Failure, see `getlasterror()`             |

`StatusInteger` is the raw code returned by SQLite.

| Statement              | `step()` calls                     |
| ---------------------- | ---------------------------------- |
| `SELECT`               | `"ROW"` per row, then `"DONE"`     |
| `INSERT`               | `"DONE"`                           |
| `INSERT` + `RETURNING` | `"ROW"` per returned row, `"DONE"` |

## Reading rows

Use `gettype(Index)` to choose the accessor:

| Type        | Accessor    | Lua value       | Comment                                              |
|-------------|-------------|-----------------|------------------------------------------------------|
| `"integer"` | `getint`    | number          | 64-bit                                               |
| `"float"`   | `getdouble` | number          |                                                      |
| `"text"`    | `gettext`   | string          | `gettext` on a number returns its textual form       |
| `"blob"`    | `getblob`   | string (binary) | `getbytes` returns its size in bytes                 |
| `"null"`    | n/a         | `nil` or `0`    | `gettext` and `getblob` return `nil`, the others `0` |

These accessors are only valid after `step()` returned `"ROW"`:

```lua
while (SelectStatement:step() == "ROW") do
  local ValueType = SelectStatement:gettype(1)
  if (ValueType == "integer") then
    print(SelectStatement:getint(1))
  elseif (ValueType == "float") then
    print(SelectStatement:getdouble(1))
  else
    print(SelectStatement:gettext(1))
  end
end
```

## Reusing a statement

Following [SQLite semantics](https://sqlite.org/c3ref/reset.html), `reset()` keeps the previously bound values:

```lua
local InsertStatement = Database:prepare("INSERT INTO users (id, name) VALUES (?, ?)")
InsertStatement:settext(2, "default-name")

for Id = 1, 3 do
  InsertStatement:setint(1, Id)
  InsertStatement:step()
  InsertStatement:reset()
end
```
