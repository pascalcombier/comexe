/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME platform.c                                                        *
 * CONTENT  platform-dependant + malloc/realloc/calloc routines               *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/*---------*/
/* HEADERS */
/*---------*/

#include <stddef.h> /* size_t  */

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <stdio.h>  /* fprintf */
#include <stdlib.h> /* exit    */
#include <mimalloc.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>         /* _isatty */
#include <combaseapi.h> /* CoInitializeEx, CoUninitialize */
#else
#include <unistd.h>
#endif

/*============================================================================*/
/* PLATFORM DEPENDANT                                                         */
/*============================================================================*/

size_t PLAT_GetPageSizeInBytes ()
{
#ifdef _WIN32
  SYSTEM_INFO SystemInfo;
  GetSystemInfo(&SystemInfo);
  return SystemInfo.dwPageSize;
#else
  long PageSizeInBytes = sysconf(_SC_PAGESIZE);
  return PageSizeInBytes;
#endif
}

int PLAT_IsAtty (int FileDescriptor)
{
#ifdef _WIN32
  return _isatty(FileDescriptor);
#else
  return isatty(FileDescriptor);
#endif
}

void PLAT_ThreadInitalize ()
{
#ifdef _WIN32
  /* COINIT_APARTMENTTHREADED is important to have both IUP and COM working
   * properly when together in the same thread
   *
   * COINIT_DISABLE_OLE1DDE is recommended in Microsoft ShellExecute
   * documentation (disable OLE1 DDE)
   */
  CoInitializeEx(NULL, (COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE));
#endif
}

void PLAT_ThreadDeinitialize ()
{
#ifdef _WIN32
  CoUninitialize();
#endif
}

/*============================================================================*/
/* MIMALLOC ALLOCATOR                                                         */
/*============================================================================*/

void *PLAT_SafeAlloc0 (size_t Count, size_t ObjectSizeInBytes)
{
  void *Buffer = mi_calloc(Count, ObjectSizeInBytes);

  if (Buffer == NULL)
  {
    fprintf(stderr, "memory allocation failed (%zu bytes)\n", ObjectSizeInBytes);
    exit(1);
  }

  return Buffer;
}

void *PLAT_SafeRealloc (void *Object, size_t ObjectSizeInBytes)
{
  void *NewBlock = mi_realloc(Object, ObjectSizeInBytes);

  if (NewBlock == NULL)
  {
    fprintf(stderr, "memory reallocation failed (%zu bytes)\n", ObjectSizeInBytes);
    exit(1);
  }

  return NewBlock;
}

void PLAT_Free (void *Object)
{
  mi_free(Object);
}

char *PLAT_StrDup (const char *String)
{
  return mi_strdup(String);
}
