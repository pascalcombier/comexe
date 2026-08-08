# Using the FFI to wrap a C library

* [Introduction](#introduction)
* [Gathering the needed functions into a C header](#gathering-the-needed-functions-into-a-c-header)
  * [Opening and closing](#opening-and-closing)
  * [Executing SQL code](#executing-sql-code)
  * [Compiled statements](#compiled-statements)
  * [Handling errors](#handling-errors)
  * [Generating the bindings](#generating-the-bindings)
* [Implementing the high-level interface](#implementing-the-high-level-interface)
  * [Module architecture](#module-architecture)
  * [Using the generated SQLite binding](#using-the-generated-sqlite-binding)
  * [Opening the database](#opening-the-database)
  * [Executing SQL statements](#executing-sql-statements)
  * [Creating statements](#creating-statements)
  * [Statements introspection](#statements-introspection)
  * [Reading values](#reading-values)
  * [Writing values](#writing-values)
  * [Reading and writing blobs](#reading-and-writing-blobs)
  * [Retrieving error messages](#retrieving-error-messages)
  * [Closing the database](#closing-the-database)
* [Full listing](#full-listing)

# Introduction

The purpose of this guide is to show how to use the [ffi API](./comexe-reference-ffi.md) to build a small but viable SQLite layer:

- Opening and closing SQLite files
- Executing SQL code
- Using compiled statements
- Handling errors

# Gathering the needed functions into a C header

Select the minimal set of functions needed.

## Opening and closing

```c
int sqlite3_open  (const char *filename, void **ppDb);
int sqlite3_close (void *db);
```

## Executing SQL code

```c
int sqlite3_exec (void *db, const char *sql, void *callback, void *arg, void **errmsg);
```

## Compiled statements

Statements serve two purposes:
- Reading data, from a `SELECT` clause
- Writing data, from a `INSERT` clause

```c
/* Common function for statements */
int sqlite3_prepare_v2 (void *db, const char *zSql, int nByte, void **ppStmt, void **pzTail);
int sqlite3_step       (void *pStmt);
int sqlite3_finalize   (void *pStmt);
int sqlite3_reset      (void *pStmt);

/* Read data */
int         sqlite3_column_count (void *pStmt);
const char *sqlite3_column_name  (void *pStmt, int N);
int         sqlite3_column_type  (void *pStmt, int iCol);

const char *sqlite3_column_text   (void *pStmt, int iCol);
int         sqlite3_column_bytes  (void *pStmt, int iCol);
const void *sqlite3_column_blob   (void *pStmt, int iCol);
int64_t     sqlite3_column_int64  (void *pStmt, int iCol);
double      sqlite3_column_double (void *pStmt, int iCol);

/* Write data */
int sqlite3_bind_text   (void *pStmt, int index, const char *val, int n, void *destructor);
int sqlite3_bind_blob   (void *pStmt, int index, const void *val, int n, void *destructor);
int sqlite3_bind_int64  (void *pStmt, int index, int64_t val);
int sqlite3_bind_double (void *pStmt, int index, double val);
int sqlite3_bind_null   (void *pStmt, int index);

int64_t sqlite3_last_insert_rowid (void *db);
int     sqlite3_changes           (void *db);
```

## Handling errors

```c
#define SQLITE_OK     0
#define SQLITE_ROW  100
#define SQLITE_DONE 101

const char *sqlite3_errmsg (void *db);
```

## Generating the bindings

The declarations are collected into the header [sqlite3.h](../runtime/comexe/usr/share/lua/5.5/com/sqlite3.h). Then some boilerplate code is required to generate the FFI code.

**[sqlite3.lua](../runtime/comexe/usr/share/lua/5.5/com/sqlite3.lua)**

```lua
-- @BEGIN FfiHeader("BindLibrary", "libffi", "sqlite3.h")
-- @OUTPUT
-- @END
```

The [preprocessor](./comexe-reference-preprocessor.md) generates the code making `C` functions callable from Lua:

```console
lua55ce.exe -x --preprocess runtime/comexe/usr/share/lua/5.5/com/sqlite3.lua
```

The block now contains the generated bindings:

```lua
-- @BEGIN FfiHeader("BindLibrary", "libffi", "sqlite3.h")
-- @OUTPUT
-- Constants
local SQLITE_BLOB = 4
local SQLITE_DONE = 101
local SQLITE_FLOAT = 2
local SQLITE_INTEGER = 1
local SQLITE_NULL = 5
local SQLITE_OK = 0
local SQLITE_ROW = 100
local SQLITE_TEXT = 3
-- Functions
local sqlite3_bind_blob
local sqlite3_bind_double
local sqlite3_bind_int64
local sqlite3_bind_null
local sqlite3_bind_text
local sqlite3_changes
local sqlite3_close
local sqlite3_column_blob
local sqlite3_column_bytes
local sqlite3_column_count
local sqlite3_column_double
local sqlite3_column_int64
local sqlite3_column_name
local sqlite3_column_text
local sqlite3_column_type
local sqlite3_errmsg
local sqlite3_exec
local sqlite3_finalize
local sqlite3_last_insert_rowid
local sqlite3_open
local sqlite3_prepare_v2
local sqlite3_reset
local sqlite3_step
-- Binding function
local function BindLibrary (Library)
  sqlite3_bind_blob = Library:bind(libffi.sint32, "sqlite3_bind_blob", libffi.pointer, libffi.sint32, libffi.pointer, libffi.sint32, libffi.pointer)
  sqlite3_bind_double = Library:bind(libffi.sint32, "sqlite3_bind_double", libffi.pointer, libffi.sint32, libffi.double)
  sqlite3_bind_int64 = Library:bind(libffi.sint32, "sqlite3_bind_int64", libffi.pointer, libffi.sint32, libffi.sint64)
  sqlite3_bind_null = Library:bind(libffi.sint32, "sqlite3_bind_null", libffi.pointer, libffi.sint32)
  sqlite3_bind_text = Library:bind(libffi.sint32, "sqlite3_bind_text", libffi.pointer, libffi.sint32, libffi.pointer, libffi.sint32, libffi.pointer)
  sqlite3_changes = Library:bind(libffi.sint32, "sqlite3_changes", libffi.pointer)
  sqlite3_close = Library:bind(libffi.sint32, "sqlite3_close", libffi.pointer)
  sqlite3_column_blob = Library:bind(libffi.pointer, "sqlite3_column_blob", libffi.pointer, libffi.sint32)
  sqlite3_column_bytes = Library:bind(libffi.sint32, "sqlite3_column_bytes", libffi.pointer, libffi.sint32)
  sqlite3_column_count = Library:bind(libffi.sint32, "sqlite3_column_count", libffi.pointer)
  sqlite3_column_double = Library:bind(libffi.double, "sqlite3_column_double", libffi.pointer, libffi.sint32)
  sqlite3_column_int64 = Library:bind(libffi.sint64, "sqlite3_column_int64", libffi.pointer, libffi.sint32)
  sqlite3_column_name = Library:bind(libffi.cstring, "sqlite3_column_name", libffi.pointer, libffi.sint32)
  sqlite3_column_text = Library:bind(libffi.cstring, "sqlite3_column_text", libffi.pointer, libffi.sint32)
  sqlite3_column_type = Library:bind(libffi.sint32, "sqlite3_column_type", libffi.pointer, libffi.sint32)
  sqlite3_errmsg = Library:bind(libffi.cstring, "sqlite3_errmsg", libffi.pointer)
  sqlite3_exec = Library:bind(libffi.sint32, "sqlite3_exec", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer)
  sqlite3_finalize = Library:bind(libffi.sint32, "sqlite3_finalize", libffi.pointer)
  sqlite3_last_insert_rowid = Library:bind(libffi.sint64, "sqlite3_last_insert_rowid", libffi.pointer)
  sqlite3_open = Library:bind(libffi.sint32, "sqlite3_open", libffi.pointer, libffi.pointer)
  sqlite3_prepare_v2 = Library:bind(libffi.sint32, "sqlite3_prepare_v2", libffi.pointer, libffi.pointer, libffi.sint32, libffi.pointer, libffi.pointer)
  sqlite3_reset = Library:bind(libffi.sint32, "sqlite3_reset", libffi.pointer)
  sqlite3_step = Library:bind(libffi.sint32, "sqlite3_step", libffi.pointer)
end
-- @END
```

Note that the SQLite API has two indexing methods, which is unusual for Lua users:

- **0-based indexing** for column functions
- **1-based indexing** for bind parameter functions

# Implementing the high-level interface

The high-level module:

* Automatically open "sqlite3.dll" or "libsqlite3.so"
* Avoid C idioms and use more Lua
  * Object-oriented API instead of raw function calls
  * Automatically release database and statements
  * Use 1-based indexing everywhere

## Module architecture

The module exports a single function:

```lua
local PUBLIC_API = {
  open = OpenDllAndOpenDatabase,
}
```

The function **initializes the DLL on the very first call**:

```lua
local function OpenDllAndOpenDatabase (Filename)
  local NewDatabase
  local ErrorString
  -- Initialize the DLL if necessary
  if (not SqliteLoaded) then
    SqliteLoaded, ErrorString = InitializeDll()
  end
  -- Open the database
  if SqliteLoaded then
    NewDatabase, ErrorString = OpenDatabase(Filename)
  end
  -- Return values
  return NewDatabase, ErrorString
end
```

The module provides two object types:
* **Database objects**, created by `sqlite3.open`
* **Statement objects**, created by `database:prepare`

Each type's behavior is defined in its metatable:

```lua
local DATABASE_METATABLE = {
  -- METATABLE_LuaDefinedMethods
  __gc = DATABASE_Close,
  -- METATABLE_UserDefinedMethods
  __index = {
    exec         = DATABASE_Exec,
    prepare      = DATABASE_Prepare,
    close        = DATABASE_Close,
    getlasterror = DATABASE_GetLastError,
  }
}

local STATEMENT_METATABLE = {
  -- METATABLE_LuaDefinedMethods
  __gc = STATEMENT_CollectGarbage,
  -- METATABLE_UserDefinedMethods
  __index = {
    step      = STATEMENT_Step,
    reset     = STATEMENT_Reset,
    getcount  = STATEMENT_ColumnCount,
    getname   = STATEMENT_ColumnName,
    gettype   = STATEMENT_ColumnType,
    getbytes  = STATEMENT_ColumnBytes,
    gettext   = STATEMENT_ColumnText,
    getint    = STATEMENT_ColumnInt,
    getdouble = STATEMENT_ColumnDouble,
    getblob   = STATEMENT_ColumnBlob,
    settext   = STATEMENT_BindText,
    setint    = STATEMENT_BindInt,
    setdouble = STATEMENT_BindDouble,
    setblob   = STATEMENT_BindBlob,
    setnull   = STATEMENT_BindNull,
  }
}
```

Resources are cleaned up automatically by the garbage collector.

## Using the generated SQLite binding

Load the shared library and use the bindings:

```lua
local libffi = require("com.ffi")

-- @BEGIN FfiHeader("BindLibrary", "libffi", "sqlite3.h")
-- @OUTPUT
-- Constants
local SQLITE_BLOB = 4
local SQLITE_DONE = 101
local SQLITE_FLOAT = 2
local SQLITE_INTEGER = 1
...
-- @END

local SqliteLoaded = false

local function InitializeDll ()
  -- Load shared library
  local NewSqlite = libffi.loadlib("windows", "sqlite3.dll", "linux", "libsqlite3.so.0")
  -- Error handling
  local ErrorString
  if NewSqlite then
    -- Load bindings generated from sqlite3.h
    BindLibrary(NewSqlite)
    -- Build the type name map
    COLUMN_TYPE_NAME = {
      [SQLITE_INTEGER] = "integer",
      [SQLITE_FLOAT]   = "float",
      [SQLITE_TEXT]    = "text",
      [SQLITE_BLOB]    = "blob",
      [SQLITE_NULL]    = "null",
    }
    -- Mark as loaded
    SqliteLoaded = true
  else
    ErrorString = "sqlite3 shared library not found"
  end
  -- Return value
  return SqliteLoaded, ErrorString
end
```

The `COLUMN_TYPE_NAME` is a dictionary that maps C integer type codes to readable strings. This lets `statement:gettype(1)` return "float" or "integer" instead of `SQLITE_FLOAT` or `SQLITE_INTEGER`.

## Opening the database

`sqlite3_open` writes the database handle into `ppDb`:

```c
int sqlite3_open (const char *filename, void **ppDb);
```

To retrieve the handle:

```lua
local PointerArray    = libffi.newarray(libffi.pointer, 1)
local Result          = sqlite3_open(Filename, PointerArray:getpointer())
local DatabasePointer = PointerArray:get(1)
```

The complete function is:

```lua
local function OpenDatabase (Filename)
  -- local data
  local NewDatabase
  local ErrorString
  -- Allocate pointer array for sqlite3_open output
  local PointerArray = libffi.newarray(pointer, 1)
  local Result       = sqlite3_open(Filename, PointerArray:getpointer())
  -- Interpret result
  if (Result == SQLITE_OK) then
    -- Read the output pointer
    local DatabasePointer = PointerArray:get(1)
    -- Create database object
    NewDatabase = {
      PointerArray = PointerArray,
      Pointer      = DatabasePointer,
    }
    -- Attach metatable
    setmetatable(NewDatabase, DATABASE_METATABLE)
  else
    ErrorString = "Failed to open database"
  end
  -- Return value
  return NewDatabase, ErrorString
end
```

Notes:
* `DatabasePointer` is a *copy* (light userdata) of the pointer initially stored in `PointerArray`. If `PointerArray` is released, the copy remains valid.
* `PointerArray` is kept inside `NewDatabase` because `sqlite3_prepare_v2` also takes a `PointerArray` as parameter, so it is reused when calling `sqlite3_prepare_v2`.

## Executing SQL statements

Straight-forward implementation: call the function and check the result.

```lua
local function DATABASE_Exec (Database, SqlString)
  -- Execute SQL string
  local Result = sqlite3_exec(Database.Pointer, SqlString, NULL, NULL, NULL)
  local Success
  local ErrorString
  if (Result == SQLITE_OK) then
    Success = true
  else
    Success      = false
    ErrorString = sqlite3_errmsg(Database.Pointer)
  end
  return Success, ErrorString
end
```

## Creating statements

In `DATABASE_Prepare`, the pointer array created in `OpenDatabase` is reused:

```lua
local function DATABASE_Prepare (Database, SqlString)
  -- Retrieve data
  local DatabasePointer = Database.Pointer
  local PointerArray    = Database.PointerArray
  -- Prepare statement
  local Result = sqlite3_prepare_v2(DatabasePointer, SqlString, -1, PointerArray:getpointer(), NULL)
  local NewStatement
  local ErrorString
  -- Interpret result
  if (Result == SQLITE_OK) then
    -- Read the output pointer
    local StatementPointer = PointerArray:get(1)
    -- Create statement object
    NewStatement = {
      Database = Database,
      Pointer  = StatementPointer,
    }
    -- Attach metatable
    setmetatable(NewStatement, STATEMENT_METATABLE)
  else
    ErrorString = sqlite3_errmsg(DatabasePointer)
  end
  -- Return value
  return NewStatement, ErrorString
end
```

The `nByte` is set to `-1` to tell SQLite that the string is null-terminated. Passing the string length instead would also work.

## Statements introspection

After a `SELECT` query, the result columns can be inspected, **the C column API is 0-based**:

* `Statement:getcount()`: number of columns
* `Statement:getname(N)`: name of column N
* `Statement:gettype(N)`: type of column N as a string

`COLUMN_TYPE_NAME` maps the C integer type codes to readable strings:

| C constant                  | Lua constant |
|-----------------------------|--------------|
| `#define SQLITE_INTEGER  1` | `"integer"`  |
| `#define SQLITE_FLOAT    2` | `"float"`    |
| `#define SQLITE_TEXT     3` | `"text"`     |
| `#define SQLITE_BLOB     4` | `"blob"`     |
| `#define SQLITE_NULL     5` | `"null"`     |

```lua
local function STATEMENT_ColumnCount (Statement)
  return sqlite3_column_count(Statement.Pointer)
end

local function STATEMENT_ColumnName (Statement, ColumnIndex)
  return sqlite3_column_name(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnType (Statement, ColumnIndex)
  local ColumnType     = sqlite3_column_type(Statement.Pointer, (ColumnIndex - 1))
  local ColumnTypeName = COLUMN_TYPE_NAME[ColumnType]
  return ColumnTypeName
end
```

## Reading values

These functions are typically used with `SELECT` queries. **The C column API is 0-based**.

```lua
local function STATEMENT_ColumnText (Statement, ColumnIndex)
  return sqlite3_column_text(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnInt (Statement, ColumnIndex)
  return sqlite3_column_int64(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnDouble (Statement, ColumnIndex)
  return sqlite3_column_double(Statement.Pointer, (ColumnIndex - 1))
end
```

## Writing values

Unlike the C column API, **the C bind API is 1-based**: no adjustment needed here.

```lua
-- sqlite3_bind_text 5th parameter: SQLITE_STATIC (0) vs SQLITE_TRANSIENT (-1)
-- SQLITE_TRANSIENT tells SQLite to copy the string immediately
local SQLITE_TRANSIENT = libffi.newpointer(0xFFFFFFFF, 0xFFFFFFFF)

local function STATEMENT_BindText (Statement, ParameterIndex, Value)
  local StatementPointer = Statement.Pointer
  local Result
  if Value then
    Result = sqlite3_bind_text(StatementPointer, ParameterIndex, Value, #Value, SQLITE_TRANSIENT)
  else
    Result = sqlite3_bind_text(StatementPointer, ParameterIndex, NULL, 0, SQLITE_TRANSIENT)
  end
  return Result
end

local function STATEMENT_BindInt (Statement, ParameterIndex, Value)
  return sqlite3_bind_int64(Statement.Pointer, ParameterIndex, Value)
end

local function STATEMENT_BindDouble (Statement, ParameterIndex, Value)
  return sqlite3_bind_double(Statement.Pointer, ParameterIndex, Value)
end

local function STATEMENT_BindNull (Statement, ParameterIndex)
  return sqlite3_bind_null(Statement.Pointer, ParameterIndex)
end
```

Note that `SQLITE_TRANSIENT` tells SQLite to copy the string immediately. The data is used later when `sqlite3_step` is called, at that time SQLite uses its own copy.

## Reading and writing blobs

`BindText` expects UTF-8 while `BindBlob` handles arbitrary binary data. `sqlite3_column_bytes` gives the byte count. `sqlite3_column_blob` returns raw bytes via `readmemory`.

```lua
local function STATEMENT_ColumnBytes (Statement, ColumnIndex)
  return sqlite3_column_bytes(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnBlob (Statement, ColumnIndex)
  local PointerOffset    = (ColumnIndex - 1)
  local StatementPointer = Statement.Pointer
  local Result
  if (sqlite3_column_type(StatementPointer, PointerOffset) ~= SQLITE_NULL) then
    local ByteCount = sqlite3_column_bytes(StatementPointer, PointerOffset)
    if (ByteCount > 0) then
      local BlobPointer = sqlite3_column_blob(StatementPointer, PointerOffset)
      Result = libffi.readmemory(BlobPointer, 0, ByteCount)
    else
      Result = ""
    end
  end
  return Result
end
```

For **writing**, a binary Lua string is passed to `sqlite3_bind_blob` with its full length.

```lua
local function STATEMENT_BindBlob (Statement, ParameterIndex, Value)
  return sqlite3_bind_blob(Statement.Pointer, ParameterIndex, Value, #Value, SQLITE_TRANSIENT)
end
```

## Retrieving error messages

SQLite provides a useful error message function:

```lua
local function DATABASE_GetLastError (Database)
  return sqlite3_errmsg(Database.Pointer)
end
```

## Closing the database

Called automatically by the garbage collector if the user forgets.

```lua
local function DATABASE_Close (Database)
  local DatabasePointer = Database.Pointer
  if DatabasePointer then
    sqlite3_close(DatabasePointer)
    Database.Pointer = nil
  end
end
```

# Full listing

The complete module is at **[sqlite3.lua](../runtime/comexe/usr/share/lua/5.5/com/sqlite3.lua)**. It is intended to be used with the test **[test-sqlite3.lua](../tests/examples/ffi/test-sqlite3.lua)**
