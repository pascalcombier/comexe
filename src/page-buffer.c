/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME page-buffer.c                                                     *
 * CONTENT  Growing buffer aligned on page size                               *
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

struct PB_Allocator
{
  size_t (*GetPageSizeInBytes)(void);
  
  void * (*Alloc)  (size_t Count, size_t SizeInBytes);
  void   (*Free)   (void *Pointer);
  void * (*Realloc)(void *Pointer, size_t NewSizeInBytes);
};

struct PB_Buffer;

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <stddef.h> /* size_t  */
#include <stdint.h> /* uint8_t */

#include "comexe.h" /* PB_Allocator */

/*============================================================================*/
/* PRIVATE TYPES                                                              */
/*============================================================================*/

struct PB_Buffer
{
  struct PB_Allocator *Allocator;
  size_t               Capacity;  /* Effective capacity (allocated size - PB_Buffer size) */
  uint8_t              Data[];    /* Flexible array member for the data area */
};

/*============================================================================*/
/* PRIVATE FUNCTIONS                                                          */
/*============================================================================*/

static size_t PB_AlignToPageSize (size_t PageSize, size_t BufferSizeInBytes) 
{
  size_t Remainder = (BufferSizeInBytes % PageSize);
  size_t NumberOfPages;
  size_t AlignedSize;
  
  if (Remainder == 0) 
  {
    NumberOfPages = (BufferSizeInBytes / PageSize);
  }
  else 
  {
    NumberOfPages = (BufferSizeInBytes / PageSize) + 1;
  }

  AlignedSize = (NumberOfPages * PageSize);
  
  return AlignedSize;
}

/*============================================================================*/
/* PUBLIC FUNCTIONS                                                           */
/*============================================================================*/

struct PB_Buffer *PB_NewBuffer (struct PB_Allocator *Allocator,
                                size_t               InitialSizeInBytes)
{
  size_t PageSize    = Allocator->GetPageSizeInBytes();
  size_t StructSize  = sizeof(struct PB_Buffer);
  size_t TotalSize   = (StructSize + InitialSizeInBytes);
  size_t AlignedSize = PB_AlignToPageSize(PageSize, TotalSize);
  
  struct PB_Buffer *NewBuffer = Allocator->Alloc(1, AlignedSize);
  
  NewBuffer->Allocator = Allocator;
  NewBuffer->Capacity  = (AlignedSize - StructSize);
  
  return NewBuffer;
}

void PB_FreeBuffer (struct PB_Buffer *Buffer)
{
  Buffer->Allocator->Free(Buffer);
}

struct PB_Buffer *PB_EnsureCapacity (struct PB_Buffer *Buffer,
                                     size_t            NeededCapacity)
{
  size_t            StructSize = sizeof(struct PB_Buffer);
  size_t            NewTotalSize;
  struct PB_Buffer *NewBuffer;
  size_t            PageSize;
  
  if (NeededCapacity > Buffer->Capacity)
  {
    PageSize      = Buffer->Allocator->GetPageSizeInBytes();
    NewTotalSize  = (StructSize + NeededCapacity);
    NewTotalSize  = PB_AlignToPageSize(PageSize, NewTotalSize);
    NewBuffer     = Buffer->Allocator->Realloc(Buffer, NewTotalSize);
    
    if (NewBuffer != NULL)
    {
      NewBuffer->Capacity = (NewTotalSize - StructSize);
      Buffer = NewBuffer;
    }
  }
  
  return Buffer;
}

size_t PB_GetCapacity (struct PB_Buffer *Buffer)
{
  return Buffer->Capacity;
}

void *PB_GetData (struct PB_Buffer *Buffer)
{
  return Buffer->Data;
}
