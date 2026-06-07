/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-libtcc-module.c                                               *
 * CONTENT  TCC Lua binary module (libtcc.so / libtcc.dll)                    *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/*---------*/
/* HEADERS */
/*---------*/

#include <lua.h>

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <lauxlib.h> /* luaL_Reg             */
#include <lualib.h>  /* luaopen_*            */
#include <stdlib.h>  /* calloc, free, strdup */
#include <stdbool.h> /* bool                 */
#include <string.h>  /* memcpy, strcmp       */
#include <errno.h>   /* errno constants      */
#include <fcntl.h>   /* O_CREAT              */

#include "tcc.h" /* TCCState internal */
#undef free      /* set by tcc.h      */
#undef strdup    /* set by tcc.h      */

/* tcc.h includes libtcc.h, so tcc_new/tcc_compile_string/etc are available */
extern int tcc_main (void *UserData, int argc, char **argv);

/*============================================================================*/
/* PRIVATE MACROS                                                             */
/*============================================================================*/

#define TCC_MIN(a, b) ((a) < (b) ? (a) : (b))

/*============================================================================*/
/* UIO REGISTRY REFS (set at module init)                                     */
/*============================================================================*/

/* Those references are simply optimizations to avoid retrieving global symbol
 * from environment all the time */

static int UIO_open_ref  = LUA_NOREF;
static int UIO_write_ref = LUA_NOREF;
static int UIO_read_ref  = LUA_NOREF;
static int UIO_close_ref = LUA_NOREF;
static int UIO_lseek_ref = LUA_NOREF;
static int UIO_dup_ref   = LUA_NOREF;

/*============================================================================*/
/* UIO I/O functions (LIBTCC BINDINGS)                                        */
/*============================================================================*/

/* Those functions are called from:
 *  libtcc.c
 *  tccpe.c
 *  tccrun.c
 *  etc
 */

int uio_open (TCCState *TccState, const char *pathname, int flags, int mode)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  int        Result;

  lua_rawgeti(LuaState, LUA_REGISTRYINDEX, UIO_open_ref);
  lua_pushstring(LuaState, pathname);
  lua_pushinteger(LuaState, flags);
  lua_pushinteger(LuaState, mode);

  if (lua_pcall(LuaState, 3, 1, 0) == LUA_OK)
  {
    Result = lua_tointeger(LuaState, -1);
    lua_pop(LuaState, 1);
  }
  else
  {
    lua_pop(LuaState, 1);
    Result = -EIO;
  }

  return Result;
}

int uio_write (TCCState *TccState, int fd, const void *buf, unsigned int count)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  int        Result;

  lua_rawgeti(LuaState, LUA_REGISTRYINDEX, UIO_write_ref);
  lua_pushinteger(LuaState, fd);
  lua_pushlstring(LuaState, (const char *)buf, count);

  if (lua_pcall(LuaState, 2, 1, 0) == LUA_OK)
  {
    Result = lua_tointeger(LuaState, -1);
    lua_pop(LuaState, 1);
  }
  else
  {
    lua_pop(LuaState, 1);
    Result = -EIO;
  }

  return Result;
}

int uio_read (TCCState *TccState, int fd, void *buf, unsigned int count)
{
  lua_State   *LuaState = tcc_get_userdata(TccState);
  int          Result;
  const char  *Data;
  size_t       SizeInBytes;

  lua_rawgeti(LuaState, LUA_REGISTRYINDEX, UIO_read_ref);
  lua_pushinteger(LuaState, fd);
  lua_pushinteger(LuaState, count);

  if (lua_pcall(LuaState, 2, 1, 0) == LUA_OK)
  {
    if (lua_isstring(LuaState, -1))
    {
      Data        = lua_tolstring(LuaState, -1, &SizeInBytes);
      SizeInBytes = TCC_MIN(count, SizeInBytes);
      memcpy(buf, Data, SizeInBytes);
      Result = (int)SizeInBytes;
    }
    /* -EBADF, -EIO */
    else if (lua_isnumber(LuaState, -1))
    {
      Result = lua_tointeger(LuaState, -1);
    }
    else
    {
      Result = -EIO;
    }
    lua_pop(LuaState, 1);
  }
  else
  {
    lua_pop(LuaState, 1);
    Result = -EIO;
  }

  return Result;
}

int uio_close (TCCState *TccState, int fd)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  int        Result;

  lua_rawgeti(LuaState, LUA_REGISTRYINDEX, UIO_close_ref);
  lua_pushinteger(LuaState, fd);

  if (lua_pcall(LuaState, 1, 1, 0) == LUA_OK)
  {
    Result = lua_tointeger(LuaState, -1);
    lua_pop(LuaState, 1);
  }
  else
  {
    lua_pop(LuaState, 1);
    Result = -EIO;
  }

  return Result;
}

off_t uio_lseek (TCCState *TccState, int fd, off_t offset, int whence)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  off_t      Result;

  lua_rawgeti(LuaState, LUA_REGISTRYINDEX, UIO_lseek_ref);
  lua_pushinteger(LuaState, fd);
  lua_pushinteger(LuaState, offset);
  lua_pushinteger(LuaState, whence);

  if (lua_pcall(LuaState, 3, 1, 0) == LUA_OK)
  {
    Result = (off_t)lua_tointeger(LuaState, -1);
    lua_pop(LuaState, 1);
  }
  else
  {
    lua_pop(LuaState, 1);
    Result = -ESPIPE;
  }

  return Result;
}

int uio_dup (TCCState *TccState, int fd)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  int        Result;

  lua_rawgeti(LuaState, LUA_REGISTRYINDEX, UIO_dup_ref);
  lua_pushinteger(LuaState, fd);

  if (lua_pcall(LuaState, 1, 1, 0) == LUA_OK)
  {
    Result = lua_tointeger(LuaState, -1);
    lua_pop(LuaState, 1);
  }
  else
  {
    lua_pop(LuaState, 1);
    Result = -EBADF;
  }

  return Result;
}

/*============================================================================*/
/* LIBTCC API FUNCTIONS                                                       */
/*============================================================================*/

static bool STRING_Equals (const char *String1, const char *String2)
{
  return (strcmp(String1, String2) == 0);
}

static int LIBTCC_New (lua_State *LuaState)
{
  TCCState *TccState = tcc_new();

  tcc_set_userdata(TccState, LuaState);

  lua_pushlightuserdata(LuaState, TccState);

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_Delete (lua_State *LuaState)
{
  TCCState *TccState = lua_touserdata(LuaState, 1);

  tcc_delete(TccState);

  return 0; /* No values returned on the stack */
}

static int LIBTCC_SetOutputType (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Type     = lua_tostring(LuaState, 2);
  int         TccType;

  if ((Type == NULL) || STRING_Equals(Type, "memory"))
  {
    TccType = TCC_OUTPUT_MEMORY;
  }
  else if (STRING_Equals(Type, "exe"))
  {
    TccType = TCC_OUTPUT_EXE;
  }
  else if (STRING_Equals(Type, "dll"))
  {
    TccType = TCC_OUTPUT_DLL;
  }
  else if (STRING_Equals(Type, "obj"))
  {
    TccType = TCC_OUTPUT_OBJ;
  }
  else if (STRING_Equals(Type, "preprocess"))
  {
    TccType = TCC_OUTPUT_PREPROCESS;
  }
  else
  {
    TccType = TCC_OUTPUT_MEMORY;
  }

  lua_pushinteger(LuaState, tcc_set_output_type(TccState, TccType));

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_CompileString (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Buffer   = luaL_checkstring(LuaState, 2);

  lua_pushinteger(LuaState, tcc_compile_string(TccState, Buffer));

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_Run (lua_State *LuaState)
{
  TCCState *TccState = lua_touserdata(LuaState, 1);
  int       Argc     = lua_gettop(LuaState) - 1;
  char    **Argv     = NULL;
  int       Offset;
  int       Result;

  if (Argc >= 0)
  {
    Argv = calloc((Argc + 1), sizeof(char *));

    for (Offset = 0; Offset < Argc; Offset++)
    {
      Argv[Offset] = (char *)lua_tostring(LuaState, Offset + 2);
    }
    Argv[Argc] = NULL;

    Result = tcc_run(TccState, Argc, Argv);

    free(Argv);
  }
  else
  {
    Result = -1;
  }

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_Relocate (lua_State *LuaState)
{
  TCCState *TccState = lua_touserdata(LuaState, 1);

  lua_pushinteger(LuaState, tcc_relocate(TccState));

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_GetSymbol (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Name     = luaL_checkstring(LuaState, 2);
  void       *Symbol   = tcc_get_symbol(TccState, Name);

  lua_pushlightuserdata(LuaState, Symbol);

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_AddSymbol (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Name     = luaL_checkstring(LuaState, 2);
  const void *Value    = lua_touserdata(LuaState, 3);

  lua_pushinteger(LuaState, tcc_add_symbol(TccState, Name, Value));

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_AddFile (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Filename = luaL_checkstring(LuaState, 2);

  lua_pushinteger(LuaState, tcc_add_file(TccState, Filename));

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_AddLibraryPath (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Path     = luaL_checkstring(LuaState, 2);

  lua_pushinteger(LuaState, tcc_add_library_path(TccState, Path));

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_AddLibrary (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *LibName  = luaL_checkstring(LuaState, 2);

  lua_pushinteger(LuaState, tcc_add_library(TccState, LibName));

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_DefineSymbol (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Symbol   = luaL_checkstring(LuaState, 2);

  if (lua_isnil(LuaState, 3))
  {
    tcc_define_symbol(TccState, Symbol, NULL);
  }
  else
  {
    tcc_define_symbol(TccState, Symbol, lua_tostring(LuaState, 3));
  }

  return 0; /* No values returned on the stack */
}

static int LIBTCC_UndefineSymbol (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Symbol   = luaL_checkstring(LuaState, 2);

  tcc_undefine_symbol(TccState, Symbol);

  return 0; /* No values returned on the stack */
}

static int LIBTCC_OutputFile (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Filename = luaL_checkstring(LuaState, 2);

  lua_pushinteger(LuaState, tcc_output_file(TccState, Filename));

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_RunTccMain (lua_State *LuaState)
{
  int          Argc = lua_gettop(LuaState);
  char       **Argv = NULL;
  int          Index;
  int          Result;
  const char  *String;

  if (Argc > 0)
  {
    Argv    = calloc((Argc + 2), sizeof(char *));
    Argv[0] = strdup("tcc");

    for (Index = 1; Index <= Argc; Index++)
    {
      if (lua_isstring(LuaState, Index))
      {
        String = lua_tostring(LuaState, Index);
        Argv[Index] = strdup(String);
      }
      else
      {
        Argv[Index] = NULL;
      }
    }
    Argv[Argc + 1] = NULL;

    Result = tcc_main(LuaState, (Argc + 1), Argv);

    for (Index = 0; Index <= Argc; Index++)
    {
      free(Argv[Index]);
    }
    free(Argv);
  }
  else
  {
    char *default_argv[] = { "tcc", NULL };
    Result = tcc_main(LuaState, 1, default_argv);
  }

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static void TCC_SymbolCallback (void       *UserData,
                                const char *SymbolName,
                                const void *SymbolValue)
{
  lua_State *LuaState = UserData;

  lua_pushstring(LuaState, SymbolName);
  lua_pushlightuserdata(LuaState, (void *)SymbolValue); /* avoid const warning */
  lua_settable(LuaState, -3);
}

static int LIBTCC_ListSymbols (lua_State *LuaState)
{
  TCCState *TccState = lua_touserdata(LuaState, 1);

  lua_newtable(LuaState);
  tcc_list_symbols(TccState, LuaState, TCC_SymbolCallback);

  return 1; /* Number of values returned on the stack */
}

static int LIBTCC_GetLuaState (lua_State *LuaState)
{
  lua_pushlightuserdata(LuaState, LuaState);

  return 1; /* Number of values returned on the stack */
}

struct UIO_LuaFunctionEntry
{
  const char *Name;
  void       *Pointer;
};

/* We provide the Lua library symbols in order to let tcc extend
 * Lua runtime at execution
 *
 * This would allow to write C extensions at Lua runtime
 */
static const struct UIO_LuaFunctionEntry UIO_LuaFunctions[] =
{
  { "lua_absindex",          (void *)lua_absindex },
  { "lua_arith",             (void *)lua_arith },
  { "lua_atpanic",           (void *)lua_atpanic },
  { "lua_callk",             (void *)lua_callk },
  { "lua_checkstack",        (void *)lua_checkstack },
  { "lua_close",             (void *)lua_close },
  { "lua_closeslot",         (void *)lua_closeslot },
  { "lua_closethread",       (void *)lua_closethread },
  { "lua_compare",           (void *)lua_compare },
  { "lua_concat",            (void *)lua_concat },
  { "lua_copy",              (void *)lua_copy },
  { "lua_createtable",       (void *)lua_createtable },
  { "lua_dump",              (void *)lua_dump },
  { "lua_error",             (void *)lua_error },
  { "lua_gc",                (void *)lua_gc },
  { "lua_getallocf",         (void *)lua_getallocf },
  { "lua_getfield",          (void *)lua_getfield },
  { "lua_getglobal",         (void *)lua_getglobal },
  { "lua_gethook",           (void *)lua_gethook },
  { "lua_gethookcount",      (void *)lua_gethookcount },
  { "lua_gethookmask",       (void *)lua_gethookmask },
  { "lua_geti",              (void *)lua_geti },
  { "lua_getinfo",           (void *)lua_getinfo },
  { "lua_getiuservalue",     (void *)lua_getiuservalue },
  { "lua_getmetatable",      (void *)lua_getmetatable },
  { "lua_getstack",          (void *)lua_getstack },
  { "lua_gettable",          (void *)lua_gettable },
  { "lua_gettop",            (void *)lua_gettop },
  { "lua_iscfunction",       (void *)lua_iscfunction },
  { "lua_isinteger",         (void *)lua_isinteger },
  { "lua_isnumber",          (void *)lua_isnumber },
  { "lua_isstring",          (void *)lua_isstring },
  { "lua_isuserdata",        (void *)lua_isuserdata },
  { "lua_isyieldable",       (void *)lua_isyieldable },
  { "lua_len",               (void *)lua_len },
  { "lua_load",              (void *)lua_load },
  { "lua_newstate",          (void *)lua_newstate },
  { "lua_newthread",         (void *)lua_newthread },
  { "lua_newuserdatauv",     (void *)lua_newuserdatauv },
  { "lua_next",              (void *)lua_next },
  { "lua_numbertocstring",   (void *)lua_numbertocstring },
  { "lua_pcallk",            (void *)lua_pcallk },
  { "lua_pushboolean",       (void *)lua_pushboolean },
  { "lua_pushcclosure",      (void *)lua_pushcclosure },
  { "lua_pushinteger",       (void *)lua_pushinteger },
  { "lua_pushlightuserdata", (void *)lua_pushlightuserdata },
  { "lua_pushnil",           (void *)lua_pushnil },
  { "lua_pushnumber",        (void *)lua_pushnumber },
  { "lua_pushstring",        (void *)lua_pushstring },
  { "lua_pushthread",        (void *)lua_pushthread },
  { "lua_pushvalue",         (void *)lua_pushvalue },
  { "lua_rawequal",          (void *)lua_rawequal },
  { "lua_rawget",            (void *)lua_rawget },
  { "lua_rawgeti",           (void *)lua_rawgeti },
  { "lua_rawgetp",           (void *)lua_rawgetp },
  { "lua_rawlen",            (void *)lua_rawlen },
  { "lua_rawset",            (void *)lua_rawset },
  { "lua_rawseti",           (void *)lua_rawseti },
  { "lua_rawsetp",           (void *)lua_rawsetp },
  { "lua_resume",            (void *)lua_resume },
  { "lua_rotate",            (void *)lua_rotate },
  { "lua_setallocf",         (void *)lua_setallocf },
  { "lua_setfield",          (void *)lua_setfield },
  { "lua_setglobal",         (void *)lua_setglobal },
  { "lua_sethook",           (void *)lua_sethook },
  { "lua_seti",              (void *)lua_seti },
  { "lua_setiuservalue",     (void *)lua_setiuservalue },
  { "lua_setmetatable",      (void *)lua_setmetatable },
  { "lua_settable",          (void *)lua_settable },
  { "lua_settop",            (void *)lua_settop },
  { "lua_setwarnf",          (void *)lua_setwarnf },
  { "lua_status",            (void *)lua_status },
  { "lua_stringtonumber",    (void *)lua_stringtonumber },
  { "lua_toboolean",         (void *)lua_toboolean },
  { "lua_tocfunction",       (void *)lua_tocfunction },
  { "lua_toclose",           (void *)lua_toclose },
  { "lua_tointegerx",        (void *)lua_tointegerx },
  { "lua_tolstring",         (void *)lua_tolstring },
  { "lua_tonumberx",         (void *)lua_tonumberx },
  { "lua_tothread",          (void *)lua_tothread },
  { "lua_touserdata",        (void *)lua_touserdata },
  { "lua_type",              (void *)lua_type },
  { "lua_upvalueid",         (void *)lua_upvalueid },
  { "lua_upvaluejoin",       (void *)lua_upvaluejoin },
  { "lua_version",           (void *)lua_version },
  { "lua_warning",           (void *)lua_warning },
  { "lua_xmove",             (void *)lua_xmove },
  { "lua_yieldk",            (void *)lua_yieldk },
  { "luaL_addgsub",          (void *)luaL_addgsub },
  { "luaL_addlstring",       (void *)luaL_addlstring },
  { "luaL_addstring",        (void *)luaL_addstring },
  { "luaL_addvalue",         (void *)luaL_addvalue },
  { "luaL_argerror",         (void *)luaL_argerror },
  { "luaL_buffinit",         (void *)luaL_buffinit },
  { "luaL_callmeta",         (void *)luaL_callmeta },
  { "luaL_checkany",         (void *)luaL_checkany },
  { "luaL_checkinteger",     (void *)luaL_checkinteger },
  { "luaL_checknumber",      (void *)luaL_checknumber },
  { "luaL_checkoption",      (void *)luaL_checkoption },
  { "luaL_checkstack",       (void *)luaL_checkstack },
  { "luaL_checktype",        (void *)luaL_checktype },
  { "luaL_checkversion_",    (void *)luaL_checkversion_ },
  { "luaL_error",            (void *)luaL_error },
  { "luaL_execresult",       (void *)luaL_execresult },
  { "luaL_fileresult",       (void *)luaL_fileresult },
  { "luaL_getmetafield",     (void *)luaL_getmetafield },
  { "luaL_getsubtable",      (void *)luaL_getsubtable },
  { "luaL_len",              (void *)luaL_len },
  { "luaL_loadbufferx",      (void *)luaL_loadbufferx },
  { "luaL_loadfilex",        (void *)luaL_loadfilex },
  { "luaL_loadstring",       (void *)luaL_loadstring },
  { "luaL_newmetatable",     (void *)luaL_newmetatable },
  { "luaL_openselectedlibs", (void *)luaL_openselectedlibs },
  { "luaL_optinteger",       (void *)luaL_optinteger },
  { "luaL_optnumber",        (void *)luaL_optnumber },
  { "luaL_pushresult",       (void *)luaL_pushresult },
  { "luaL_pushresultsize",   (void *)luaL_pushresultsize },
  { "luaL_ref",              (void *)luaL_ref },
  { "luaL_requiref",         (void *)luaL_requiref },
  { "luaL_setfuncs",         (void *)luaL_setfuncs },
  { "luaL_setmetatable",     (void *)luaL_setmetatable },
  { "luaL_traceback",        (void *)luaL_traceback },
  { "luaL_typeerror",        (void *)luaL_typeerror },
  { "luaL_unref",            (void *)luaL_unref },
  { "luaL_where",            (void *)luaL_where },
  { "luaopen_base",          (void *)luaopen_base },
  { "luaopen_coroutine",     (void *)luaopen_coroutine },
  { "luaopen_debug",         (void *)luaopen_debug },
  { "luaopen_io",            (void *)luaopen_io },
  { "luaopen_math",          (void *)luaopen_math },
  { "luaopen_os",            (void *)luaopen_os },
  { "luaopen_package",       (void *)luaopen_package },
  { "luaopen_string",        (void *)luaopen_string },
  { "luaopen_table",         (void *)luaopen_table },
  { "luaopen_utf8",          (void *)luaopen_utf8 },
  { NULL, NULL }
};

static int LIBTCC_GetLuaLibrary (lua_State *LuaState)
{
  const struct UIO_LuaFunctionEntry *Entry = UIO_LuaFunctions;

  lua_newtable(LuaState);

  while (Entry->Name != NULL)
  {
    lua_pushstring(LuaState, Entry->Name);
    lua_pushlightuserdata(LuaState, Entry->Pointer);
    lua_settable(LuaState, -3);

    Entry++;
  }

  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* MODULE INITIALIZATION                                                      */
/*============================================================================*/

static const struct luaL_Reg TCC_FUNCTIONS[] =
{
  { "tcc_new",              LIBTCC_New            },
  { "tcc_delete",           LIBTCC_Delete         },
  { "tcc_set_output_type",  LIBTCC_SetOutputType  },
  { "tcc_compile_string",   LIBTCC_CompileString  },
  { "tcc_run",              LIBTCC_Run            },
  { "tcc_relocate",         LIBTCC_Relocate       },
  { "tcc_get_symbol",       LIBTCC_GetSymbol      },
  { "tcc_add_symbol",       LIBTCC_AddSymbol      },
  { "tcc_add_file",         LIBTCC_AddFile        },
  { "tcc_add_library_path", LIBTCC_AddLibraryPath },
  { "tcc_add_library",      LIBTCC_AddLibrary     },
  { "tcc_define_symbol",    LIBTCC_DefineSymbol   },
  { "tcc_undefine_symbol",  LIBTCC_UndefineSymbol },
  { "tcc_output_file",      LIBTCC_OutputFile     },
  { "tcc_main",             LIBTCC_RunTccMain     },
  { "tcc_list_symbols",     LIBTCC_ListSymbols    },
  { "tcc_get_luastate",     LIBTCC_GetLuaState    },
  { "tcc_get_lualib",       LIBTCC_GetLuaLibrary  },
  { NULL, NULL }
};

/*============================================================================*/
/* ENTRY POINT                                                                */
/*============================================================================*/

int luaopen_libtcc (lua_State *LuaState)
{
  /* Load UIO module via require("com.uio") */
  lua_getglobal(LuaState, "require");
  lua_pushstring(LuaState, "com.uio");
  lua_pcall(LuaState, 1, 1, 0);

  lua_getfield(LuaState, -1, "open");
  UIO_open_ref  = luaL_ref(LuaState, LUA_REGISTRYINDEX);
  lua_getfield(LuaState, -1, "write");
  UIO_write_ref = luaL_ref(LuaState, LUA_REGISTRYINDEX);
  lua_getfield(LuaState, -1, "read");
  UIO_read_ref  = luaL_ref(LuaState, LUA_REGISTRYINDEX);
  lua_getfield(LuaState, -1, "close");
  UIO_close_ref = luaL_ref(LuaState, LUA_REGISTRYINDEX);
  lua_getfield(LuaState, -1, "lseek");
  UIO_lseek_ref = luaL_ref(LuaState, LUA_REGISTRYINDEX);
  lua_getfield(LuaState, -1, "dup");
  UIO_dup_ref   = luaL_ref(LuaState, LUA_REGISTRYINDEX);

  /* Pop uio module table */
  lua_pop(LuaState, 1);

  /* Register all TCC functions */
  luaL_newlib(LuaState, TCC_FUNCTIONS);

  return 1; /* Number of values returned on the stack */
}
