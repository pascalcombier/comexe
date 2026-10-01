/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME tools/src/buildtool.c                                             *
 * CONTENT  Special build-time tool to help build ComEXE (ZIP, concat, etc)   *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*
 *
 * DOCUMENTED IN tools/src/buildtool.h
 */

/*============================================================================*/
/* HEADERS                                                                    */
/*============================================================================*/

#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "buildtool.h"

/*============================================================================*/
/* EXTERNAL C MODULES                                                         */
/*============================================================================*/

extern int luaopen_luv       (lua_State *LuaState);
extern int luaopen_minizipng (lua_State *LuaState);

/*============================================================================*/
/* EMBEDDED LUA                                                               */
/*============================================================================*/

static const char BUILDTOOL_FILE_OPS_LUA[] = {
#embed "buildtool-file-ops.lua"
, 0
};

static const char BUILDTOOL_PACK_LUA[] = {
#embed "buildtool-pack.lua"
, 0
};

static const char BUILDTOOL_MAIN_LUA[] = {
#embed "buildtool-main.lua"
, 0
};

/*============================================================================*/
/* IMPORTED FUNCTIONS (lua-application.c)                                     */
/*============================================================================*/

static void APP_RegisterPreload (lua_State     *LuaState,
                                 const char    *PreloadName,
                                 lua_CFunction  Function)
{
  luaL_getsubtable(LuaState, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  lua_pushcfunction(LuaState, Function);
  lua_setfield(LuaState, -2, PreloadName);
  lua_pop(LuaState, 1); /* LUA_PRELOAD_TABLE table */
}

/*============================================================================*/
/* RUNTIME                                                                    */
/*============================================================================*/

static int BUILDTOOL_RunChunk (lua_State  *LuaState,
                               const char *Buffer,
                               size_t      Size,
                               const char *ChunkName)
{
  luaL_loadbuffer(LuaState, Buffer, Size, ChunkName);
  lua_call(LuaState, 0, 1);
  
  return 1; /* Number of values returned on the stack */
}

static int BUILDTOOL_LoadFileOps (lua_State *LuaState)
{
  return BUILDTOOL_RunChunk(LuaState,
                            BUILDTOOL_FILE_OPS_LUA,
                            (sizeof(BUILDTOOL_FILE_OPS_LUA) - 1),
                            "@buildtool-file-ops.lua");
}

static int BUILDTOOL_LoadPack (lua_State *LuaState)
{
  return BUILDTOOL_RunChunk(LuaState,
                            BUILDTOOL_PACK_LUA,
                            (sizeof(BUILDTOOL_PACK_LUA) - 1),
                            "@buildtool-pack.lua");
}

void BUILDTOOL_BootLibraries (struct lua_State *LuaState)
{
  /* Standard Lua libraries */
  luaL_openlibs(LuaState);

  /* Load C libraries */
  APP_RegisterPreload(LuaState, "com.raw.minizipng", luaopen_minizipng);
  APP_RegisterPreload(LuaState, "luv",               luaopen_luv);

  /* Load Lua runtime */
  luaL_requiref(LuaState, "buildtool-file-ops", BUILDTOOL_LoadFileOps, 0);
  lua_pop(LuaState, 1);
  luaL_requiref(LuaState, "buildtool-pack", BUILDTOOL_LoadPack, 0);
  lua_pop(LuaState, 1);
}

/* Set arg table in the environment */
/* WARNING: not UNICODE!! */
static void BUILDTOOL_ExportArg (lua_State *LuaState, int argc, char **argv)
{
  int Offset;

  lua_createtable(LuaState, argc, 0);
  
  for (Offset = 0; (Offset < argc); Offset++)
  {
    lua_pushstring(LuaState, argv[Offset]);
    lua_rawseti(LuaState, -2, Offset);
  }
  
  lua_setglobal(LuaState, "arg");
}

/*============================================================================*/
/* MAIN                                                                       */
/*============================================================================*/

static int BUILDTOOL_RunLuaEntryPoint (lua_State  *LuaState,
                                       int         argc,
                                       char      **argv)
{
  int Status;
  int Offset;
  int ExitCode;

  /* Load the chunk on the stack */
  Status = luaL_loadbuffer(LuaState,
                           BUILDTOOL_MAIN_LUA,
                           (sizeof(BUILDTOOL_MAIN_LUA) - 1),
                           "@buildtool-main.lua");
  
  if (Status == LUA_OK)
  {
    /* Push args for Lua script to have "..." */
    for (Offset = 1; (Offset < argc); Offset++)
    {
      lua_pushstring(LuaState, argv[Offset]);
    }

    /* Execute the chunk, 0 result */
    Status = lua_pcall(LuaState, (argc - 1), 0, 0);

    if (Status != LUA_OK)
    {
      fprintf(stderr, "buildtool: %s\n", lua_tostring(LuaState, -1));
      ExitCode = EXIT_FAILURE;
    }
    else
    {
      ExitCode = EXIT_SUCCESS;
    }
  }
  else
  {
    fprintf(stderr, "buildtool: cannot load the entry point: %s\n", lua_tostring(LuaState, -1));
    ExitCode = EXIT_FAILURE;
  }
  
  return ExitCode;
}

int main (int argc, char **argv)
{
  lua_State *LuaState = luaL_newstate();
  int        ExitCode;

  if (LuaState)
  {
    BUILDTOOL_BootLibraries(LuaState);
    BUILDTOOL_ExportArg(LuaState, argc, argv);
    ExitCode = BUILDTOOL_RunLuaEntryPoint(LuaState, argc, argv);
    lua_close(LuaState);
  }
  else
  {
    fprintf(stderr, "buildtool: could not create a Lua state\n");
    ExitCode = EXIT_FAILURE;
  }

  return ExitCode;
}
