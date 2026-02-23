/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-libbuffer.c                                                   *
 * CONTENT  Expose C-side growing buffer to Lua                               *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* DOCUMENTATION                                                              */
/*============================================================================*/

/**
 * PB_Buffer is a buffer which grows as needed, with its ensurecapacity()
 * function, potentially returning a new pointer like the function realloc().
 *
 * This buffer APIis simply providing a light user-data PB_Buffer, the idea was
 * to provide a high-level API, implemented on the Lua side. That Lua object
 * wiil resize and update the pointer when ensurecapacity() is called. Seemed
 * pretty straight-forward.
 *
 * That implies something: the buffer capacity need to be calculated on Lua
 * side.
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

#include <stdint.h>  /* uint8_t     */
#include <lauxlib.h> /* luaL_newlib */
#include <string.h>  /* memcpy      */

#include "comexe.h" /* PB_Buffer */

/*============================================================================*/
/* CONFIGURATION                                                              */
/*============================================================================*/

#define BUFFER_DEFAULT_INIT_SIZE 4096

/*============================================================================*/
/* PRIVATE DATA                                                               */
/*============================================================================*/

static struct PB_Allocator BUFFER_Allocator =
{
  PLAT_GetPageSizeInBytes,
  PLAT_SafeAlloc0,
  PLAT_Free,
  PLAT_SafeRealloc
};

/*============================================================================*/
/* MACROS                                                                     */
/*============================================================================*/

#define BUF_MAX(a, b) ((a) > (b) ? (a) : (b))

/*============================================================================*/
/* RAW BUFFER API                                                             */
/*============================================================================*/

/* That function intentionally looks weird to fit 80 on columns */
static int BUFFER_NewBuffer (lua_State *LuaState)
{
  size_t            SizeInBytes;
  struct PB_Buffer *NewBuffer;
  
  SizeInBytes = luaL_optinteger(LuaState, 1, BUFFER_DEFAULT_INIT_SIZE);
  NewBuffer   = PB_NewBuffer(&BUFFER_Allocator, SizeInBytes);

  lua_pushlightuserdata(LuaState, NewBuffer);

  return 1; /* Number of values pushed on the stack */
}

static int BUFFER_GetBufferCapacity (lua_State *LuaState)
{
  struct PB_Buffer *Buffer   = lua_touserdata(LuaState, 1);
  size_t            Capacity = PB_GetCapacity(Buffer);
  
  lua_pushinteger(LuaState, Capacity);
  
  return 1; /* Number of values pushed on the stack */
}

static int BUFFER_EnsureBufferCapacity (lua_State *LuaState)
{
  struct PB_Buffer *Buffer         = lua_touserdata(LuaState, 1);
  size_t            NeededCapacity = luaL_checkinteger(LuaState, 2);
  struct PB_Buffer *NewBuffer      = PB_EnsureCapacity(Buffer, NeededCapacity);
  
  lua_pushlightuserdata(LuaState, NewBuffer);
  
  return 1; /* Number of values pushed on the stack */
}

static int BUFFER_GetBufferData (lua_State *LuaState)
{
  struct PB_Buffer *Buffer = lua_touserdata(LuaState, 1);
  int               Offset = luaL_optinteger(LuaState, 2, 0);
  uint8_t          *Data   = PB_GetData(Buffer);
  
  lua_pushlightuserdata(LuaState, &Data[Offset]);
  
  return 1; /* Number of values pushed on the stack */
}

static int BUFFER_FreeBuffer (lua_State *LuaState)
{
  struct PB_Buffer *Buffer = lua_touserdata(LuaState, 1);
  
  PB_FreeBuffer(Buffer);

  return 0; /* Number of values pushed on the stack */
}

static int BUFFER_ReadBuffer (lua_State *LuaState)
{
  struct PB_Buffer *Buffer     = lua_touserdata(LuaState, 1);
  int               IndexStart = luaL_checkinteger(LuaState, 2);
  int               IndexEnd   = luaL_checkinteger(LuaState, 3);
  const uint8_t    *Data;
  size_t            Offset;
  size_t            Count;

  IndexStart = BUF_MAX(IndexStart, 1);

  if (IndexStart > IndexEnd)
  {
    lua_pushlstring(LuaState, "", 0);
  }
  else
  {
    Data   = PB_GetData(Buffer);
    Offset = (IndexStart - 1);
    Count  = (IndexEnd - IndexStart + 1);

    lua_pushlstring(LuaState, (const char *)&Data[Offset], Count);
  }

  return 1; /* Number of values pushed on the stack */
}

/* Write(Buffer, Data, OptionalIndex) */
static int BUFFER_WriteBuffer (lua_State *LuaState)
{
  size_t            DataLen;
  struct PB_Buffer *Buffer = lua_touserdata(LuaState, 1);
  const char       *Input  = luaL_checklstring(LuaState, 2, &DataLen);
  int               Index  = luaL_optinteger(LuaState, 3, 1);
  char             *Output;
  size_t            Offset;
  size_t            NeededCapacity;

  if (DataLen > 0)
  {
    Index          = BUF_MAX(Index, 1);
    Offset         = (Index - 1);
    NeededCapacity = (Offset + DataLen);

    Buffer = PB_EnsureCapacity(Buffer, NeededCapacity);
    Output = PB_GetData(Buffer);

    memcpy(&Output[Offset], Input, DataLen);

    lua_pushlightuserdata(LuaState, Buffer);
    lua_pushinteger(LuaState, DataLen);
  }
  else
  {
    lua_pushnil(LuaState);
    lua_pushnil(LuaState);
  }

  return 2; /* Number of values pushed on the stack */
}

/*============================================================================*/
/* PUBLIC INTERFACE                                                           */
/*============================================================================*/

static const struct luaL_Reg BUFFER_FUNCTIONS[] =
{
  { "newbuffer",      BUFFER_NewBuffer            },
  { "getcapacity",    BUFFER_GetBufferCapacity    },
  { "ensurecapacity", BUFFER_EnsureBufferCapacity },
  { "getbufferdata",  BUFFER_GetBufferData        },
  { "freebuffer",     BUFFER_FreeBuffer           },
  { "read",           BUFFER_ReadBuffer           },
  { "write",          BUFFER_WriteBuffer          },
  { NULL,             NULL                        }
};

int luaopen_buffer (lua_State *LuaState)
{
  luaL_newlib(LuaState, BUFFER_FUNCTIONS);

  return 1; /* Number of values pushed on the stack */
}
