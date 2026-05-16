/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME growing-buffer.c                                                  *
 * CONTENT  Resizable growing buffer                                          *
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
#include <stdint.h> /* uint8_t */

/*-------*/
/* TYPES */
/*-------*/

typedef size_t (*GB_Strategy_t)(size_t CurrentCapacity, size_t NeededCapacity);

struct GB_Allocator
{
  void * (*Alloc)  (size_t Count, size_t SizeInBytes);
  void   (*Free)   (void *Pointer);
  void * (*Realloc)(void *Pointer, size_t NewSizeInBytes);
};

struct GB_Buffer;

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <stddef.h> /* size_t  */
#include <stdint.h> /* uint8_t */

#include "comexe.h" /* GB_Allocator */

/*============================================================================*/
/* PRIVATE TYPES                                                              */
/*============================================================================*/

struct GB_Buffer
{
  struct GB_Allocator *Allocator;
  GB_Strategy_t        ResizeStrategy;
  size_t               Capacity;
  uint8_t              Data[];
};

/*============================================================================*/
/* PRIVATE FUNCTIONS                                                          */
/*============================================================================*/

static size_t GB_DefaultStrategy (size_t CurrentCapacity, size_t NeededCapacity)
{
  size_t NewCapacity = (CurrentCapacity * 2);

  if (NewCapacity < NeededCapacity)
  {
    NewCapacity = NeededCapacity;
  }

  return NewCapacity;
}

static size_t GB_EvaluateNewCapacity (struct GB_Buffer *Buffer,
                                      size_t            NeededCapacity)
{
  GB_Strategy_t ResizeStrategy = Buffer->ResizeStrategy;
  size_t        NewCapacity;
  size_t        CalculatedCapacity;

  CalculatedCapacity = ResizeStrategy(Buffer->Capacity, NeededCapacity);

  if (CalculatedCapacity < NeededCapacity)
  {
    NewCapacity = NeededCapacity;
  }
  else
  {
    NewCapacity = CalculatedCapacity;
  }

  return NewCapacity;
}

/*============================================================================*/
/* PUBLIC FUNCTIONS                                                           */
/*============================================================================*/

struct GB_Buffer *GB_NewBuffer (struct GB_Allocator *Allocator,
                                size_t               InitialSizeInBytes,
                                GB_Strategy_t        UserStrategy)
{
  size_t            StructureSize = sizeof(struct GB_Buffer);
  size_t            TotalSize;
  struct GB_Buffer *NewBuffer;
  GB_Strategy_t     ResizeStrategy;

  TotalSize = (StructureSize + InitialSizeInBytes);
  NewBuffer = Allocator->Alloc(1, TotalSize);

  if (UserStrategy)
  {
    ResizeStrategy = UserStrategy;
  }
  else
  {
    ResizeStrategy = GB_DefaultStrategy;
  }

  NewBuffer->Allocator      = Allocator;
  NewBuffer->ResizeStrategy = ResizeStrategy;
  NewBuffer->Capacity       = InitialSizeInBytes;

  return NewBuffer;
}

void GB_FreeBuffer (struct GB_Buffer *Buffer)
{
  Buffer->Allocator->Free(Buffer);
}

struct GB_Buffer *GB_EnsureCapacity (struct GB_Buffer *Buffer,
                                     size_t            NeededCapacity)
{
  size_t            StructureSize = sizeof(struct GB_Buffer);
  size_t            NewCapacity;
  size_t            NewTotalSize;
  struct GB_Buffer *NewBuffer;

  if (NeededCapacity > Buffer->Capacity)
  {
    NewCapacity  = GB_EvaluateNewCapacity(Buffer, NeededCapacity);
    NewTotalSize = (StructureSize + NewCapacity);
    NewBuffer    = Buffer->Allocator->Realloc(Buffer, NewTotalSize);

    if (NewBuffer != NULL)
    {
      NewBuffer->Capacity = NewCapacity;
      Buffer = NewBuffer;
    }
  }

  return Buffer;
}

size_t GB_GetCapacity (struct GB_Buffer *Buffer)
{
  return Buffer->Capacity;
}

void *GB_GetData (struct GB_Buffer *Buffer)
{
  return Buffer->Data;
}
