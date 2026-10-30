/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-libmbedtls.c                                                  *
 * CONTENT  Raw Lua bindings for mbedtls (message digests)                    *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the MIT license (see the LICENSE file). *
 * SPDX-License-Identifier: MIT                                               *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* DOCUMENTATION                                                              *
/*============================================================================*/

/**
 * Internal mbedtls layer:
 *   - implement digest (streaming)
 *
 * Usage:
 *
 *   local Info    = md_info_from_string("SHA256")
 *   local Size    = md_size(Info)
 *   local Context = md_new()
 *   local Code    = md_setup(Context, Info)
 *   Code          = md_starts(Context)
 *   Code          = md_update(Context, "abc")
 *   Code, Digest  = md_finish(Context, Size)
 *   md_free(Context)
 */

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/* The external function luaopen_XXX rely on the type lua_State */
#include <lua.h>

#endif

/*============================================================================*/
/* IMPLEMENTATION                                                             */
/*============================================================================*/

#include <string.h>     /* memset        */
#include <lauxlib.h>    /* luaL_newlib   */
#include <mbedtls/md.h> /* mbedtls_md_*  */

#include "comexe.h"

/*============================================================================*/
/* PRIVATE FUNCTIONS                                                          */
/*============================================================================*/

static int MBEDTLS_MD_InfoFromString (lua_State *LuaState)
{
  const char              *Algorithm = luaL_checkstring(LuaState, 1);
  const mbedtls_md_info_t *Info      = mbedtls_md_info_from_string(Algorithm);

  if (Info != NULL)
  {
    lua_pushlightuserdata(LuaState, Info);
  }
  else
  {
    lua_pushnil(LuaState);
  }

  return 1; /* Number of values pushed on the stack */
}

static int MBEDTLS_MD_Size (lua_State *LuaState)
{
  const mbedtls_md_info_t *Info = lua_touserdata(LuaState, 1);

  lua_pushinteger(LuaState, mbedtls_md_get_size(Info));

  return 1; /* Number of values pushed on the stack */
}

static int MBEDTLS_MD_New (lua_State *LuaState)
{
  mbedtls_md_context_t *NewContext = PLAT_SafeAlloc0(1, sizeof(mbedtls_md_context_t));

  mbedtls_md_init(NewContext);

  lua_pushlightuserdata(LuaState, NewContext);

  return 1; /* Number of values pushed on the stack */
}

static int MBEDTLS_MD_Free (lua_State *LuaState)
{
  mbedtls_md_context_t *Context = lua_touserdata(LuaState, 1);

  mbedtls_md_free(Context);
  PLAT_Free(Context);

  return 0; /* Number of values pushed on the stack */
}

static int MBEDTLS_MD_Setup (lua_State *LuaState)
{
  mbedtls_md_context_t    *Context = lua_touserdata(LuaState, 1);
  const mbedtls_md_info_t *Info    = lua_touserdata(LuaState, 2);
  
  int Result = mbedtls_md_setup(Context, Info, 0);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values pushed on the stack */
}

static int MBEDTLS_MD_Starts (lua_State *LuaState)
{
  mbedtls_md_context_t *Context = lua_touserdata(LuaState, 1);
  int                   Result  = mbedtls_md_starts(Context);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values pushed on the stack */
}

static int MBEDTLS_MD_Update (lua_State *LuaState)
{
  size_t                SizeInBytes;
  mbedtls_md_context_t *Context = lua_touserdata(LuaState, 1);
  const char           *Data    = luaL_checklstring(LuaState, 2, &SizeInBytes);
  
  int Result = mbedtls_md_update(Context, (const unsigned char *)Data, SizeInBytes);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values pushed on the stack */
}

/* DigestSizeInBytes comes from md_size(Info) and must not exceed MBEDTLS_MD_MAX_SIZE */
static int MBEDTLS_MD_Finish (lua_State *LuaState)
{
  mbedtls_md_context_t *Context           = lua_touserdata(LuaState, 1);
  size_t                DigestSizeInBytes = luaL_checkinteger(LuaState, 2);
  unsigned char         Digest[MBEDTLS_MD_MAX_SIZE];
  int                   Result;

  memset(Digest, 0, sizeof(Digest));

  Result = mbedtls_md_finish(Context, Digest);

  if (Result == 0)
  {
    lua_pushinteger(LuaState, Result);
    lua_pushlstring(LuaState, (const char *)Digest, DigestSizeInBytes);
  }
  else
  {
    lua_pushinteger(LuaState, Result);
    lua_pushnil(LuaState);
  }

  return 2; /* Number of values pushed on the stack */
}

static int MBEDTLS_MD_Algorithms (lua_State *LuaState)
{
  const int               *Types = mbedtls_md_list();
  const mbedtls_md_info_t *Info;
  int                      Count = 0;
  int                      Index = 0;

  lua_newtable(LuaState);

  while (Types[Index] != MBEDTLS_MD_NONE)
  {
    Info = mbedtls_md_info_from_type(Types[Index]);

    if (Info != NULL)
    {
      Count = (Count + 1);
      lua_pushstring(LuaState, mbedtls_md_get_name(Info));
      lua_rawseti(LuaState, -2, Count);
    }

    Index = (Index + 1);
  }

  return 1; /* Number of values pushed on the stack */
}

/*============================================================================*/
/* PUBLIC INTERFACE                                                           */
/*============================================================================*/

static const struct luaL_Reg MBEDTLS_MD_FUNCTIONS[] =
{
  { "md_info_from_string", MBEDTLS_MD_InfoFromString },
  { "md_size",             MBEDTLS_MD_Size           },
  { "md_new",              MBEDTLS_MD_New            },
  { "md_free",             MBEDTLS_MD_Free           },
  { "md_setup",            MBEDTLS_MD_Setup          },
  { "md_starts",           MBEDTLS_MD_Starts         },
  { "md_update",           MBEDTLS_MD_Update         },
  { "md_finish",           MBEDTLS_MD_Finish         },
  { "md_algorithms",       MBEDTLS_MD_Algorithms     },
  { NULL,                  NULL                      }
};

int luaopen_mbedtls_raw (lua_State *LuaState)
{
  luaL_newlib(LuaState, MBEDTLS_MD_FUNCTIONS);

  return 1; /* Number of values pushed on the stack */
}
