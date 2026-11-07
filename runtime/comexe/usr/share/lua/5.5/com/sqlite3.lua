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
--   local sqlite3  = require("com.sqlite3")
--   local database = sqlite3.open("test.db")
--   database:setbusytimeout(5000)
--   database:exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
--   database:exec("INSERT INTO users VALUES (1, 'Alice')")
--
--   -- Prepared statement with bind parameters
--   local statement = database:prepare("INSERT INTO users VALUES (?, ?)")
--   statement:setint(1, 2)
--   statement:settext(2, "Bob")
--   statement:step()
--   statement:reset()

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi = require("com.ffi")

local NULL         = libffi.NULL
local pointer      = libffi.pointer
local derefpointer = libffi.derefpointer

--------------------------------------------------------------------------------
-- FFI IMPORTS                                                                --
--------------------------------------------------------------------------------

-- @BEGIN FfiHeader("BindLibrary", "libffi", "sqlite3.h")
-- @OUTPUT
-- Constants
local SQLITE_BLOB = 4
local SQLITE_BUSY = 5
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
local sqlite3_busy_timeout
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
  sqlite3_busy_timeout = Library:bind(libffi.sint32, "sqlite3_busy_timeout", libffi.pointer, libffi.sint32)
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

-- sqlite3_prepare_v2 returns values through pointer to pointers
local SharedPointerArray = libffi.newarray(pointer, 1)
local SharedPointer      = SharedPointerArray:getpointer()

--------------------------------------------------------------------------------
-- STATEMENT TYPE                                                             --
--------------------------------------------------------------------------------

-- sqlite3_step return a 32-bit error code
-- Primary error code is lower 8 bits
-- Extended error codes are (primary | (extended << 8))
--
-- This Lua interface just focus on primary error codes
-- The STATEMENT_Step return the most important ones as a string
-- And always return the integer value
--
-- sqlite3_step returns only SQLITE_ROW (100), SQLITE_DONE (101), or an error code
local function STATEMENT_Step (Statement)
  -- local data
  local StatusInteger = sqlite3_step(Statement.Pointer)
  local PrimaryCode   = (StatusInteger & 0xFF)
  local StatusString
  if (PrimaryCode == SQLITE_ROW) then
    StatusString = "ROW"
  elseif (PrimaryCode == SQLITE_DONE) then
    StatusString = "DONE"
  elseif (PrimaryCode == SQLITE_BUSY) then
    StatusString = "BUSY"
  else
    StatusString = "ERROR"
  end
  -- Raise error if requested
  if (StatusString ~= "DONE") and (StatusString ~= "ROW") then
    local Database = Statement.Database
    if (Database.RaiseOnError) then
      local ErrorString = (sqlite3_errmsg(Database.Pointer) or "unknown")
      error(string.format("step failed (%d): %s", StatusInteger, ErrorString), 2)
    end
  end
  -- Return value
  return StatusString, StatusInteger
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

local function STATEMENT_ColumnBytes (Statement, ColumnIndex)
  return sqlite3_column_bytes(Statement.Pointer, (ColumnIndex - 1))
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

local function STATEMENT_BindBlob (Statement, ParameterIndex, Value)
  return sqlite3_bind_blob(Statement.Pointer, ParameterIndex, Value, #Value, SQLITE_TRANSIENT)
end

local function STATEMENT_BindNull (Statement, ParameterIndex)
  return sqlite3_bind_null(Statement.Pointer, ParameterIndex)
end

local STATEMENT_METATABLE = {
  -- METATABLE_LuaDefinedMethods
  __gc = STATEMENT_CollectGarbage,
  -- METATABLE_UserDefinedMethods
  __index = {
    step      = STATEMENT_Step,         -- Statement
    reset     = STATEMENT_Reset,        -- Statement
    getcount  = STATEMENT_ColumnCount,  -- Statement
    getname   = STATEMENT_ColumnName,   -- Statement
    gettype   = STATEMENT_ColumnType,   -- Current row (step)
    getbytes  = STATEMENT_ColumnBytes,  -- Current row (step)
    gettext   = STATEMENT_ColumnText,   -- Current row (step)
    getint    = STATEMENT_ColumnInt,    -- Current row (step)
    getdouble = STATEMENT_ColumnDouble, -- Current row (step)
    getblob   = STATEMENT_ColumnBlob,   -- Current row (step)
    settext   = STATEMENT_BindText,     -- Parameter binding
    setint    = STATEMENT_BindInt,      -- Parameter binding
    setdouble = STATEMENT_BindDouble,   -- Parameter binding
    setblob   = STATEMENT_BindBlob,     -- Parameter binding
    setnull   = STATEMENT_BindNull,     -- Parameter binding
  }
}

--------------------------------------------------------------------------------
-- DATABASE TYPE                                                              --
--------------------------------------------------------------------------------

local function DATABASE_Exec (Database, SqlString)
  -- Execute SQL string
  local Result = sqlite3_exec(Database.Pointer, SqlString, NULL, NULL, NULL)
  local Success
  local ErrorString
  if (Result == SQLITE_OK) then
    Success = true
  else
    Success     = false
    ErrorString = (sqlite3_errmsg(Database.Pointer) or "unknown")
    -- Raise on failure if requested
    if Database.RaiseOnError then
      error(ErrorString, 2)
    end
  end
  return Success, ErrorString
end

local function DATABASE_Prepare (Database, SqlString)
  -- Retrieve data
  local DatabasePointer = Database.Pointer
  -- Prepare statement
  local Result = sqlite3_prepare_v2(DatabasePointer, SqlString, -1, SharedPointer, NULL)
  local NewStatement
  local ErrorString
  -- Interpret result
  if (Result == SQLITE_OK) then
    -- Read the output pointer
    local StatementPointer = derefpointer(SharedPointer)
    -- Create statement object
    NewStatement = {
      Database = Database,
      Pointer  = StatementPointer,
    }
    -- Attach metatable
    setmetatable(NewStatement, STATEMENT_METATABLE)
  else
    ErrorString = (sqlite3_errmsg(DatabasePointer) or "unknown")
    -- Raise on failure if requested
    if Database.RaiseOnError then
      error(ErrorString, 2)
    end
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

local function DATABASE_SetBusyTimeout (Database, TimeoutMilliseconds)
  return sqlite3_busy_timeout(Database.Pointer, TimeoutMilliseconds)
end

local function DATABASE_RaiseOnError (Database, Enabled)
  Database.RaiseOnError = Enabled
end

-- This is a helper for transactions. Transactions are verbose to handle,
-- because there is an exec("BEGIN TRANSACTION") where we need to handle the
-- errors, then the steps and then finally the exec("COMMIT") or
-- exec("ROLLBACK")
--
-- DATABASE_Transaction does NOT call DATABASE_Exec on purpose
--
-- If function raise an error, the work will be ROLLBACK
-- If not the transaction will be COMMIT
--
-- This function returns: Success, ErrorString, Result
--
-- Result is user callback return value, verbatim: false, nil, true any value
-- returned by the callback will be retrievable here (don't support multiple
-- values, just return the first value)

local function DATABASE_Transaction (Database, Function, ...)
  -- Local data
  local DatabasePointer = Database.Pointer
  local Result
  local ErrorString
  -- Run the work inside the transaction
  if (sqlite3_exec(DatabasePointer, "BEGIN", NULL, NULL, NULL) ~= SQLITE_OK) then
    ErrorString = (sqlite3_errmsg(DatabasePointer) or "unknown")
  else
    local CallSuccess, CallResult = pcall(Function, ...)
    if (not CallSuccess) then
      ErrorString = CallResult
      sqlite3_exec(DatabasePointer, "ROLLBACK", NULL, NULL, NULL)
    elseif (sqlite3_exec(DatabasePointer, "COMMIT", NULL, NULL, NULL) ~= SQLITE_OK) then
      ErrorString = (sqlite3_errmsg(DatabasePointer) or "unknown")
      sqlite3_exec(DatabasePointer, "ROLLBACK", NULL, NULL, NULL)
    else
      Result = CallResult
    end
  end
  -- Raise on failure if requested
  if ErrorString and Database.RaiseOnError then
    error(ErrorString, 0)
  end
  -- Evaluate success
  local Success = (ErrorString == nil)
  -- Return values
  return Success, ErrorString, Result
end

local DATABASE_METATABLE = {
  -- METATABLE_LuaDefinedMethods
  __gc = DATABASE_Close,
  -- METATABLE_UserDefinedMethods
  __index = {
    exec           = DATABASE_Exec,
    prepare        = DATABASE_Prepare,
    transaction    = DATABASE_Transaction,
    close          = DATABASE_Close,
    getlasterror   = DATABASE_GetLastError,
    getlastrowid   = DATABASE_LastInsertRowid,
    getchanges     = DATABASE_Changes,
    setbusytimeout = DATABASE_SetBusyTimeout,
    raiseonerror   = DATABASE_RaiseOnError,
  }
}

--------------------------------------------------------------------------------
-- OPEN DATABASE                                                              --
--------------------------------------------------------------------------------

local function OpenDatabase (Filename)
  -- local data
  local NewDatabase
  local ErrorString
  -- sqlite3_prepare_v2 returns values through pointer to pointers
  local Result          = sqlite3_open(Filename, SharedPointer)
  local DatabasePointer = derefpointer(SharedPointer)
  -- Interpret result
  if (Result == SQLITE_OK) then
    -- Create database object
    NewDatabase = {
      Pointer      = DatabasePointer,
      RaiseOnError = false,
    }
    -- Attach metatable
    setmetatable(NewDatabase, DATABASE_METATABLE)
  elseif (DatabasePointer ~= NULL) then
    -- sqlite3_open can create a connection even when it fails
    ErrorString = sqlite3_errmsg(DatabasePointer)
    sqlite3_close(DatabasePointer)
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
