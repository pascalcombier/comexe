/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-libwin32.c                                                    *
 * CONTENT  Expose Windows utility functions to Lua                           *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* DOCUMENTATION                                                              */
/*============================================================================*/

/* This API is a RAW API, we basically call the win32 functions and return their
 * values. That's it. It's intended to be used from a kind of higher level
 * interface written in Lua. Lua being easier to modify, this strategy has been
 * chosen for easier long-term maintenance
 */

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/*---------*/
/* HEADERS */
/*---------*/

/* The external luaopen_wincom will be automatically generated, but it rely on
 * the type lua_State */
#include <lua.h>

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include <lauxlib.h>
#include <windows.h>

#include "comexe.h"

/*============================================================================*/
/*  WIN32 ADDONS                                                              */
/*============================================================================*/

#define lua_tostringcast(LuaState, Index, Type) \
  ((Type)lua_tostring(LuaState, Index))

#define luaL_checkstringcast(LuaState, Index, Type) \
  ((Type)luaL_checkstring(LuaState, Index))

#define luaL_toBOOL(LuaState, Index) \
  (lua_toboolean(LuaState, Index) ? TRUE : FALSE)

/*============================================================================*/
/* WIN32 ERROR MANAGEMENT                                                     */
/*============================================================================*/

static int WIN32_GetLastError (lua_State *LuaState)
{
  DWORD Error = GetLastError();

  lua_pushinteger(LuaState, Error);

  return 1; /* Number of values pushed on the stack */
}

static int WIN32_FormatMessageA (lua_State *LuaState)
{
  DWORD   Flags      = luaL_checkinteger(LuaState, 1);
  LPCVOID Source     = lua_touserdata(LuaState, 2);
  DWORD   MessageId  = luaL_checkinteger(LuaState, 3);
  DWORD   LanguageId = luaL_checkinteger(LuaState, 4);
  LPSTR   Buffer     = lua_touserdata(LuaState, 5);
  DWORD   BufferSize = luaL_checkinteger(LuaState, 6);
  
  DWORD Result = FormatMessageA(Flags,
                                Source,
                                MessageId,
                                LanguageId,
                                Buffer,
                                BufferSize,
                                NULL);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values pushed on the stack */
}

/*============================================================================*/
/* CONVERSION FUNCTIONS                                                       */
/*============================================================================*/

/* Note that while Lua string like StringUtf16 carry its own SizeInBytes it does
 * not carry the number of UTF characters
 */   
static int WIN32_WideCharToMultiByte (lua_State *LuaState)
{
  UINT   CodePage          = luaL_checkinteger(LuaState, 1);
  DWORD  Flags             = luaL_checkinteger(LuaState, 2);
  LPWSTR StringUtf16       = luaL_checkstringcast(LuaState, 3, LPWSTR);
  int    StringUtf16Length = luaL_checkinteger(LuaState, 4);
  LPSTR  Utf8Buffer        = lua_touserdata(LuaState, 5);
  int    Utf8BufferSize    = luaL_checkinteger(LuaState, 6);
  LPCCH  DefaultChar       = lua_tostringcast(LuaState, 7, LPCCH);
  BOOL   UsedDefaultChar   = luaL_toBOOL(LuaState, 8);

  int Result = WideCharToMultiByte(CodePage,
                                   Flags,
                                   StringUtf16,
                                   StringUtf16Length,
                                   Utf8Buffer,
                                   Utf8BufferSize,
                                   DefaultChar,
                                   &UsedDefaultChar);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values pushed on the stack */
}

static int WIN32_MultiByteToWideChar (lua_State *LuaState)
{
  UINT   CodePage          = luaL_checkinteger(LuaState, 1);
  DWORD  Flags             = luaL_checkinteger(LuaState, 2);
  LPCSTR StringUtf8        = luaL_checkstring(LuaState, 3);
  int    StringUtf8Size    = luaL_checkinteger(LuaState, 4);
  LPWSTR StringUtf16       = lua_touserdata(LuaState, 5);
  int    StringUtf16Length = luaL_checkinteger(LuaState, 6);
  
  /* We get StringUtf8Size as a parameter and not from luaL_checklstring on
   * purpose: we allow the user to specify -1 */
  
  int Result = MultiByteToWideChar(CodePage,
                                   Flags,
                                   StringUtf8,
                                   StringUtf8Size,
                                   StringUtf16,
                                   StringUtf16Length);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values pushed on the stack */
}

/*============================================================================*/
/* REGISTRY                                                                   */
/*============================================================================*/

/* Limitation: SecurityAttributes is not supported */
static int WIN32_RegCreateKeyEx (lua_State *LuaState)
{
  HKEY    RootKey          = (HKEY)luaL_checkinteger(LuaState, 1);
  LPCWSTR SubKeyUtf16      = luaL_checkstringcast(LuaState, 2, LPCWSTR);
  LPWSTR  ClassUtf16       = lua_tostringcast(LuaState, 3, LPWSTR);
  DWORD   Options          = luaL_checkinteger(LuaState, 4);
  REGSAM  Sam              = luaL_checkinteger(LuaState, 5);
  DWORD   Reserved         = 0;
  PVOID   SecurityAttrs    = NULL;
  HKEY    ResultKey        = NULL;
  DWORD   LocalDisposition = 0;
  LSTATUS Status;

  Status = RegCreateKeyExW(RootKey,
                           SubKeyUtf16,
                           Reserved,
                           ClassUtf16,
                           Options,
                           Sam,
                           SecurityAttrs,
                           &ResultKey,
                           &LocalDisposition);

  lua_pushinteger(LuaState, Status);
  lua_pushlightuserdata(LuaState, ResultKey);
  lua_pushinteger(LuaState, LocalDisposition);

  return 3; /* Number of values pushed on the stack */
}

static int WIN32_RegOpenKeyEx (lua_State *LuaState)
{
  HKEY    RootKey     = (HKEY)luaL_checkinteger(LuaState, 1);
  LPCWSTR SubKeyUtf16 = luaL_checkstringcast(LuaState, 2, LPCWSTR);
  DWORD   Options     = luaL_checkinteger(LuaState, 3);
  REGSAM  Sam         = luaL_checkinteger(LuaState, 4);
  HKEY    ResultKey   = NULL;
  LSTATUS Status;

  Status = RegOpenKeyExW(RootKey, SubKeyUtf16, Options, Sam, &ResultKey);

  lua_pushinteger(LuaState, Status);
  lua_pushlightuserdata(LuaState, ResultKey);

  return 2; /* Number of values pushed on the stack */
}

static int WIN32_RegCloseKey (lua_State *LuaState)
{
  HKEY    Key    = lua_touserdata(LuaState, 1);
  LSTATUS Status = RegCloseKey(Key);

  lua_pushinteger(LuaState, Status);

  return 1; /* Number of values pushed on the stack */
}

static int WIN32_RegQueryValueEx (lua_State *LuaState)
{
  HKEY    Key              = lua_touserdata(LuaState, 1);
  LPCWSTR ValueNameUtf16   = luaL_checkstringcast(LuaState, 2, LPCWSTR);
  LPBYTE  DataPointer      = lua_touserdata(LuaState, 3);
  DWORD   ValueSizeInBytes = luaL_checkinteger(LuaState, 4);
  LPDWORD Reserved         = NULL;
  DWORD   ValueType;
  LSTATUS Status;

  Status = RegQueryValueExW(Key, ValueNameUtf16, Reserved, &ValueType, DataPointer, &ValueSizeInBytes);

  lua_pushinteger(LuaState, Status);
  lua_pushinteger(LuaState, ValueType);
  lua_pushinteger(LuaState, ValueSizeInBytes);

  return 3; /* Number of values pushed on the stack */
}

/* Limitation: not the full RegQueryInfoKeyW function */
static int WIN32_RegQueryInfoKey (lua_State *LuaState)
{
  HKEY    Key = lua_touserdata(LuaState, 1);
  DWORD   SubKeyCount;
  DWORD   SubKeyMaxLength;
  LSTATUS Status;

  Status = RegQueryInfoKeyW(Key,
                            NULL,
                            NULL,
                            NULL,
                            &SubKeyCount,
                            &SubKeyMaxLength,
                            NULL,
                            NULL,
                            NULL,
                            NULL,
                            NULL,
                            NULL);

  lua_pushinteger(LuaState, Status);
  lua_pushinteger(LuaState, SubKeyCount);
  lua_pushinteger(LuaState, SubKeyMaxLength);

  return 3; /* Number of values pushed on the stack */
}

/* Limitation: not the full RegEnumKeyExW function */
static int WIN32_RegEnumKeyEx (lua_State *LuaState)
{
  HKEY    Key           = lua_touserdata(LuaState, 1);
  DWORD   Index         = luaL_checkinteger(LuaState, 2);
  LPWSTR  NameBuffer    = lua_touserdata(LuaState, 3);
  DWORD   NameCharCount = luaL_checkinteger(LuaState, 4);
  LSTATUS Status;

  Status = RegEnumKeyExW(Key,
                         Index,
                         NameBuffer,
                         &NameCharCount,
                         NULL,
                         NULL,
                         NULL,
                         NULL);

  lua_pushinteger(LuaState, Status);
  lua_pushinteger(LuaState, NameCharCount);

  return 2; /* Number of values pushed on the stack */
}

static int WIN32_RegDeleteKey (lua_State *LuaState)
{
  HKEY    RootKey     = (HKEY)luaL_checkinteger(LuaState, 1);
  LPCWSTR SubKeyUtf16 = luaL_checkstringcast(LuaState, 2, LPCWSTR);
  LSTATUS Status;

  Status = RegDeleteKeyW(RootKey, SubKeyUtf16);

  lua_pushinteger(LuaState, Status);

  return 1; /* Number of values pushed on the stack */
}

static int WIN32_RegSetValueEx (lua_State *LuaState)
{
  HKEY    Key              = lua_touserdata(LuaState, 1);
  LPCWSTR ValueName        = luaL_checkstringcast(LuaState, 2, LPCWSTR);
  LPBYTE  DataPointer      = lua_touserdata(LuaState, 3);
  DWORD   ValueSizeInBytes = luaL_checkinteger(LuaState, 4);
  DWORD   ValueType        = luaL_checkinteger(LuaState, 5);
  DWORD   Reserved         = 0;
  LSTATUS Status;

  Status = RegSetValueExW(Key, ValueName, Reserved, ValueType, DataPointer, ValueSizeInBytes);

  lua_pushinteger(LuaState, Status);

  return 1; /* Number of values pushed on the stack */
}

static int WIN32_RegEnumValue (lua_State *LuaState)
{
  HKEY    Key             = lua_touserdata(LuaState, 1);
  DWORD   ValueOffset     = luaL_checkinteger(LuaState, 2);
  LPWSTR  NameUtf16       = lua_touserdata(LuaState, 3);
  DWORD   NameCharCount   = luaL_checkinteger(LuaState, 4);
  LPBYTE  Data            = lua_touserdata(LuaState, 5);
  DWORD   DataSizeInBytes = luaL_checkinteger(LuaState, 6);
  LPDWORD Reserved        = NULL;
  DWORD   ValueType;
  LSTATUS Status;
  
  Status = RegEnumValueW(Key,
                         ValueOffset,
                         NameUtf16,
                         &NameCharCount,
                         Reserved,
                         &ValueType,
                         Data,
                         &DataSizeInBytes);

  lua_pushinteger(LuaState, Status);
  lua_pushinteger(LuaState, ValueType);
  lua_pushinteger(LuaState, NameCharCount);
  lua_pushinteger(LuaState, DataSizeInBytes);

  return 4; /* Number of values pushed on the stack */
}

static int WIN32_RegDeleteValue (lua_State *LuaState)
{
  HKEY    Key            = lua_touserdata(LuaState, 1);
  LPCWSTR ValueNameUtf16 = luaL_checkstringcast(LuaState, 2, LPCWSTR);
  LSTATUS Status;

  Status = RegDeleteValueW(Key, ValueNameUtf16);

  lua_pushinteger(LuaState, Status);

  return 1; /* Number of values pushed on the stack */
}

/* Sinmce we don't implement RegOpenKeyTransacted, we have to implement a way to
 * flush keys, without that, if one write a value and read immediatly after, the
 * read value might be the previous one
 */
static int WIN32_RegFlushKey (lua_State *LuaState)
{
  HKEY    Key    = lua_touserdata(LuaState, 1);
  LSTATUS Status = RegFlushKey(Key);

  lua_pushinteger(LuaState, Status);

  return 1; /* Number of values pushed on the stack */
}

/*============================================================================*/
/* MISCELLANEOUS                                                              */
/*============================================================================*/

static int WIN32_ExpandEnvironmentStrings (lua_State *LuaState)
{
  LPCWSTR InputStringUtf16  = luaL_checkstringcast(LuaState, 1, LPCWSTR);
  LPWSTR  OutputBufferUtf16 = lua_touserdata(LuaState, 2);
  DWORD   BufferSizeInBytes = luaL_checkinteger(LuaState, 3);

  DWORD Result = ExpandEnvironmentStringsW(InputStringUtf16, OutputBufferUtf16, BufferSizeInBytes);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values pushed on the stack */
}

static int WIN32_ShellExecuteEx (lua_State *LuaState)
{
  LPCWSTR           StringVerbUtf16   = lua_tostringcast(LuaState, 1, LPCWSTR);
  LPCWSTR           StringFileUtf16   = lua_tostringcast(LuaState, 2, LPCWSTR);
  LPCWSTR           StringParamsUtf16 = lua_tostringcast(LuaState, 3, LPCWSTR);
  LPCWSTR           StringDirUtf16    = lua_tostringcast(LuaState, 4, LPCWSTR);
  int               ShowCmd           = luaL_checkinteger(LuaState, 5);
  BOOL              WaitForProcess;
  SHELLEXECUTEINFOW ShellExecuteInfo;
  HANDLE            Process;
  BOOL              Success;
  DWORD             ExitCode;

  if (lua_isnone(LuaState, 6))
  {
    WaitForProcess = TRUE;
  }
  else
  {
    WaitForProcess = luaL_toBOOL(LuaState, 6);
  }

  ZeroMemory(&ShellExecuteInfo, sizeof(ShellExecuteInfo));
  
  ShellExecuteInfo.cbSize       = sizeof(ShellExecuteInfo);
  ShellExecuteInfo.fMask        = SEE_MASK_NOCLOSEPROCESS;
  ShellExecuteInfo.hwnd         = NULL;
  ShellExecuteInfo.lpVerb       = StringVerbUtf16;
  ShellExecuteInfo.lpFile       = StringFileUtf16;
  ShellExecuteInfo.lpParameters = StringParamsUtf16;
  ShellExecuteInfo.lpDirectory  = StringDirUtf16;
  ShellExecuteInfo.nShow        = ShowCmd;
  ShellExecuteInfo.hInstApp     = NULL;
  ShellExecuteInfo.hProcess     = NULL;

  Success = ShellExecuteExW(&ShellExecuteInfo);

  if (Success)
  {
    Process = ShellExecuteInfo.hProcess;

    if (Process)
    {
      if (WaitForProcess)
      {
        WaitForSingleObject(Process, INFINITE);

        if (GetExitCodeProcess(Process, &ExitCode))
        {
          lua_pushboolean(LuaState, 1);
          lua_pushinteger(LuaState, ExitCode);
        }
        else
        {
          lua_pushboolean(LuaState, 1);
          lua_pushnil(LuaState);
        }
      }
      else
      {
        /* Do not wait: return success and no exit code */
        lua_pushboolean(LuaState, 1);
        lua_pushnil(LuaState);
      }

      CloseHandle(Process);
    }
    else
    {
      lua_pushboolean(LuaState, 1);
      lua_pushnil(LuaState);
    }
  }
  else
  {
    lua_pushboolean(LuaState, 0);
    lua_pushnil(LuaState);
  }

  return 2; /* Number of values pushed on the stack */
}

/*============================================================================*/
/* PUBLIC API                                                                 */
/*============================================================================*/

static const struct luaL_Reg WIN32_FUNCTIONS[] =
{
  /* Error management */
  {"getlasterror",   WIN32_GetLastError   },
  {"formatmessageA", WIN32_FormatMessageA },
  /* Unicode */
  {"widechartomultibyte", WIN32_WideCharToMultiByte },
  {"multibytetowidechar", WIN32_MultiByteToWideChar },
  /* Registry */
  {"regcreatekeyex",  WIN32_RegCreateKeyEx        },
  {"regopenkeyex",    WIN32_RegOpenKeyEx          },
  {"regclosekey",     WIN32_RegCloseKey           },
  {"regqueryvalueex", WIN32_RegQueryValueEx       },
  {"regqueryinfokey", WIN32_RegQueryInfoKey       },
  {"regenumkeyex",    WIN32_RegEnumKeyEx          },
  {"regdeletekey",    WIN32_RegDeleteKey          },
  {"regsetvalueex",   WIN32_RegSetValueEx         },
  {"regenumvalue",    WIN32_RegEnumValue          },
  {"regdeletevalue",  WIN32_RegDeleteValue        },
  {"regflushkey",     WIN32_RegFlushKey           },
  /* Miscellaneous */
  {"expandenvironmentstrings", WIN32_ExpandEnvironmentStrings },
  {"shellexecute",             WIN32_ShellExecuteEx           },
  /* End of list */
  {NULL, NULL}
};

int luaopen_win32 (lua_State *LuaState)
{
  luaL_newlib(LuaState, WIN32_FUNCTIONS);
  
  return 1; /* Number of values pushed on the stack */
}
