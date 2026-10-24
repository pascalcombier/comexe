/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME tools/src/tcc-host.c                                              *
 * CONTENT  Generate tccdefs_.h                                               *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the MIT license (see the LICENSE file). *
 * SPDX-License-Identifier: MIT                                               *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* HEADERS                                                                    */
/*============================================================================*/

#include <stddef.h>
#include <errno.h>
#include <sys/types.h>

#ifdef _WIN32
#include <io.h>
#define comexe_open  _open
#define comexe_read  _read
#define comexe_write _write
#define comexe_close _close
#define comexe_lseek _lseeki64
#else
#include <fcntl.h>  /* open, O_* flags, mode */
#include <unistd.h> /* read, write, close, lseek */
#define comexe_open  open
#define comexe_read  read
#define comexe_write write
#define comexe_close close
#define comexe_lseek lseek
#endif

#include "tcc.h"

/*============================================================================*/
/* FUNCTIONS DECLARATIONS                                                     */
/*============================================================================*/

extern int tcc_main (void *UserData, int argc, char **argv);

/*============================================================================*/
/* UIO LAYER IMPLEMENTATION                                                   */
/*============================================================================*/

int uio_open (TCCState *TccState, const char *pathname, int flags, int mode)
{
  int Result = comexe_open(pathname, flags, mode);

  if (Result < 0)
  {
    Result = -errno;
  }
  
  return Result;
}

int uio_write (TCCState *TccState, int fd, const void *buf, unsigned int count)
{
  int Result = comexe_write(fd, buf, count);

  if (Result < 0)
  {
    Result = -errno;
  }
  
  return Result;
}

int uio_read (TCCState *TccState, int fd, void *buf, unsigned int count)
{
  int Result = comexe_read(fd, buf, count);

  if (Result < 0)
  {
    Result = -errno;
  }
  
  return Result;
}

int uio_close (TCCState *TccState, int fd)
{
  int Result = comexe_close(fd);

  if (Result < 0)
  {
    Result = -errno;
  }
  
  return Result;
}

off_t uio_lseek (TCCState *TccState, int fd, off_t offset, int whence)
{
  off_t Result = (off_t)comexe_lseek(fd, offset, whence);

  if (Result < 0)
  {
    Result = (off_t)(-errno);
  }
  
  return Result;
}

/*============================================================================*/
/* ENTRY POINT                                                                */
/*============================================================================*/

int main (int argc, char **argv)
{
  return tcc_main(NULL, argc, argv);
}
