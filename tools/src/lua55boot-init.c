/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua55boot-init.c                                                  *
 * CONTENT  Special lua interpreter for make.lua/pack.lua                     *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*
 *
 * DOCUMENTED IN lua55boot.h
 */

/*============================================================================*/
/* HEADERS                                                                    */
/*============================================================================*/

#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/*============================================================================*/
/* EXTERNAL C MODULES                                                         */
/*============================================================================*/

extern int luaopen_luv       (lua_State *LuaState);
extern int luaopen_minizipng (lua_State *LuaState);

/*============================================================================*/
/* LUA RUNTIME                                                                */
/*============================================================================*/

static const char LUA_BOOT_INIT_LUA[] = {
#embed "lua55boot-init.lua"
, 0
};

/*============================================================================*/
/* ENTRY POINT                                                                */
/*============================================================================*/

/* Duplicated from lua-application.c */
static void APP_RegisterPreload (lua_State     *LuaState,
                                 const char    *Name,
                                 lua_CFunction  Function)
{
  luaL_getsubtable(LuaState, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  lua_pushcfunction(LuaState, Function);
  lua_setfield(LuaState, -2, Name);
  lua_pop(LuaState, 1); /* LUA_PRELOAD_TABLE table */
}

static void LUA_FatalError (lua_State *LuaState, const char *Step)
{
  fprintf(stderr, "lua55boot: %s: %s\n", Step, lua_tostring(LuaState, -1));
  lua_pop(LuaState, 1);
  exit(EXIT_FAILURE);
}

/* Called by lua.c main function */
void LUA_BootOpenLibraries (struct lua_State *LuaState)
{
  /* Standard libraries */
  luaL_openlibs(LuaState);

  /* Load the C libraries */
  APP_RegisterPreload(LuaState, "com.raw.minizipng", luaopen_minizipng);
  APP_RegisterPreload(LuaState, "luv",               luaopen_luv);

  /* Load the lua init code */
  if (luaL_loadbuffer(LuaState, LUA_BOOT_INIT_LUA, (sizeof(LUA_BOOT_INIT_LUA) - 1), "@lua55boot-init.lua") != LUA_OK)
  {
    LUA_FatalError(LuaState, "cannot load init.lua");
  }
  else if (lua_pcall(LuaState, 0, 0, 0) != LUA_OK)
  {
    LUA_FatalError(LuaState, "cannot run init.lua");
  }
}
