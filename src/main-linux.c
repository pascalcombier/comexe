/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME main-linux.c                                                      *
 * CONTENT  Main function                                                     *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* HEADERS                                                                    */
/*============================================================================*/

#include <stdlib.h>            /* EXIT_SUCCESS              */
#include <stdio.h>             /* printf                    */
#include <string.h>            /* strcmp                    */
#include <stdbool.h>           /* bool                      */
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
#else
#define COMEXE_BUILD_TYPE "???"
#endif

/*============================================================================*/
/* STATIC DATA                                                                */
/*============================================================================*/

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

/* On Linux, we use uv_exepath to get the executable path */
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
    /* Fallback to Argv0 if uv_exepath fails (no procfs?) */
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
}

static void MAIN_DeInitializeApplication ()
{
  MAIN_FreeMbedtls();
}

/*============================================================================*/
/* MAIN FUNCTION                                                              */
/*============================================================================*/

int main (int argc, char **argv)
{
  struct LUA_Application *Application;
  struct PB_Buffer       *Buffer;
  char                   *NormalizedArgv0;

  if ((argc == 2) && (strcmp(argv[1], "--comexe-version") == 0))
  {
    /* Without newline on purpose to make parsing trivial */
    printf("comexe-%s-%s", COMEXE_BUILD_TYPE, COMEXE_COMMIT);
  }
  else
  {
    Buffer = PB_NewBuffer(&MAIN_Allocator, 4096);

    /* Same behavior as on Windows: we need the full qualified filename, because
     * we need to open the EXE as a ZIP file to load init.lua */
    NormalizedArgv0 = MAIN_NormalizeArgv0(&Buffer, argv[0]);
    argv[0]         = PLAT_StrDup(NormalizedArgv0);
    PB_FreeBuffer(Buffer);

    MAIN_InitializeApplication();
    
    /* On Linux, argv is already UTF-8 or compatible with what fopen expect.
     * We pass it directly to LUA_CreateApplication. */
    Application = LUA_CreateApplication((size_t)argc, (const char **)argv);
    
    if (Application)
    {
      LUA_RunApplication(Application);
      LUA_FreeApplication(Application);
    }

    PLAT_Free(argv[0]);
    MAIN_DeInitializeApplication();
  }

  return EXIT_SUCCESS;
}
