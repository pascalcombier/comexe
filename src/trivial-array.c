/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME trivial-array.c                                                   *
 * CONTENT  Resizable array of objects which are fixed position in memory     *
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

#include <stdint.h>
#include <stdbool.h>

/*-------*/
/* TYPES */
/*-------*/

struct TA_Array;

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <string.h> /* memcpy */

#include "comexe.h"

/*============================================================================*/
/* TYPES                                                                      */
/*============================================================================*/

struct TA_Array
{
  void             **Data;
  size_t             Count;
  size_t             Capacity;
  struct TQU_Queue  *RemovedOffsets;
};

/* 0 is invalid offset by design, the first key created by TA_AddObject is 1.
 * It allows to have size_t as an offset type instead of signed
 */
#define TA_INVALID_OFFSET ((size_t)0)

/*============================================================================*/
/* PRIVATE API                                                                */
/*============================================================================*/

static void TA_ResizeArray (struct TA_Array *Array)
{
  size_t   CurCapacity    = Array->Capacity;
  size_t   NewCapacity    = (CurCapacity * 2);
  size_t   NewSizeInBytes = (NewCapacity * sizeof(void *));
  void   **NewData        = PLAT_SafeRealloc(Array->Data, NewSizeInBytes);

  /* Initialize the new slots */
  void   *NewSlots           = (NewData + CurCapacity);
  size_t  NewSlotSizeInBytes = ((NewCapacity - CurCapacity) * sizeof(void *));
  
  memset(NewSlots, 0, NewSlotSizeInBytes);

  /* Update array */
  Array->Data     = NewData;
  Array->Capacity = NewCapacity;
}

static size_t TA_FindFreeElement (struct TA_Array *Array)
{
  size_t Result;
  
  /* First check if we have any removed offsets in the queue */
  if (TQU_IsEmpty(Array->RemovedOffsets))
  {
    /* No removed offsets available, use Count as next free offset */
    Result = Array->Count;
  }
  else
  {
    /* Reuse the oldest removed offset first */
    Result = TQU_Dequeue(Array->RemovedOffsets);
  }

  return Result;
}

/*============================================================================*/
/* PUBLIC API                                                                 */
/*============================================================================*/

struct TA_Array *TA_CreateArray (size_t InitialCapacity)
{
  struct TA_Array *Array = PLAT_SafeAlloc0(1, sizeof(struct TA_Array));

  Array->Data           = PLAT_SafeAlloc0(InitialCapacity, sizeof(void *));
  Array->Count          = 1; /* reserved for Array[0] = TA_INVALID_OFFSET */
  Array->Capacity       = InitialCapacity;
  Array->RemovedOffsets = TQU_CreateQueue(InitialCapacity);
  
  /* Initialize offset 0, reserved dummy value */
  Array->Data[TA_INVALID_OFFSET] = 0;

  return Array;
}

void TA_FreeArray (struct TA_Array *Array)
{
  TQU_FreeQueue(Array->RemovedOffsets);
  PLAT_Free(Array->Data);
  PLAT_Free(Array);
}

size_t TA_AddObject (struct TA_Array *Array, void *Object)
{
  size_t  Offset;

  if (Array->Count >= Array->Capacity)
  {
    TA_ResizeArray(Array);
  }

  Offset = TA_FindFreeElement(Array);

  if (Offset != TA_INVALID_OFFSET)
  {
    Array->Data[Offset] = Object;
    Array->Count++;
  }

  return Offset;
}

size_t TA_GetCapacity (struct TA_Array *Array)
{
  return Array->Capacity;
}

bool TA_IsValid (struct TA_Array *Array, size_t Offset)
{
  return (Offset != TA_INVALID_OFFSET)
    && (Offset < Array->Capacity)
    && (Array->Data[Offset]);
}

void *TA_GetObject (struct TA_Array *Array, size_t Offset)
{
  void *Object = Array->Data[Offset];
  return Object;
}

void TA_RemoveObject (struct TA_Array *Array, size_t Offset)
{
  if (TA_IsValid(Array, Offset))
  {
    Array->Data[Offset] = 0;
    Array->Count--;
    
    /* Store the offset in the queue for reuse */
    TQU_Enqueue(Array->RemovedOffsets, Offset);
  }
}
