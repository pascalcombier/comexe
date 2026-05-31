--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- This module provides a high-level interface to SQLite3 using the FFI layer.
--
-- The shared library is loaded on the first call to open(). If the library is
-- not found, open() returns nil and an error message.
--
-- Database
--   Open a database and provides methods to execute SQL and prepare statements.
--
-- Statement
--   Represents a prepared SQL statement with methods to bind parameters,
--   execute, and retrieve results. Column indices are 1-based.
--
-- Example:
--   local sqlite3  = require("tiny-sqlite3")
--   local database = sqlite3.open("test.db")
--   database:exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
--   database:exec("INSERT INTO users VALUES (1, 'Alice')")

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local ffi = require("com.ffi")

local format  = string.format
local NULL    = ffi.NULL
local pointer = ffi.pointer

-- sqlite3_bind_text 5th parameter: SQLITE_STATIC (0) vs SQLITE_TRANSIENT (-1)
-- SQLITE_TRANSIENT tells SQLite to copy the string immediately
local SQLITE_TRANSIENT = ffi.newpointer(0xFFFFFFFF, 0xFFFFFFFF)

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local Sqlite
local COLUMN_TYPE_NAME

--------------------------------------------------------------------------------
-- STATEMENT TYPE                                                             --
--------------------------------------------------------------------------------

local function STATEMENT_Step (Statement)
  -- local data
  local Result = Sqlite.sqlite3_step(Statement.Pointer)
  local Success
  local Status
  -- Interpret result code
  if (Result == Sqlite.SQLITE_ROW) then
    Success = true
    Status  = "ROW"
  elseif (Result == Sqlite.SQLITE_DONE) then
    Success = true
    Status  = "DONE"
  elseif (Result == Sqlite.SQLITE_OK) then
    Success = true
    Status  = "OK"
  else
    Success = false
    Status  = Sqlite.sqlite3_errmsg(Statement.Database.Pointer)
  end
  -- Return value
  return Success, Status
end

local function STATEMENT_Reset (Statement)
  return Sqlite.sqlite3_reset(Statement.Pointer)
end

local function STATEMENT_CollectGarbage (Statement)
  local StatementPointer = Statement.Pointer
  if StatementPointer then
    Sqlite.sqlite3_finalize(StatementPointer)
    Statement.Pointer  = nil
    Statement.Database = nil
  end
end

local function STATEMENT_ColumnCount (Statement)
  return Sqlite.sqlite3_column_count(Statement.Pointer)
end

local function STATEMENT_ColumnName (Statement, ColumnIndex)
  return Sqlite.sqlite3_column_name(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnType (Statement, ColumnIndex)
  local ColumnType     = Sqlite.sqlite3_column_type(Statement.Pointer, (ColumnIndex - 1))
  local ColumnTypeName = COLUMN_TYPE_NAME[ColumnType]
  return ColumnTypeName
end

local function STATEMENT_ColumnText (Statement, ColumnIndex)
  return Sqlite.sqlite3_column_text(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnInt (Statement, ColumnIndex)
  return Sqlite.sqlite3_column_int64(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnDouble (Statement, ColumnIndex)
  return Sqlite.sqlite3_column_double(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnBytes (Statement, ColumnIndex)
  return Sqlite.sqlite3_column_bytes(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnBlob (Statement, ColumnIndex)
  local PointerOffset    = (ColumnIndex - 1)
  local StatementPointer = Statement.Pointer
  local Result
  if (Sqlite.sqlite3_column_type(StatementPointer, PointerOffset) ~= Sqlite.SQLITE_NULL) then
    local ByteCount = Sqlite.sqlite3_column_bytes(StatementPointer, PointerOffset)
    if (ByteCount > 0) then
      local BlobPointer = Sqlite.sqlite3_column_blob(StatementPointer, PointerOffset)
      Result = ffi.readmemory(BlobPointer, 0, ByteCount)
    else
      Result = ""
    end
  end
  return Result
end

local function STATEMENT_BindText (Statement, ParameterIndex, Value)
  local Result
  if Value then
    Result = Sqlite.sqlite3_bind_text(Statement.Pointer, ParameterIndex, Value, #Value, SQLITE_TRANSIENT)
  else
    Result = Sqlite.sqlite3_bind_text(Statement.Pointer, ParameterIndex, NULL, 0, SQLITE_TRANSIENT)
  end
  return Result
end

local function STATEMENT_BindInt (Statement, ParameterIndex, Value)
  return Sqlite.sqlite3_bind_int64(Statement.Pointer, ParameterIndex, Value)
end

local function STATEMENT_BindDouble (Statement, ParameterIndex, Value)
  return Sqlite.sqlite3_bind_double(Statement.Pointer, ParameterIndex, Value)
end

local function STATEMENT_BindNull (Statement, ParameterIndex)
  return Sqlite.sqlite3_bind_null(Statement.Pointer, ParameterIndex)
end

local function STATEMENT_BindBlob (Statement, ParameterIndex, Value)
  return Sqlite.sqlite3_bind_blob(Statement.Pointer, ParameterIndex, Value, #Value, SQLITE_TRANSIENT)
end

local STATEMENT_METATABLE = {
  -- METATABLE_LuaDefinedMethods
  __gc = STATEMENT_CollectGarbage,
  -- METATABLE_UserDefinedMethods
  __index = {
    Step         = STATEMENT_Step,
    Reset        = STATEMENT_Reset,
    ColumnCount  = STATEMENT_ColumnCount,
    ColumnName   = STATEMENT_ColumnName,
    ColumnText   = STATEMENT_ColumnText,
    ColumnInt    = STATEMENT_ColumnInt,
    ColumnDouble = STATEMENT_ColumnDouble,
    ColumnType   = STATEMENT_ColumnType,
    ColumnBytes  = STATEMENT_ColumnBytes,
    ColumnBlob   = STATEMENT_ColumnBlob,
    BindText     = STATEMENT_BindText,
    BindBlob     = STATEMENT_BindBlob,
    BindInt      = STATEMENT_BindInt,
    BindDouble   = STATEMENT_BindDouble,
    BindNull     = STATEMENT_BindNull,
  }
}

--------------------------------------------------------------------------------
-- DATABASE TYPE                                                              --
--------------------------------------------------------------------------------

local function DATABASE_Exec (Database, SqlString)
  -- Execute SQL string
  local Result = Sqlite.sqlite3_exec(Database.Pointer, SqlString, NULL, NULL, NULL)
  local Success
  local ErrorMessage
  if (Result == Sqlite.SQLITE_OK) then
    Success = true
  else
    Success      = false
    ErrorMessage = Sqlite.sqlite3_errmsg(Database.Pointer)
  end
  return Success, ErrorMessage
end

local function DATABASE_Prepare (Database, SqlString)
  -- Retrieve data
  local DatabasePointer = Database.Pointer
  local PointerArray    = Database.PointerArray
  -- Prepare statement
  local Result = Sqlite.sqlite3_prepare_v2(DatabasePointer, SqlString, -1, PointerArray:getpointer(), NULL)
  local NewStatement
  local ErrorString
  -- Interpret result
  if (Result == Sqlite.SQLITE_OK) then
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
    ErrorString = Sqlite.sqlite3_errmsg(DatabasePointer)
  end
  -- Return value
  return NewStatement, ErrorString
end

local function DATABASE_Close (Database)
  local DatabasePointer = Database.Pointer
  if DatabasePointer then
    Sqlite.sqlite3_close(DatabasePointer)
    Database.Pointer = nil
  end
end

local function DATABASE_GetLastError (Database)
  return Sqlite.sqlite3_errmsg(Database.Pointer)
end

local function DATABASE_LastInsertRowid (Database)
  return Sqlite.sqlite3_last_insert_rowid(Database.Pointer)
end

local function DATABASE_Changes (Database)
  return Sqlite.sqlite3_changes(Database.Pointer)
end

local DATABASE_METATABLE = {
  -- METATABLE_LuaDefinedMethods
  __gc = DATABASE_Close,
  -- METATABLE_UserDefinedMethods
  __index = {
    exec            = DATABASE_Exec,
    prepare         = DATABASE_Prepare,
    close           = DATABASE_Close,
    lastError       = DATABASE_GetLastError,
    lastInsertRowid = DATABASE_LastInsertRowid,
    changes         = DATABASE_Changes,
  }
}

--------------------------------------------------------------------------------
-- OPEN DATABASE                                                              --
--------------------------------------------------------------------------------

local function OpenDatabase (Filename)
  -- local data
  local NewDatabase
  local ErrorString
  -- Allocate pointer array for sqlite3_open output
  local PointerArray = ffi.newarray(pointer, 1)
  local Result       = Sqlite.sqlite3_open(Filename, PointerArray:getpointer())
  -- Interpret result
  if (Result == Sqlite.SQLITE_OK) then
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

--------------------------------------------------------------------------------
-- DLL INITIALIZATION                                                         --
--------------------------------------------------------------------------------

local function InitializeDll ()
  -- Load shared library
  local NewSqlite = ffi.loadlib("windows", "sqlite3.dll", "linux", "libsqlite3.so.0")
  -- Error handling
  local ErrorString
  if NewSqlite then
    -- Load bindings generated from tiny-sqlite.h
    NewSqlite:load("tiny-sqlite3-ffi")
    -- Build the type name map
    COLUMN_TYPE_NAME = {
      [NewSqlite.SQLITE_INTEGER] = "integer",
      [NewSqlite.SQLITE_FLOAT]   = "float",
      [NewSqlite.SQLITE_TEXT]    = "text",
      [NewSqlite.SQLITE_BLOB]    = "blob",
      [NewSqlite.SQLITE_NULL]    = "null",
    }
  else
    ErrorString = "sqlite3 shared library not found"
  end
  -- Return value
  return NewSqlite, ErrorString
end

--------------------------------------------------------------------------------
-- INITIALIZATION                                                             --
--------------------------------------------------------------------------------

local function OpenDllAndOpenDatabase (Filename)
  local NewDatabase
  local ErrorString
  -- Initialize the DLL if necessary and store reference to global Sqlite
  if (not Sqlite) then
    Sqlite, ErrorString = InitializeDll()
  end
  -- Open the database
  if Sqlite then
    NewDatabase, ErrorString = OpenDatabase(Filename)
  end
  -- Return values
  return NewDatabase, ErrorString
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  open = OpenDllAndOpenDatabase,
}

return PUBLIC_API
