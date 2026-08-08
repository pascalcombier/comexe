/* Constants */
#define SQLITE_OK 0
#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_INTEGER 1
#define SQLITE_FLOAT 2
#define SQLITE_TEXT 3
#define SQLITE_BLOB 4
#define SQLITE_NULL 5
/* Opening / closing */
int sqlite3_open(const char *filename, void **ppDb);
int sqlite3_close(void *db);
/* Statements */
int sqlite3_exec(void *db, const char *sql, void *callback, void *arg, void **errmsg);
int sqlite3_prepare_v2(void *db, const char *zSql, int nByte, void **ppStmt, void **pzTail);
int sqlite3_step(void *pStmt);
int sqlite3_reset(void *pStmt);
int sqlite3_finalize(void *pStmt);
int sqlite3_column_count(void *pStmt);
int sqlite3_column_type(void *pStmt, int iCol);
const char *sqlite3_column_name(void *pStmt, int N);
const char *sqlite3_column_text(void *pStmt, int iCol);
int sqlite3_column_bytes(void *pStmt, int iCol);
const void *sqlite3_column_blob(void *pStmt, int iCol);
int64_t sqlite3_column_int64(void *pStmt, int iCol);
double sqlite3_column_double(void *pStmt, int iCol);
int sqlite3_bind_text(void *pStmt, int index, const char *val, int n, void *destructor);
int sqlite3_bind_blob(void *pStmt, int index, const void *val, int n, void *destructor);
int sqlite3_bind_int64(void *pStmt, int index, int64_t val);
int sqlite3_bind_double(void *pStmt, int index, double val);
int sqlite3_bind_null(void *pStmt, int index);
int64_t sqlite3_last_insert_rowid(void *db);
int sqlite3_changes(void *db);
/* Error handling */
const char *sqlite3_errmsg(void *db);
