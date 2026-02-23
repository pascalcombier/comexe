/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-service-win32.c                                               *
 * CONTENT  Windows service integration for Lua                               *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/* DOCUMENTATION
 *
 * This file provide a support to interface with Windows service sc.exe.
 *
 * This implementation has limitations:
 *   Only the first instance/thread will receive the SERVICE notifications.
 *   RegisterServiceCtrlHandler is pretty much a global thing, single-threaded
 *
 * For simplicity, we just use global variables and provide only 2 functions:
 *   SERVICE_Initialize to set the global struct LUA_Application
 *   luaopen_service for Lua state registration
 *
 * To notify the Lua side, only 1 function: SERVICE_NotifyInstance
 * This is implemented in lua-application.c
 *
 * The great thing about that implementation is that it's really easy to drop,
 * the coupling with lua-application.c is minimal.
 * 
 * API RATIONALE
 *
 * Why SERVICE_Start takes 2 strings corresponding to Lua function names instead
 * of taking 2 Lua functions?
 *
 * The Win32 API makes SERVICE_CtrlHandler being called by an external thread,
 * at any time. So that SERVICE_CtrlHandler is called when SERVICE_Main is
 * running (and blocking: probably in a Lua event loop RunLoop, or luv loop or
 * maybe Copas loop).
 *
 * For that reason, we need a async way to notify that SERVICE_Main about the
 * event. We use the available COM Events for that purpose with
 * SERVICE_NotifyInstance which basically enqueue an event, by design it's just
 * a string corresponding to a global function.
 *
 * By symmetry, SERVICE_Main also use a string for the other parameter. So: 2
 * strings in place of 2 Lua functions.
 */

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/*---------*/
/* HEADERS */
/*---------*/

/* The external luaopen_service declaration require lua_State */
#include <lua.h>

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <lua.h>     /* lua_State       */
#include <lauxlib.h> /* luaL_optinteger */
#include <stdio.h>   /* fprintf */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "comexe.h"

/*============================================================================*/
/*  WIN32 ADDONS                                                              */
/*============================================================================*/

#define luaL_checklstringcast(LuaState, Index, Type, LenPtr) \
  ((Type)luaL_checklstring(LuaState, Index, LenPtr))

/*============================================================================*/
/* CONSTANTS                                                                  */
/*============================================================================*/

static struct PB_Allocator SERVICE_Allocator =
{
  PLAT_GetPageSizeInBytes,
  PLAT_SafeAlloc0,
  PLAT_Free,
  PLAT_SafeRealloc
};

/*============================================================================*/
/* GLOBAL VARIABLES                                                           */
/*============================================================================*/

/* The only place in ComEXE with so many global variables */

static struct LUA_Application *SERVICE_Application;
static lua_State              *SERVICE_LuaState;
static SERVICE_STATUS_HANDLE   SERVICE_Handle;
static SERVICE_STATUS          SERVICE_Status;

/* Store all the strings inside SERVICE_Buffer */
static struct PB_Buffer *SERVICE_Buffer;
static size_t            SERVICE_WriteOffset;

static LPWSTR SERVICE_Name;
static char  *SERVICE_Win32EventName;
static char  *SERVICE_UserMainFunctionName;

/*============================================================================*/
/* STANDARD LIBRARIES ADDONS                                                  */
/*============================================================================*/

static void SERVICE_EnsureBufferCapacity (size_t NeededSizeInBytes)
{
  if (SERVICE_Buffer == 0)
  {
    SERVICE_Buffer      = PB_NewBuffer(&SERVICE_Allocator, NeededSizeInBytes);
    SERVICE_WriteOffset = 0;
  }
  else
  {
    PB_EnsureCapacity(SERVICE_Buffer, NeededSizeInBytes);
  }
}

/* Assume there is enough space (PB_EnsureCapacity already called) */
static LPWSTR SERVICE_AllocStringUtf16 (LPCWSTR Data, size_t SizeInBytes)
{
  char *Buffer         = PB_GetData(SERVICE_Buffer);
  char *NewStringBytes = (Buffer + SERVICE_WriteOffset);

  memcpy(NewStringBytes, (const char *)Data, SizeInBytes);

  /* Append null terminator */
  NewStringBytes[SizeInBytes + 0] = '\0';
  NewStringBytes[SizeInBytes + 1] = '\0';

  /* Advance by bytes copied + two zero bytes */
  SERVICE_WriteOffset += (SizeInBytes + 2);

  return (LPWSTR)NewStringBytes;
}

/* Assume there is enough space (PB_EnsureCapacity already called) */
static char *SERVICE_AllocStringUtf8 (const char *String, size_t SizeInBytes)
{
  char *Buffer    = PB_GetData(SERVICE_Buffer);
  char *NewString = (Buffer + SERVICE_WriteOffset);
  
  memcpy(NewString, String, SizeInBytes);
  NewString[SizeInBytes] = '\0';
  
  SERVICE_WriteOffset += (SizeInBytes + 1);
  
  return NewString;
}

/*============================================================================*/
/* SERVICE FUNCTIONS                                                          */
/*============================================================================*/

static BOOL SERVICE_ReportStatus (DWORD dwCurrentState, DWORD dwWaitHint)
{
  BOOL Success;

  SERVICE_Status.dwCurrentState = dwCurrentState;
  SERVICE_Status.dwWaitHint     = dwWaitHint;

  Success = SetServiceStatus(SERVICE_Handle, &SERVICE_Status);

  return Success;
}

/* This function is not called in the same thread. So we cannot just interact
 * with Lua state directly, we need to work asynchronously, in our case we use
 * the existing com event system. */
static void WINAPI SERVICE_CtrlHandler (DWORD CtrlCode)
{
  /* Simply translate to the Lua instance */
  SERVICE_NotifyInstance(SERVICE_Application, SERVICE_Win32EventName, CtrlCode);
}

/* While for the most part, the Win32 API is implemented in a very RAW style,
 * simply exposing the Win32 API like SERVICE_SetStatus or
 * SERVICE_ReportError. Doing the same here make things way more complex,
 * essentially because the inputs to RegisterServiceCtrlHandlerW involve the
 * table SERVICE_CtrlHandler that would need to interface between C/Lua leading
 * to unwanted complexity.
 */
static void WINAPI SERVICE_Main (DWORD argc, LPWSTR *argv)
{
  const char *ErrorMessage;
  
  (void)argc; /* Unused parameter */
  (void)argv; /* Unused parameter */

  SERVICE_Handle = RegisterServiceCtrlHandlerW(SERVICE_Name, SERVICE_CtrlHandler);

  if (SERVICE_Handle == 0)
  {
    fprintf(stderr, "ERROR: Failed to register service control handler (GetLastError=%lu)\n", GetLastError());
  }
  else
  {
    ZeroMemory(&SERVICE_Status, sizeof(SERVICE_Status));
  
    SERVICE_Status.dwServiceType             = SERVICE_WIN32_OWN_PROCESS;
    SERVICE_Status.dwControlsAccepted        = (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
    SERVICE_Status.dwCurrentState            = SERVICE_START_PENDING;
    SERVICE_Status.dwWin32ExitCode           = NO_ERROR;
    SERVICE_Status.dwServiceSpecificExitCode = NO_ERROR;
    SERVICE_Status.dwCheckPoint              = 0;
    SERVICE_Status.dwWaitHint                = 0;

    /* Give Windows an estimate of 3000ms to start the service */
    SERVICE_ReportStatus(SERVICE_START_PENDING, 3000);
    SERVICE_ReportStatus(SERVICE_RUNNING,       0);

    /* Call the user-specified Lua function */
    lua_getglobal(SERVICE_LuaState, SERVICE_UserMainFunctionName);
    
    if (lua_isfunction(SERVICE_LuaState, -1))
    {
      if (lua_pcall(SERVICE_LuaState, 0, 0, 0) != LUA_OK)
      {
        ErrorMessage = lua_tostring(SERVICE_LuaState, -1);
        fprintf(stderr, "Service error: %s\n", ErrorMessage);
        lua_pop(SERVICE_LuaState, 1);
      }
    }
    else
    {
      /* Not a function */
      lua_pop(SERVICE_LuaState, 1);
    }

    SERVICE_ReportStatus(SERVICE_STOPPED, 0);
  }
}

static SERVICE_TABLE_ENTRYW SERVICE_Table[] =
{
  { NULL, SERVICE_Main },
  { NULL, NULL }
};

/* This function will call StartServiceCtrlDispatcherW which will call the main function */
static int SERVICE_Start (lua_State *LuaState)
{
  size_t ServiceNameLength;
  size_t Win32EventNameLength;
  size_t MainFunctionNameLength;
  
  LPCWSTR     ServiceNameUtf16     = luaL_checklstringcast(LuaState, 1, LPCWSTR, &ServiceNameLength);
  const char *Win32EventNameUtf8   = luaL_checklstring(LuaState, 2, &Win32EventNameLength);
  const char *MainFunctionNameUtf8 = luaL_checklstring(LuaState, 3, &MainFunctionNameLength);

  size_t WideServiceBytes = ServiceNameLength;
  size_t TotalSizeInBytes = (WideServiceBytes + 2 + Win32EventNameLength + 1 + MainFunctionNameLength + 1);
  SERVICE_EnsureBufferCapacity(TotalSizeInBytes);

  /* Service is started, erase previous strings */
  SERVICE_WriteOffset = 0;

  /* Copy strings */
  SERVICE_Name                 = SERVICE_AllocStringUtf16(ServiceNameUtf16,    ServiceNameLength);
  SERVICE_Win32EventName       = SERVICE_AllocStringUtf8(Win32EventNameUtf8,   Win32EventNameLength);
  SERVICE_UserMainFunctionName = SERVICE_AllocStringUtf8(MainFunctionNameUtf8, MainFunctionNameLength);

  /* We first allocate ServiceNameUtf16 so we know it's properly aligned */

  /* Global Lua State */
  SERVICE_LuaState = LuaState;

  /* Set the service name */
  SERVICE_Table[0].lpServiceName = SERVICE_Name;
  
  if (StartServiceCtrlDispatcherW(SERVICE_Table))
  {
    lua_pushboolean(LuaState, 1);
    lua_pushnil(LuaState);
  }
  else
  {
    lua_pushboolean(LuaState, 0);
    lua_pushinteger(LuaState, GetLastError());
  }
  
  return 2; /* Number of values returned on the stack */
}

static int SERVICE_SetStatus (lua_State *LuaState)
{
  DWORD Status   = luaL_checkinteger(LuaState, 1);
  DWORD WaitHint = luaL_checkinteger(LuaState, 2);
  BOOL  Success  = SERVICE_ReportStatus(Status, WaitHint);

  if (Success)
  {
    lua_pushboolean(LuaState, 1);
  }
  else
  {
    lua_pushboolean(LuaState, 0);
  }

  return 1; /* Number of values returned on the stack */
}

static int SERVICE_ReportError (lua_State *LuaState)
{
  DWORD ExitCode         = luaL_checkinteger(LuaState, 1);
  DWORD ServiceErrorCode = luaL_checkinteger(LuaState, 2);
  BOOL  Success;
  
  SERVICE_Status.dwWin32ExitCode           = ExitCode;
  SERVICE_Status.dwServiceSpecificExitCode = ServiceErrorCode;

  Success = SetServiceStatus(SERVICE_Handle, &SERVICE_Status);
  
  if (Success)
  {
    lua_pushboolean(LuaState, 1);
  }
  else
  {
    lua_pushboolean(LuaState, 0);
  }

  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* ENTRY POINTS                                                               */
/*============================================================================*/

static const struct luaL_Reg SERVICE_FUNCTIONS[] =
{
  { "start",       SERVICE_Start       },
  { "setstatus",   SERVICE_SetStatus   },
  { "reporterror", SERVICE_ReportError },
  { NULL, NULL }
};

/* Single entry point: called by lua-application.c to set the global variable
 * Application
 */
extern void SERVICE_Initialize (struct LUA_Application *Application)
{
  SERVICE_Application = Application;
  /* Do not allocate SERVICE_Buffer here, most applications don't need to
   * implement a service, service will be allocated when needed in
   * SERVICE_Start */
}

extern int luaopen_service (lua_State *LuaState)
{
  luaL_newlib(LuaState, SERVICE_FUNCTIONS);

  return 1; /* Number of values returned on the stack */
}
