/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME trivial-queue-uint.c                                              *
 * CONTENT  Queue of objects using a circular buffer                          *
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

#include <stddef.h>  /* size_t */
#include <stdbool.h> /* bool   */

/*-------*/
/* TYPES */
/*-------*/

struct TQU_Queue;

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <stddef.h>  /* size_t */
#include <stdbool.h> /* bool   */

#include "comexe.h"

/*============================================================================*/
/* TYPES                                                                      */
/*============================================================================*/

struct TQU_Queue
{
  size_t *Data;
  size_t  Head;     /* Offset for dequeue operations */
  size_t  Tail;     /* Offset for enqueue operations */
  size_t  Count;    /* Current number of elements    */
  size_t  Capacity; /* Total capacity of the queue   */
};

/*============================================================================*/
/* PRIVATE API                                                                */
/*============================================================================*/

static void TQU_ResizeQueue (struct TQU_Queue *Queue)
{
  size_t  NewCapacity = (Queue->Capacity * 2);
  size_t *NewData     = PLAT_SafeAlloc0(NewCapacity, sizeof(size_t));
  size_t  OffsetA;
  size_t  OffsetB;

  /* Copy elements in order from head to tail */
  OffsetA = 0;
  OffsetB = Queue->Head;

  while (OffsetA < Queue->Count)
  {
    NewData[OffsetA] = Queue->Data[OffsetB];
    OffsetB = ((OffsetB + 1) % Queue->Capacity);
    OffsetA++;
  }

  PLAT_Free(Queue->Data);
  
  Queue->Data     = NewData;
  Queue->Head     = 0;
  Queue->Tail     = Queue->Count;
  Queue->Capacity = NewCapacity;
}

/*============================================================================*/
/* PUBLIC API                                                                 */
/*============================================================================*/

struct TQU_Queue *TQU_CreateQueue (size_t InitialCapacity)
{
  struct TQU_Queue *NewQueue = PLAT_SafeAlloc0(1, sizeof(struct TQU_Queue));

  NewQueue->Data     = PLAT_SafeAlloc0(InitialCapacity, sizeof(size_t));
  NewQueue->Head     = 0;
  NewQueue->Tail     = 0;
  NewQueue->Count    = 0;
  NewQueue->Capacity = InitialCapacity;

  return NewQueue;
}

void TQU_FreeQueue (struct TQU_Queue *Queue)
{
  PLAT_Free(Queue->Data);
  PLAT_Free(Queue);
}

bool TQU_Enqueue (struct TQU_Queue *Queue, size_t Value)
{
  bool Success;

  if (!TQU_IsFull(Queue))
  {
    Queue->Data[Queue->Tail] = Value;
    Queue->Tail = ((Queue->Tail + 1) % Queue->Capacity);
    Queue->Count++;
    Success = true;
  }
  else if (Queue->Count == Queue->Capacity)
  {
    TQU_ResizeQueue(Queue);
    Success = TQU_Enqueue(Queue, Value);
  }
  else
  {
    Success = false;
  }

  return Success;
}

size_t TQU_Peek (struct TQU_Queue *Queue)
{
  size_t Result;
  
  if (TQU_IsEmpty(Queue))
  {
    Result = 0;
  }
  else
  {
    Result = Queue->Data[Queue->Head];
  }

  return Result;
}

size_t TQU_Dequeue (struct TQU_Queue *Queue)
{
  size_t Value;

  if (TQU_IsEmpty(Queue))
  {
    Value = 0;
  }
  else
  {
    Value = Queue->Data[Queue->Head];
    Queue->Data[Queue->Head] = 0;
    Queue->Head = (Queue->Head + 1) % Queue->Capacity;
    Queue->Count--;
  }

  return Value;
}

size_t TQU_GetCapacity (struct TQU_Queue *Queue)
{
  return Queue->Capacity;
}

size_t TQU_GetCount (struct TQU_Queue *Queue)
{
  return Queue->Count;
}

bool TQU_IsEmpty (struct TQU_Queue *Queue)
{
  return (Queue->Count == 0);
}

bool TQU_IsFull (struct TQU_Queue *Queue)
{
  return (Queue->Count == Queue->Capacity);
}
