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
--   local sqlite3  = require("com.ffi.sqlite3")
--   local database = sqlite3.open("test.db")
--   database:exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
--   database:exec("INSERT INTO users VALUES (1, 'Alice')")
--
--   -- Prepared statement with bind parameters
--   local statement = database:prepare("INSERT INTO users VALUES (?, ?)")
--   statement:BindInt(1, 2)
--   statement:BindText(2, "Bob")
--   statement:Step()
--   statement:Reset()

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.ffi")

local NULL    = libffi.NULL
local pointer = libffi.pointer

--------------------------------------------------------------------------------
-- FFI IMPORTS                                                                --
--------------------------------------------------------------------------------

-- @BEGIN import-c-header
-- @PARAM file sqlite3.h
-- @PARAM function BindLibrary
-- @PARAM lib libffi
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

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local SqliteLoaded = false
local COLUMN_TYPE_NAME

-- sqlite3_bind_text 5th parameter: SQLITE_STATIC (0) vs SQLITE_TRANSIENT (-1)
-- SQLITE_TRANSIENT tells SQLite to copy the string immediately
local SQLITE_TRANSIENT = libffi.newpointer(0xFFFFFFFF, 0xFFFFFFFF)

--------------------------------------------------------------------------------
-- STATEMENT TYPE                                                             --
--------------------------------------------------------------------------------

local function STATEMENT_Step (Statement)
  -- local data
  local Result = sqlite3_step(Statement.Pointer)
  local Success
  local Status
  -- Interpret result code
  if (Result == SQLITE_ROW) then
    Success = true
    Status  = "ROW"
  elseif (Result == SQLITE_DONE) then
    Success = true
    Status  = "DONE"
  elseif (Result == SQLITE_OK) then
    Success = true
    Status  = "OK"
  else
    Success = false
    Status  = sqlite3_errmsg(Statement.Database.Pointer)
  end
  -- Return value
  return Success, Status
end

local function STATEMENT_Reset (Statement)
  return sqlite3_reset(Statement.Pointer)
end

local function STATEMENT_CollectGarbage (Statement)
  local StatementPointer = Statement.Pointer
  if StatementPointer then
    sqlite3_finalize(StatementPointer)
    Statement.Pointer  = nil
    Statement.Database = nil
  end
end

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

local function STATEMENT_ColumnText (Statement, ColumnIndex)
  return sqlite3_column_text(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnInt (Statement, ColumnIndex)
  return sqlite3_column_int64(Statement.Pointer, (ColumnIndex - 1))
end

local function STATEMENT_ColumnDouble (Statement, ColumnIndex)
  return sqlite3_column_double(Statement.Pointer, (ColumnIndex - 1))
end

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

local function STATEMENT_BindText (Statement, ParameterIndex, Value)
  local Result
  if Value then
    Result = sqlite3_bind_text(Statement.Pointer, ParameterIndex, Value, #Value, SQLITE_TRANSIENT)
  else
    Result = sqlite3_bind_text(Statement.Pointer, ParameterIndex, NULL, 0, SQLITE_TRANSIENT)
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

local function STATEMENT_BindBlob (Statement, ParameterIndex, Value)
  return sqlite3_bind_blob(Statement.Pointer, ParameterIndex, Value, #Value, SQLITE_TRANSIENT)
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
  local Result = sqlite3_exec(Database.Pointer, SqlString, NULL, NULL, NULL)
  local Success
  local ErrorMessage
  if (Result == SQLITE_OK) then
    Success = true
  else
    Success      = false
    ErrorMessage = sqlite3_errmsg(Database.Pointer)
  end
  return Success, ErrorMessage
end

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

local function DATABASE_Close (Database)
  local DatabasePointer = Database.Pointer
  if DatabasePointer then
    sqlite3_close(DatabasePointer)
    Database.Pointer = nil
  end
end

local function DATABASE_GetLastError (Database)
  return sqlite3_errmsg(Database.Pointer)
end

local function DATABASE_LastInsertRowid (Database)
  return sqlite3_last_insert_rowid(Database.Pointer)
end

local function DATABASE_Changes (Database)
  return sqlite3_changes(Database.Pointer)
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

--------------------------------------------------------------------------------
-- DLL INITIALIZATION                                                         --
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- INITIALIZATION                                                             --
--------------------------------------------------------------------------------

local function OpenDllAndOpenDatabase (Filename)
  local NewDatabase
  local ErrorString
  -- Initialize the DLL if necessary and store reference to global Sqlite
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

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  open = OpenDllAndOpenDatabase,
}

return PUBLIC_API
