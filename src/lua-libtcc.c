/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-libtcc.c                                                      *
 * CONTENT  Embeded libtcc into ComEXE (raw bindings, low level)              *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/* Note that we are not using mi_malloc here or PLAT_SafeAlloc0
 *
 * libtcc has the function tcc_set_realloc but it does not make sense because
 * tcc_set_free is missing, so for the time being we just use internal
 * allocations routines from libtcc which are probably malloc/free.
 *
 * Maybe it make sense, if it only allocates memory without freeing anything.
 *
 * Initial code was:
 * static void *TCC_ReallocWrapper (void *Pointer, unsigned long SizeInBytes)
 * {
 *   return PLAT_SafeRealloc(Pointer, (size_t)SizeInBytes);
 * }
 * tcc_set_realloc(TCC_ReallocWrapper);
 */

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/*---------*/
/* HEADERS */
/*---------*/

/* The external luaopen_libtcc declaration require lua_State */
#include <lua.h>

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <lauxlib.h> /* luaL_Reg */
#include <string.h>  /* memcpy   */
#include <stdbool.h> /* bool     */
#include <errno.h>   /* errno constants */
#include <fcntl.h>   /* O_CREAT  */
#include <libtcc.h>

#include "comexe.h" /* PLAT_SafeAlloc0 */

/*============================================================================*/
/* FORWARD DECLARATIONS                                                       */
/*============================================================================*/

/* We want to have 1-to-1 compatibility with tcc.exe... so we just call tcc */
extern int tcc_main (void *UserData, int argc, char **argv);

#define TCC_MIN(a, b) ((a) < (b) ? (a) : (b))

/*============================================================================*/
/* PRIVATE FUNCTIONS                                                          */
/*============================================================================*/

static bool STRING_Equals (const char *String1, const char *String2)
{
  return (strcmp(String1, String2) == 0);
}

/*============================================================================*/
/* LIBTCC PATCH                                                               */
/*============================================================================*/

/* On tcc_write_elf_file, the initial call to open() includes mode */
int vio4_open (TCCState *TccState, const char *Pathname, int Flags, int Mode)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  int        FileDescriptor;
  
  if (LUA_PushEventHandler(LuaState))
  {
    /* Push arguments */
    lua_pushstring(LuaState, "Open");
    lua_pushstring(LuaState, Pathname);
    lua_pushinteger(LuaState, Flags);
    lua_pushinteger(LuaState, Mode);
    
    /* Call the Lua function */
    if (lua_pcall(LuaState, 4, 1, 0) == 0)
    {
      FileDescriptor = lua_tointeger(LuaState, -1);
      lua_pop(LuaState, 1);
    } 
    else
    {
      lua_pop(LuaState, 1);     /* pop error message */
      FileDescriptor = -ENOENT; /* File not found    */
    }
  }
  else
  {
    FileDescriptor = -ENOSYS; /* Function not implemented */
  }
  
  return FileDescriptor;
}

int vio4_write (TCCState     *TccState,
                int           fd,
                const void   *Buffer,
                unsigned int  SizeInBytes)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  int        Result;
  
  if (LUA_PushEventHandler(LuaState))
  {
    /* Push arguments */
    lua_pushstring(LuaState, "Write");
    lua_pushinteger(LuaState, fd);
    lua_pushlstring(LuaState, (const char*)Buffer, SizeInBytes);
    
    /* Call the Lua function */
    if (lua_pcall(LuaState, 3, 1, 0) == 0)
    {
      Result = lua_tointeger(LuaState, -1);
      lua_pop(LuaState, 1);  /* pop return value */
    }
    else
    {
      lua_pop(LuaState, 1); /* pop error message */
      Result = -EIO;        /* I/O error         */
    }
  }
  else
  {
    Result = -ENOSYS; /* Function not implemented */
  }
  
  return Result;
}

int vio4_read (TCCState     *TccState,
               int           fd,
               void         *Buffer,
               unsigned int  BufferSizeInBytes)
{
  lua_State   *LuaState = tcc_get_userdata(TccState);
  int          Result;
  const char  *Data;
  size_t       ReadSizeInBytes;
  
  if (LUA_PushEventHandler(LuaState))
  {
    /* Push arguments */
    lua_pushstring(LuaState, "Read");
    lua_pushinteger(LuaState, fd);
    lua_pushinteger(LuaState, BufferSizeInBytes);
    
    /* Call the Lua function */
    if (lua_pcall(LuaState, 3, 1, 0) == 0)
    {
      /* Handle return value based on type */
      if (lua_isstring(LuaState, -1))
      {
        Data = lua_tolstring(LuaState, -1, &ReadSizeInBytes);
        BufferSizeInBytes = TCC_MIN(BufferSizeInBytes, ReadSizeInBytes);
        memcpy(Buffer, Data, BufferSizeInBytes);
        Result = (int)BufferSizeInBytes;
      }
      else if (lua_isnumber(LuaState, -1))
      {
        Result = lua_tointeger(LuaState, -1);
      }
      lua_pop(LuaState, 1);
    }
    else
    {
      lua_pop(LuaState, 1); /* pop error message */
      Result = -EIO;        /* I/O error         */
    }
  }
  else
  {
    Result = -ENOSYS; /* Function not implemented */
  }
  
  return Result;
}

int vio4_close (TCCState *TccState, int fd)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  int        Result;
  
  if (LUA_PushEventHandler(LuaState))
  {
    /* Push arguments */
    lua_pushstring(LuaState, "Close");
    lua_pushinteger(LuaState, fd);
    
    /* Call the Lua function */
    if (lua_pcall(LuaState, 2, 1, 0) == 0)
    {
      Result = lua_tointeger(LuaState, -1);
      lua_pop(LuaState, 1); /* pop return value */
    }
    else
    {
      Result = -EIO;        /* I/O error         */
      lua_pop(LuaState, 1); /* pop error message */
    }
  }
  else
  {
    Result = -ENOSYS; /* Function not implemented */
  }
  
  return Result;
}

off_t vio4_lseek (TCCState *TccState, int fd, off_t offset, int whence)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  off_t      Result;
  
  if (LUA_PushEventHandler(LuaState))
  {
    /* Push arguments */
    lua_pushstring(LuaState, "Seek");
    lua_pushinteger(LuaState, fd);
    lua_pushinteger(LuaState, offset);
    lua_pushinteger(LuaState, whence);
    
    /* Call the Lua function */
    if (lua_pcall(LuaState, 4, 1, 0) == 0)
    {
      /* Get the file position from Lua */
      Result = (off_t)lua_tointeger(LuaState, -1);
      lua_pop(LuaState, 1); /* pop return value */
    }
    else
    {
      Result = -ESPIPE;     /* Illegal seek      */
      lua_pop(LuaState, 1); /* pop error message */
    }
  }
  else
  {
    Result = -ENOSYS; /* Function not implemented */
  }
  
  return Result;
}

int vio4_dup (TCCState *TccState, int fd)
{
  lua_State *LuaState = tcc_get_userdata(TccState);
  int        Result;
  
  if (LUA_PushEventHandler(LuaState))
  {
    /* Push arguments */
    lua_pushstring(LuaState, "Dup");
    lua_pushinteger(LuaState, fd);
    
    /* Call the Lua function */
    if (lua_pcall(LuaState, 2, 1, 0) == 0)
    {
      Result = lua_tointeger(LuaState, -1);
      lua_pop(LuaState, 1);  /* pop return value */
    }
    else
    {
      Result = -EBADF;       /* Bad file descriptor */
      lua_pop(LuaState, 1);  /* pop error message   */
    }
  }
  else
  {
    Result = -ENOSYS; /* Function not implemented */
  }
  
  return Result;
}

/*============================================================================*/
/* LIBRARY DEFINITION                                                         */
/*============================================================================*/

static int TCC_RunTccMain (lua_State *LuaState)
{
  int          argc          = lua_gettop(LuaState);
  char        *DefaultArgv[] = { "tcc", NULL };
  char       **argv          = NULL;
  int          Result;
  int          Index;
  const char  *Argument;

  if (argc > 0)
  {
    /* "tcc" + argc + NULL => we need argc+2 */
    
    argv    = PLAT_SafeAlloc0((argc + 2), sizeof(char *));
    argv[0] = PLAT_StrDup("tcc");
    
    /* Convert stack arguments to argv array */
    for (Index = 1; Index <= argc; Index++) 
    {
      if (lua_isstring(LuaState, Index))
      {
        Argument    = lua_tostring(LuaState, Index);
        argv[Index] = PLAT_StrDup(Argument);
      } 
      else 
      {
        argv[Index] = NULL;
      }
    }
    argv[argc + 1] = NULL; /* terminate the array with NULL */
    
    /* Call the TCC main function */
    Result = tcc_main(LuaState, (argc + 1), argv);
    
    /* Free allocated memory including argv[0] */
    for (Index = 0; Index <= argc; Index++)
    {
      PLAT_Free(argv[Index]);
    }
    PLAT_Free(argv);
  }
  else
  {
    /* If no arguments provided, just call tcc_main with empty args */
    Result = tcc_main(LuaState, 1, DefaultArgv);
  }
  
  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static int TCC_New (lua_State *LuaState)
{
  TCCState *TccState = tcc_new();

  /* Attach the Lua state for the vio4_ functions */
  tcc_set_userdata(TccState, LuaState);

  lua_pushlightuserdata(LuaState, TccState);
  
  return 1; /* Number of values returned on the stack */
}

static int TCC_Delete (lua_State *LuaState)
{
  TCCState *TccState = lua_touserdata(LuaState, 1);

  tcc_delete(TccState);

  return 0; /* Number of values returned on the stack */
}

static int TCC_DefineSymbol (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Symbol   = luaL_checkstring(LuaState, 2);
  const char *Value;

  if (lua_isnil(LuaState, 3)) 
  {
    Value = NULL;
  }
  else
  {
    Value = lua_tostring(LuaState, 3);
  }

  tcc_define_symbol(TccState, Symbol, Value);

  return 0; /* Number of values returned on the stack */
}

static int TCC_UndefineSymbol (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Symbol   = luaL_checkstring(LuaState, 2);
    
  tcc_undefine_symbol(TccState, Symbol);

  return 0; /* Number of values returned on the stack */
}

static int TCC_CompileString (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Buffer   = luaL_checkstring(LuaState, 2);
  int         Result   = tcc_compile_string(TccState, Buffer);
    
  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static int TCC_SetOutputType (lua_State *LuaState)
{
  TCCState   *TccState       = lua_touserdata(LuaState, 1);
  const char *UserOutputType = lua_tostring(LuaState, 2);
  int         TccOutputType  = TCC_OUTPUT_MEMORY;
  int         Result;

  if ((UserOutputType == NULL) || (STRING_Equals(UserOutputType, "memory"))) {
    TccOutputType = TCC_OUTPUT_MEMORY;
  }
  else if (STRING_Equals(UserOutputType, "exe")) {
    TccOutputType = TCC_OUTPUT_EXE;
  }
  else if (STRING_Equals(UserOutputType, "dll")) {
    TccOutputType = TCC_OUTPUT_DLL;
  }
  else if (STRING_Equals(UserOutputType, "obj")) {
    TccOutputType = TCC_OUTPUT_OBJ;
  }
  else if (STRING_Equals(UserOutputType, "preprocess")) {
    TccOutputType = TCC_OUTPUT_PREPROCESS;
  }

  Result = tcc_set_output_type(TccState, TccOutputType);
      
  lua_pushinteger(LuaState, Result);
  
  return 1; /* Number of values returned on the stack */
}

static int TCC_Run (lua_State *LuaState)
{
  TCCState  *TccState = lua_touserdata(LuaState, 1);
  int        argc     = lua_gettop(LuaState) - 1;
  char     **argv;
  int        Offset;
  int        LuaIndex;
  int        Result;
    
  if (argc >= 0) 
  {
    argv = PLAT_SafeAlloc0((argc + 1), sizeof(char *));
        
    for (Offset = 0; Offset < argc; Offset++) 
    {
      LuaIndex = Offset + 2; /* Lua stack is 1-based, skip TccState at index 1 */
      argv[Offset] = (char *)lua_tostring(LuaState, LuaIndex); /* Cast to remove const */
    }
    argv[argc] = NULL;
    
    Result = tcc_run(TccState, argc, argv);
    
    PLAT_Free(argv);
  }
  else
  {
    Result = -1;
  }
    
  lua_pushinteger(LuaState, Result);
  
  return 1; /* Number of values returned on the stack */
}

static int TCC_Relocate (lua_State *LuaState)
{
  TCCState *TccState = lua_touserdata(LuaState, 1);
  int       Result   = tcc_relocate(TccState);

  lua_pushinteger(LuaState, Result);
  
  return 1; /* Number of values returned on the stack */
}

static int TCC_AddFile (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Filename = luaL_checkstring(LuaState, 2);
  int         Result   = tcc_add_file(TccState, Filename);

  lua_pushinteger(LuaState, Result);

  return 1;
}

static int TCC_AddLibraryPath (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Pathname = luaL_checkstring(LuaState, 2);
  int         Result   = tcc_add_library_path(TccState, Pathname);

  lua_pushinteger(LuaState, Result);
  
  return 1; /* Number of values returned on the stack */
}

static int TCC_AddLibrary (lua_State *LuaState)
{
  TCCState   *TccState    = lua_touserdata(LuaState, 1);
  const char *LibraryName = luaL_checkstring(LuaState, 2);
  int         Result      = tcc_add_library(TccState, LibraryName);
  
  lua_pushinteger(LuaState, Result);
  
  return 1; /* Number of values returned on the stack */
}

static int TCC_AddSymbol (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Name     = luaL_checkstring(LuaState, 2);
  const void *Value    = lua_touserdata(LuaState, 3);
  int         Result   = tcc_add_symbol(TccState, Name, Value);
  
  lua_pushinteger(LuaState, Result);
  
  return 1; /* Number of values returned on the stack */
}

static int TCC_GetSymbol (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Name     = luaL_checkstring(LuaState, 2);
  void       *Symbol   = tcc_get_symbol(TccState, Name);
  
  lua_pushlightuserdata(LuaState, Symbol);
  
  return 1; /* Number of values returned on the stack */
}

static int TCC_OutputFile (lua_State *LuaState)
{
  TCCState   *TccState = lua_touserdata(LuaState, 1);
  const char *Filename = luaL_checkstring(LuaState, 2);
  int         Result   = tcc_output_file(TccState, Filename);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static void TCC_SymbolCallback (void       *UserData,
                                const char *SymbolName,
                                const void *SymbolValue)
{
  lua_State *LuaState = UserData;
  
  /* Push the symbol name and value onto the table */
  lua_pushstring(LuaState, SymbolName);
  lua_pushlightuserdata(LuaState, (void *)SymbolValue); /* discard const */
  lua_settable(LuaState, -3);
}

static int TCC_ListSymbols (lua_State *LuaState)
{
  TCCState *TccState = lua_touserdata(LuaState, 1);
  
  /* Create a new table to store the symbols */
  lua_newtable(LuaState);
  
  /* Call tcc_list_symbols with our callback */
  tcc_list_symbols(TccState, LuaState, TCC_SymbolCallback);

  return 1; /* Return the table of symbols */
}

/*============================================================================*/
/* LUA EXTENSIONS IN TCC                                                      */
/*============================================================================*/

static int TCC_GetLuaState (lua_State *LuaState)
{
  lua_pushlightuserdata(LuaState, LuaState);

  return 1; /* Number of values returned on the stack */
} 

static int TCC_GetLuaLibrary (lua_State *LuaState)
{
  lua_newtable(LuaState);

  /* Lua core functions */

  lua_pushstring(LuaState, "lua_createtable");
  lua_pushlightuserdata(LuaState, lua_createtable);
  lua_settable(LuaState, -3);

  lua_pushstring(LuaState, "lua_pushcclosure");
  lua_pushlightuserdata(LuaState, lua_pushcclosure);
  lua_settable(LuaState, -3);

  lua_pushstring(LuaState, "lua_getfield");
  lua_pushlightuserdata(LuaState, lua_getfield);
  lua_settable(LuaState, -3);

  lua_pushstring(LuaState, "lua_setfield");
  lua_pushlightuserdata(LuaState, lua_setfield);
  lua_settable(LuaState, -3);

  lua_pushstring(LuaState, "lua_setglobal");
  lua_pushlightuserdata(LuaState, lua_setglobal);
  lua_settable(LuaState, -3);

  lua_pushstring(LuaState, "lua_tolstring");
  lua_pushlightuserdata(LuaState, lua_tolstring);
  lua_settable(LuaState, -3);

  lua_pushstring(LuaState, "lua_settop");
  lua_pushlightuserdata(LuaState, lua_settop);
  lua_settable(LuaState, -3);

  /* Lua library */

  lua_pushstring(LuaState, "luaL_getsubtable");
  lua_pushlightuserdata(LuaState, luaL_getsubtable);
  lua_settable(LuaState, -3);

  lua_pushstring(LuaState, "luaL_checkversion_");
  lua_pushlightuserdata(LuaState, luaL_checkversion_);
  lua_settable(LuaState, -3);

  lua_pushstring(LuaState, "luaL_setfuncs");
  lua_pushlightuserdata(LuaState, luaL_setfuncs);
  lua_settable(LuaState, -3);

  return 1; /* Return the table */
}

/*============================================================================*/
/* ENTRY POINT                                                                */
/*============================================================================*/

static const struct luaL_Reg TCC_FUNCTIONS[] =
{
  { "tcc_main",             TCC_RunTccMain     },
  { "tcc_new",              TCC_New            },
  { "tcc_delete",           TCC_Delete         },
  { "tcc_define_symbol",    TCC_DefineSymbol   },
  { "tcc_undefine_symbol",  TCC_UndefineSymbol },
  { "tcc_compile_string",   TCC_CompileString  },
  { "tcc_set_output_type",  TCC_SetOutputType  },
  { "tcc_run",              TCC_Run            },
  { "tcc_relocate",         TCC_Relocate       },
  { "tcc_add_file",         TCC_AddFile        },
  { "tcc_add_library_path", TCC_AddLibraryPath },
  { "tcc_add_library",      TCC_AddLibrary     },
  { "tcc_add_symbol",       TCC_AddSymbol      },
  { "tcc_get_symbol",       TCC_GetSymbol      },
  { "tcc_output_file",      TCC_OutputFile     },
  { "tcc_list_symbols",     TCC_ListSymbols    },
  /* Allow TCC extensions for current LuaState */
  { "tcc_get_luastate",     TCC_GetLuaState    },
  { "tcc_get_lualib",       TCC_GetLuaLibrary  },
  /* End of list */
  { NULL, NULL}
};

int luaopen_libtcc (lua_State *LuaState)
{
  luaL_newlib(LuaState, TCC_FUNCTIONS);
  
  return 1; /* Number of values returned on the stack */
}
