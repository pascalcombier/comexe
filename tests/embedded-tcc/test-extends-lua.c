/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <stdio.h>
#include <lua.h>
#include <lauxlib.h>

/*============================================================================*/
/* INTERFACE WITH LUA                                                         */
/*============================================================================*/

extern lua_State *GetLuaState ();

/*============================================================================*/
/* MODULE IMPLEMENTATION                                                      */
/*============================================================================*/

static int EXAMPLE_Print (lua_State *LuaState)
{
  const char *Message = lua_tolstring(LuaState, 1, NULL);
  printf("cprint:%s\n", Message);

  return 0;
}

static const struct luaL_Reg EXAMPLE_MODULE[] =
{
  {"cprint", EXAMPLE_Print},
  {NULL, NULL}
};

int luaopen_example (lua_State *LuaState)
{
  luaL_newlib(LuaState, EXAMPLE_MODULE);

  return 1;
}

/*============================================================================*/
/* MAIN: REGISTER C MODULE TO LUASTATE                                        */
/*============================================================================*/

int main (int argc, char **argv)
{
  lua_State *LuaState = GetLuaState();

  if (LuaState)
  {
    lua_getfield(LuaState, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
    lua_pushcfunction(LuaState, luaopen_example);
    lua_setfield(LuaState, -2, "example");
    lua_pop(LuaState, 1);
  }

  return 0;
}
