/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME tools/src/tcc-host.c                                              *
 * CONTENT  Generate tccdefs_.h                                               *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* HEADERS                                                                    */
/*============================================================================*/

#include <stddef.h>
#include <errno.h>
#include <io.h>
#include <sys/types.h>

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
  int Result = _open(pathname, flags, mode);

  if (Result < 0)
  {
    Result = -errno;
  }
  
  return Result;
}

int uio_write (TCCState *TccState, int fd, const void *buf, unsigned int count)
{
  int Result = _write(fd, buf, count);

  if (Result < 0)
  {
    Result = -errno;
  }
  
  return Result;
}

int uio_read (TCCState *TccState, int fd, void *buf, unsigned int count)
{
  int Result = _read(fd, buf, count);

  if (Result < 0)
  {
    Result = -errno;
  }
  
  return Result;
}

int uio_close (TCCState *TccState, int fd)
{
  int Result = _close(fd);

  if (Result < 0)
  {
    Result = -errno;
  }
  
  return Result;
}

off_t uio_lseek (TCCState *TccState, int fd, off_t offset, int whence)
{
  off_t Result = (off_t)_lseeki64(fd, offset, whence);

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
