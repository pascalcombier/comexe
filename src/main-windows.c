/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME main-windows.c                                                    *
 * CONTENT  Main function                                                     *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/* This main file is a little bit over complicated. It's mainly due to UTF
 * management. We want ComEXE to be usable even on unicode-named directories.
 *
 * Note that Lua is implemented with C standard fopen/fclose, it does not work
 * properly for UTF paths in the file names. For that, we would need to use
 * Windows functions
 *
 * If one want Lua to properly display those UTF-8 encodings strings in the
 * terminal, one could you the following command before running lua55ce
 * > chcp 65001
 *
 * Instead, we chosed to call:
 *   SetConsoleOutputCP(65001)
 *   SetConsoleCP(65001);
 */

/*============================================================================*/
/* HEADERS                                                                    */
/*============================================================================*/

#include <stdlib.h>            /* EXIT_SUCCESS              */
#include <stdio.h>             /* printf                    */
#include <string.h>            /* strcmp                    */
#include <stdbool.h>           /* bool                      */
#include <winsock2.h>          /* fix libuv warning         */
#include <windows.h>           /* timeBeginPeriod           */
#include <shellscalingapi.h>   /* SetProcessDpiAwareness    */
#include <uv.h>                /* uv_mutex_init             */
#include <psa/crypto.h>        /* psa_crypto_init           */
#include <mbedtls/threading.h> /* mbedtls_threading_set_alt */

#include "comexe.h"
#include "version.h"

/* Define the version short name */
#if defined(COMEXE_DBG)
#define COMEXE_BUILD_TYPE "cmd-dbg"
#elif defined(COMEXE_CON)
#define COMEXE_BUILD_TYPE "cmd-con"
#elif defined(COMEXE_GUI)
#define COMEXE_BUILD_TYPE "cmd-gui"
#else
#error "Unknown build type"
#endif

/*============================================================================*/
/* TYPES                                                                      */
/*============================================================================*/

/* The SetProcessDpiAwareness could be statically linked, but the program will
 * not run before Windows 8.1 (NTDDI_WINBLUE).
 *
 * So we do the function fetching at runtime and call if available.
 */

typedef HRESULT (WINAPI *SetProcessDpiAwarenessPointer)(PROCESS_DPI_AWARENESS);

/*============================================================================*/
/* STATIC DATA                                                                */
/*============================================================================*/

static HMODULE                       MAIN_ShCoreDll              = NULL;
static SetProcessDpiAwarenessPointer MAIN_SetProcessDpiAwareness = NULL;

/* Saved console code pages so we can restore them on exit */
static UINT MAIN_OldOutputCP = 0;
static UINT MAIN_OldInputCP  = 0;

static struct PB_Allocator MAIN_Allocator =
{
  PLAT_GetPageSizeInBytes,
  PLAT_SafeAlloc0,
  PLAT_Free,
  PLAT_SafeRealloc
};

/*============================================================================*/
/* MBEDTLS THREADING API                                                      */
/*============================================================================*/

/* The callbacks should return 0 on success */

static int MAIN_MutexInitialize (mbedtls_platform_mutex_t *Mutex)
{
  uv_mutex_init(&Mutex->Mutex);

  return 0;
}

static void MAIN_MutexFree (mbedtls_platform_mutex_t *Mutex)
{
  uv_mutex_destroy(&Mutex->Mutex);
}

static int MAIN_MutexLock (mbedtls_platform_mutex_t *Mutex)
{
  uv_mutex_lock(&Mutex->Mutex);
  
  return 0;
}

static int MAIN_MutexUnlock (mbedtls_platform_mutex_t *Mutex)
{
  uv_mutex_unlock(&Mutex->Mutex);
  
  return 0;
}

static int MAIN_ConditionInitialize (mbedtls_platform_condition_variable_t *Cond)
{
  uv_cond_init(&Cond->Condition);
  
  return 0;
}

static void MAIN_ConditionFree (mbedtls_platform_condition_variable_t *Cond)
{
  uv_cond_destroy(&Cond->Condition);
}

static int MAIN_ConditionSignal (mbedtls_platform_condition_variable_t *Cond)
{
  uv_cond_signal(&Cond->Condition);
  
  return 0;
}

static int MAIN_ConditionBroadcast (mbedtls_platform_condition_variable_t *Cond)
{
  uv_cond_broadcast(&Cond->Condition);
  
  return 0;
}

static int MAIN_ConditionWait (mbedtls_platform_condition_variable_t *Cond,
                               mbedtls_platform_mutex_t              *Mutex)
{
  uv_cond_wait(&Cond->Condition, &Mutex->Mutex);
  
  return 0;
}

static void MAIN_InitializeMbedtls ()
{
  /* According to third-party\src\mbedtls\src\tf-psa-crypto\include\psa\crypto_config.h */
  /* mbedtls_threading_set_alt need to be called before psa_crypto_init */

  mbedtls_threading_set_alt(MAIN_MutexInitialize,
                            MAIN_MutexFree,
                            MAIN_MutexLock,
                            MAIN_MutexUnlock,
                            MAIN_ConditionInitialize,
                            MAIN_ConditionFree,
                            MAIN_ConditionSignal,
                            MAIN_ConditionBroadcast,
                            MAIN_ConditionWait);
  
  psa_crypto_init();
}

static void MAIN_FreeMbedtls ()
{
  /* mbedtls */
  mbedtls_threading_free_alt();
}

/*============================================================================*/
/* PRIVATE FUNCTIONS                                                          */
/*============================================================================*/

/* Return a newly allocated UTF-8 string from the given Utf16String */
static char *MAIN_ConvertString (struct PB_Buffer **BufferPointer,
                                 LPCWCH             Utf16String)
{
  struct PB_Buffer *Buffer = *BufferPointer;
  int               SizeInBytes;
  char             *BufferUtf8;
  char             *NewUtf8String;

  /* Determine required UTF-8 size (including NULL terminator) */
  SizeInBytes = WideCharToMultiByte(CP_UTF8,     /* CodePage          */
                                    0,           /* DwFlags           */
                                    Utf16String, /* lpWideCharStr     */
                                    -1,          /* cchWideChar       */
                                    NULL,        /* lpMultiByteStr    */
                                    0,           /* cchMultiByte      */
                                    NULL,        /* lpDefaultChar     */
                                    NULL);       /* lpUsedDefaultChar */

  /* Ensure space for 1 NULL terminator */
  if (SizeInBytes <= 0)
  {
    SizeInBytes = 1;
  }

  /* Retrieve pointer to the destination UTF-8 location */
  Buffer     = PB_EnsureCapacity(Buffer, SizeInBytes);
  BufferUtf8 = PB_GetData(Buffer);

  /* Convert UTF-16 into UTF-8 at the offset */
  WideCharToMultiByte(CP_UTF8,     /* CodePage          */
                      0,           /* DwFlags           */
                      Utf16String, /* lpWideCharStr     */
                      -1,          /* cchWideChar       */
                      BufferUtf8,  /* lpMultiByteStr    */
                      SizeInBytes, /* cchMultiByte      */
                      NULL,        /* lpDefaultChar     */
                      NULL);       /* lpUsedDefaultChar */

  /* Duplicate the resulting UTF-8 string onto the heap */
  NewUtf8String = PLAT_StrDup(BufferUtf8);

  /* Buffer might have been relocated by PB_EnsureCapacity */
  *BufferPointer = Buffer;

  return NewUtf8String;
}

/* Use libuv for simplicity */
static char *MAIN_NormalizeArgv0 (struct PB_Buffer **BufferPointer,
                                  const char        *Argv0)
{
  /* We need a **BufferPointer because PB_EnsureCapacity may reallocate the buffer */
  struct PB_Buffer *Buffer;
  char             *PathBuffer;
  size_t            SizeInBytes;
  size_t            Argv0Length;
  int               Result;

  Buffer = *BufferPointer;

  /* Ensure buffer space */
  Buffer      = PB_EnsureCapacity(Buffer, (PATH_MAX + 1));
  PathBuffer  = PB_GetData(Buffer);
  SizeInBytes = PB_GetCapacity(Buffer);

  Result = uv_exepath(PathBuffer, &SizeInBytes);
  
  if (Result != 0)
  {
    /* Fallback to Argv0 if uv_exepath fails, not clear why it would fail */
    /* third-party\src\libuv\src\win\util.c */
    Argv0Length = strlen(Argv0);
    Buffer      = PB_EnsureCapacity(Buffer, (Argv0Length + 1));
    PathBuffer  = PB_GetData(Buffer);
    memcpy(PathBuffer, Argv0, (Argv0Length + 1));
  }

  *BufferPointer = Buffer;

  return PathBuffer;
}

static void MAIN_InitializeApplication ()
{
  MAIN_InitializeMbedtls();
        
  /* Save current console code pages */
  MAIN_OldOutputCP = GetConsoleOutputCP();
  MAIN_OldInputCP  = GetConsoleCP();

  /* Switch to UTF-8 */
  SetConsoleOutputCP(65001);
  SetConsoleCP(65001);
  
  /* Increase scheduling precision */
  timeBeginPeriod(1);

  /* For GUI applications: dynamically load SetProcessDpiAwareness */
  MAIN_ShCoreDll = LoadLibrary("shcore.dll");

  /* Call if the function exists */
  if (MAIN_ShCoreDll)
  {
    MAIN_SetProcessDpiAwareness = (SetProcessDpiAwarenessPointer)
      (void *)GetProcAddress(MAIN_ShCoreDll, "SetProcessDpiAwareness");
    
    if (MAIN_SetProcessDpiAwareness)
    {
      MAIN_SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE);
    }
  }
}

static void MAIN_DeInitializeApplication ()
{
  MAIN_FreeMbedtls();
  
  /* Release scheduling precision */
  timeEndPeriod(1);

  /* Free shcore.dll if loaded */
  if (MAIN_ShCoreDll)
  {
    FreeLibrary(MAIN_ShCoreDll);
    MAIN_ShCoreDll              = NULL;
    MAIN_SetProcessDpiAwareness = NULL;
  }

  /* Restore previous console code pages */
  SetConsoleOutputCP(MAIN_OldOutputCP);
  SetConsoleCP(MAIN_OldInputCP);
}

static bool MAIN_StringEquals (const wchar_t *StringA, const wchar_t *StringB)
{
  return (wcscmp(StringA, StringB) == 0);
}

/*============================================================================*/
/* MAIN FUNCTION                                                              */
/*============================================================================*/

static void MAIN_ConvertArguments (struct PB_Buffer  **BufferPointer,
                                   int                 Argc,
                                   const wchar_t     **Argv,
                                   char             ***ArgvUtf8)
{
  struct PB_Buffer *Buffer = *BufferPointer;
  int               Offset;
  LPCWCH            ArgStringUtf16;

  /* We skip argv[0] because it's managed in MAIN_CollectArg0 */
  for (Offset = 1; Offset < Argc; Offset++)
  {
    ArgStringUtf16 = Argv[Offset];
    (*ArgvUtf8)[Offset] = MAIN_ConvertString(&Buffer, ArgStringUtf16);
  }

  /* Add the final NULL terminator */
  (*ArgvUtf8)[Argc] = NULL;

  /* Update resulting buffer */
  *BufferPointer = Buffer;
}

/* Free all the allocated UTF-8 arguments, including Arg0 */
static void MAIN_FreeAllocatedArguments (char **ArgvUtf8, int Argc)
{
  int Offset;

  for (Offset = 0; Offset < Argc; Offset++)
  {
    /* Release the string created with PLAT_StrDup */
    PLAT_Free(ArgvUtf8[Offset]);
  }
}

int wmain (int argc, const wchar_t **argv)
{
  struct LUA_Application  *Application;
  struct PB_Buffer        *NewBuffer;
  char                   **ArgvUtf8;
  size_t                   SizeInBytes;
  char                    *NormalizedArgv0;

  if ((argc == 2) && MAIN_StringEquals(argv[1], L"--comexe-version"))
  {
    /* Without newline on purpose to make parsing trivial */
    wprintf(L"comexe-%s-%s", COMEXE_BUILD_TYPE, COMEXE_COMMIT);
  }
  else
  {
    /* That buffer will serve multiple purposes, one of them is
     * GetModuleFileNameW */
    SizeInBytes = (32767 * sizeof(wchar_t));
    
    /* Allocate argc+1 to get a NULL-terminated argv array */
    ArgvUtf8 = PLAT_SafeAlloc0((argc + 1), sizeof(char *));
      
    /* Convert the UTF-16 arguments into UTF-8 using temp buffer */
    NewBuffer = PB_NewBuffer(&MAIN_Allocator, SizeInBytes);
    MAIN_ConvertArguments(&NewBuffer, argc, argv, &ArgvUtf8);
    NormalizedArgv0 = MAIN_NormalizeArgv0(&NewBuffer, "comexe.exe");
    ArgvUtf8[0]     = PLAT_StrDup(NormalizedArgv0);
    PB_FreeBuffer(NewBuffer);

    MAIN_InitializeApplication();
    Application = LUA_CreateApplication(argc, (const char **)ArgvUtf8);
    
    if (Application)
    {
      SERVICE_Initialize(Application);
      LUA_RunApplication(Application);
      LUA_FreeApplication(Application);
    }

    MAIN_FreeAllocatedArguments(ArgvUtf8, argc);
    PLAT_Free(ArgvUtf8);
    MAIN_DeInitializeApplication();
  }

  return EXIT_SUCCESS;
}
