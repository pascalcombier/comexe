/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME bump-allocator.c                                                  *
 * CONTENT  Store data in a blob to avoid dynamic memory allocations          *
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

#include <stddef.h>  /* size_t     */ 
#include <stdint.h>  /* uint8_t    */
#include <stdbool.h> /* BA_GetBlob */

/*-------*/
/* TYPES */
/*-------*/

typedef size_t BA_Key_t;
struct         BA_Allocator;

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <string.h> /* memcpy */

#include "comexe.h"

/*============================================================================*/
/* PRIVATE TYPES                                                              */
/*============================================================================*/

struct BA_Allocator
{
  uint8_t  *DataStore;
  size_t    StoreSizeInBytes;
  size_t    StoreFreeSizeInBytes;
  size_t    BlobCount;
  size_t    MaxBlobCount;
  size_t    UsedBlobCount;
  uint8_t  *NextFreePosition;
  size_t   *BlobSizesInBytes;
  uint8_t **BlobPointers;
};

#define BA_INVALID_KEY ((BA_Key_t)0)

/*============================================================================*/
/* PRIVATE FUNCTIONS                                                          */
/*============================================================================*/

static size_t BA_NearestPowerOf2 (size_t Value)
{
  size_t PowerValue = 1;
  while (PowerValue < Value)
  {
    PowerValue = (PowerValue * 2);
  }
  return PowerValue;
}

/* Key indexing starts from 1 because 0 is reserved as BA_INVALID_KEY. This
 * ensures that any operation with BA_INVALID_KEY (0) will fail validation.
 * Keys are sequential and match the index in BlobPointers and BlobSizesInBytes
 * arrays.
 */
static BA_Key_t BA_CalculateNewKey (struct BA_Allocator *Allocator)
{
  return (Allocator->BlobCount + 1);
}

static bool BA_IsKeyValid (struct BA_Allocator *Allocator, BA_Key_t Key)
{
  return ((Key != BA_INVALID_KEY) && (Key <= Allocator->BlobCount));
}

static void BA_DoubleKeyArea (struct BA_Allocator *Allocator)
{
  size_t   CurrentMaxCount       = Allocator->MaxBlobCount + 1; /* 1 dummy */
  size_t   CurrentSizeInfoInByte = CurrentMaxCount * sizeof(size_t);
  size_t   CurrentDataInfoInByte = CurrentMaxCount * sizeof(uint8_t *);
  size_t   NewMaxCount           = CurrentMaxCount * 2;
  size_t   NewSizeInfoInByte     = NewMaxCount * sizeof(size_t);
  size_t   NewDataInfoInByte     = NewMaxCount * sizeof(uint8_t *);
  uint8_t *NewInfo               = PLAT_SafeAlloc0(1, (NewSizeInfoInByte + NewDataInfoInByte));

  /* Copy existing data */
  memcpy(NewInfo, Allocator->BlobSizesInBytes, CurrentSizeInfoInByte);
  memcpy(NewInfo + NewSizeInfoInByte, Allocator->BlobPointers, CurrentDataInfoInByte);

  /* Free old memory after successful allocation and copy */
  PLAT_Free(Allocator->BlobSizesInBytes);

  /* Update pointers */
  Allocator->BlobSizesInBytes = (size_t *)(NewInfo);
  Allocator->BlobPointers     = (uint8_t **)(NewInfo + NewSizeInfoInByte);
  Allocator->MaxBlobCount     = (NewMaxCount - 1); /* 1 dummy */
}

static void BA_ExpandStorage (struct BA_Allocator *Allocator,
                              size_t               NewDataSizeInByte)
{
  uint8_t *NewStorage = PLAT_SafeAlloc0(1, NewDataSizeInByte);
  size_t   UsedSizeInByte;
  size_t   NextFreePositionOffset;
  size_t   Offset;
  size_t   Key;

  /* Calculate current usage */
  UsedSizeInByte = (Allocator->StoreSizeInBytes - Allocator->StoreFreeSizeInBytes);

  /* Copy existing data */
  memcpy(NewStorage, Allocator->DataStore, UsedSizeInByte);

  /* Calculate the offset for next free position */
  NextFreePositionOffset = (Allocator->NextFreePosition - Allocator->DataStore);

  /* Update all data pointers */
  for (Key = 1; Key <= Allocator->BlobCount; Key++)
  {
    if (Allocator->BlobPointers[Key] != NULL)
    {
      Offset = (Allocator->BlobPointers[Key] - Allocator->DataStore);
      Allocator->BlobPointers[Key] = (NewStorage + Offset);
    }
  }

  /* Free old storage after successful operations */
  PLAT_Free(Allocator->DataStore);

  /* Update allocator state */
  Allocator->DataStore            = NewStorage;
  Allocator->StoreSizeInBytes     = NewDataSizeInByte;
  Allocator->StoreFreeSizeInBytes = (NewDataSizeInByte - UsedSizeInByte);
  Allocator->NextFreePosition     = (NewStorage + NextFreePositionOffset);
}

static void BA_ExpandMemoryIfNeeded (struct BA_Allocator *Allocator,
                                     size_t               BlobSizeInByte)
{
  size_t NewDataSizeInByte;
  size_t RequiredSizeInBytes;

  /* Check if we need to resize memory area */
  if (BlobSizeInByte > Allocator->StoreFreeSizeInBytes)
  {
    NewDataSizeInByte   = (Allocator->StoreSizeInBytes * 2);
    RequiredSizeInBytes = (Allocator->StoreSizeInBytes + BlobSizeInByte);

    /* Keep doubling until we have enough space */
    while (NewDataSizeInByte < RequiredSizeInBytes)
    {
      NewDataSizeInByte = (NewDataSizeInByte * 2);
    }

    BA_ExpandStorage(Allocator, NewDataSizeInByte);
  }

  /* Check if we need to expand key area */
  if (Allocator->BlobCount >= Allocator->MaxBlobCount)
  {
    BA_DoubleKeyArea(Allocator);
  }
}

/*============================================================================*/
/* PUBLIC FUNCTIONS                                                           */
/*============================================================================*/

extern struct BA_Allocator *BA_NewAllocator (size_t InitialCount,
                                             size_t InitialSizeInByte)
{
  /* Calculate power of 2 values for both parameters */
  size_t PowerCount       = BA_NearestPowerOf2(InitialCount);
  size_t PowerSizeInBytes = BA_NearestPowerOf2(InitialSizeInByte);

  struct BA_Allocator *NewAllocator = PLAT_SafeAlloc0(1, sizeof(struct BA_Allocator));
  
  uint8_t *Storage        = PLAT_SafeAlloc0(1, PowerSizeInBytes);
  size_t   SizeInfoInByte = PowerCount * sizeof(size_t);
  size_t   DataInfoInByte = PowerCount * sizeof(uint8_t *);
  uint8_t *Info           = PLAT_SafeAlloc0(1, SizeInfoInByte + DataInfoInByte);

  NewAllocator->DataStore        = Storage;
  NewAllocator->StoreSizeInBytes = PowerSizeInBytes;
  NewAllocator->MaxBlobCount     = (PowerCount - 1); /* dummy */
  NewAllocator->BlobSizesInBytes = (size_t *)(Info + 0);
  NewAllocator->BlobPointers     = (uint8_t **)(Info + SizeInfoInByte);

  BA_Reset(NewAllocator);

  return NewAllocator;
}

extern void BA_Reset (struct BA_Allocator *Allocator)
{
  /* Reset all counters */
  Allocator->BlobCount            = 0;
  Allocator->UsedBlobCount        = 0;
  Allocator->NextFreePosition     = Allocator->DataStore;
  Allocator->StoreFreeSizeInBytes = Allocator->StoreSizeInBytes;
}

extern void BA_FreeAllocator (struct BA_Allocator *Allocator)
{
  PLAT_Free(Allocator->DataStore);
  PLAT_Free(Allocator->BlobSizesInBytes);
  PLAT_Free(Allocator);
}

extern size_t BA_GetCount (struct BA_Allocator *Allocator)
{
  return Allocator->UsedBlobCount;
}

/*============================================================================*/
/* INSERT VALUES                                                              */
/*============================================================================*/

/* Give a new KEY and returns a pointer to the memory area where to copy the new
 * blob */
extern void BA_AllocateBlob (struct BA_Allocator  *Allocator,
                             size_t                SizeInByte,
                             BA_Key_t             *Key,
                             uint8_t             **BlobStart)
{
  /* Calculate alignment padding needed for 8-byte alignment */
  uintptr_t CurrentAddress   = (uintptr_t)Allocator->NextFreePosition;
  size_t    AlignmentPadding = (8 - (CurrentAddress % 8)) % 8;
  size_t    RealSizeInByte   = (SizeInByte + AlignmentPadding);
  BA_Key_t  NewKey;

  BA_ExpandMemoryIfNeeded(Allocator, RealSizeInByte);

  /* Apply alignment padding if needed */
  Allocator->NextFreePosition += AlignmentPadding;

  /* Store aligned blob location */
  *BlobStart = Allocator->NextFreePosition;

  /* Calculate a new index */
  NewKey = BA_CalculateNewKey(Allocator);

  /* Update internal structure */
  Allocator->BlobPointers[NewKey]     = *BlobStart;
  Allocator->BlobSizesInBytes[NewKey] = SizeInByte;
  Allocator->NextFreePosition         = (Allocator->NextFreePosition + SizeInByte);
  Allocator->BlobCount                = Allocator->BlobCount + 1;
  Allocator->UsedBlobCount            = Allocator->UsedBlobCount + 1;
  Allocator->StoreFreeSizeInBytes     = (Allocator->StoreFreeSizeInBytes - RealSizeInByte);

  *Key = NewKey;
}

extern BA_Key_t BA_PushBlob (struct BA_Allocator *Allocator,
                             const void          *Memory,
                             size_t               SizeInByte)
{
  BA_Key_t  NewKey;
  uint8_t  *BlobStart;

  BA_AllocateBlob(Allocator, SizeInByte, &NewKey, &BlobStart);

  /* Copy blob data byte per byte */
  memcpy(BlobStart, Memory, SizeInByte);

  return NewKey;
}

extern BA_Key_t BA_PushInt32 (struct BA_Allocator *Allocator, int32_t Value)
{
  BA_Key_t  NewKey = BA_INVALID_KEY;
  uint8_t  *BlobStart;

  BA_AllocateBlob(Allocator, sizeof(Value), &NewKey, &BlobStart);

  /* Direct copy of the 4-byte value, need 32-bit alignment */
  *((int32_t *)BlobStart) = Value;

  return NewKey;
}

extern BA_Key_t BA_PushUint32 (struct BA_Allocator *Allocator, uint32_t Value)
{
  BA_Key_t  NewKey;
  uint8_t  *BlobStart;

  BA_AllocateBlob(Allocator, sizeof(Value), &NewKey, &BlobStart);

  /* Direct copy of the 4-byte value, need 32-bit alignment */
  *((uint32_t *)BlobStart) = Value;

  return NewKey;
}

extern BA_Key_t BA_PushInt64 (struct BA_Allocator *Allocator, int64_t Value)
{
  BA_Key_t  NewKey;
  uint8_t  *BlobStart;

  BA_AllocateBlob(Allocator, sizeof(Value), &NewKey, &BlobStart);

  /* Direct copy of the 8-byte value, need 64-bit alignment */
  *((int64_t *)BlobStart) = Value;

  return NewKey;
}

extern BA_Key_t BA_PushUint64 (struct BA_Allocator *Allocator, uint64_t Value)
{
  BA_Key_t  NewKey;
  uint8_t  *BlobStart;

  BA_AllocateBlob(Allocator, sizeof(Value), &NewKey, &BlobStart);

  /* Direct copy of the 8-byte value, need 64-bit alignment */
  *((uint64_t *)BlobStart) = Value;

  return NewKey;
}

extern BA_Key_t BA_PushDouble (struct BA_Allocator *Allocator, double Value)
{
  BA_Key_t  NewKey;
  uint8_t  *BlobStart;

  BA_AllocateBlob(Allocator, sizeof(Value), &NewKey, &BlobStart);

  /* Direct copy of the 8-bytes value, need 64-bit alignment */
  *((double *)BlobStart) = Value;

  return NewKey;
}

extern BA_Key_t BA_PushString (struct BA_Allocator *Allocator, const char *String)
{
  size_t SizeInBytes = (strlen(String) + 1);
  return BA_PushBlob(Allocator, String, SizeInBytes);
}

extern BA_Key_t BA_PushPointer (struct BA_Allocator *Allocator, void *Pointer)
{
  BA_Key_t  NewKey;
  uint8_t  *BlobStart;

  BA_AllocateBlob(Allocator, sizeof(Pointer), &NewKey, &BlobStart);

  /* Direct copy of the pointer value, need pointer alignment */
  *((void **)BlobStart) = Pointer;

  return NewKey;
}

/*============================================================================*/
/* RETRIEVE VALUES                                                            */
/*============================================================================*/

extern bool BA_GetBlob (struct BA_Allocator  *Allocator,
                        BA_Key_t              Key,
                        uint8_t             **Blob,
                        size_t               *BlobSizesInBytes)
{
  bool Success;

  if (BA_IsKeyValid(Allocator, Key))
  {
    if (BlobSizesInBytes)
    {
      *BlobSizesInBytes = Allocator->BlobSizesInBytes[Key];
    }

    *Blob   = Allocator->BlobPointers[Key];
    Success = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_GetInt32 (struct BA_Allocator *Allocator,
                         BA_Key_t             Key,
                         int32_t             *Value)
{
  bool Success;

  if (BA_IsKeyValid(Allocator, Key))
  {
    /* BA_ALIGNMENT */
    *Value  = *((int32_t *)Allocator->BlobPointers[Key]);
    Success = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_GetUint32 (struct BA_Allocator *Allocator,
                          BA_Key_t             Key,
                          uint32_t            *Value)
{
  bool Success;

  if (BA_IsKeyValid(Allocator, Key))
  {
    /* BA_ALIGNMENT */
    *Value  = *((uint32_t *)Allocator->BlobPointers[Key]);
    Success = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_GetInt64 (struct BA_Allocator *Allocator,
                         BA_Key_t             Key,
                         int64_t             *Value)
{
  bool Success;

  if (BA_IsKeyValid(Allocator, Key))
  {
    /* BA_ALIGNMENT */
    *Value  = *((int64_t *)Allocator->BlobPointers[Key]);
    Success = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_GetUint64 (struct BA_Allocator *Allocator,
                          BA_Key_t             Key,
                          uint64_t            *Value)
{
  bool Success;

  if (BA_IsKeyValid(Allocator, Key))
  {
    /* BA_ALIGNMENT */
    *Value  = *((uint64_t *)Allocator->BlobPointers[Key]);
    Success = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_GetDouble (struct BA_Allocator *Allocator,
                          BA_Key_t             Key,
                          double              *Value)
{
  bool Success;

  if (BA_IsKeyValid(Allocator, Key))
  {
    *Value  = *((double *)Allocator->BlobPointers[Key]);
    Success = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_GetString (struct BA_Allocator  *Allocator,
                          BA_Key_t              Key,
                          const char          **String)
{
  bool Success;

  if (BA_IsKeyValid(Allocator, Key))
  {
    *String = (char *)Allocator->BlobPointers[Key];
    Success = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_GetPointer (struct BA_Allocator  *Allocator,
                           BA_Key_t              Key,
                           void                **Value)
{
  bool Success;

  if (BA_IsKeyValid(Allocator, Key))
  {
    /* BA_ALIGNMENT */
    *Value = *((void **)Allocator->BlobPointers[Key]);
    Success = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

/*============================================================================*/
/* UPDATE VALUES                                                              */
/*============================================================================*/

extern bool BA_SetInt32 (struct BA_Allocator *Allocator,
                         BA_Key_t             Key,
                         int32_t              Value)
{
  bool     Success;
  int32_t *Pointer;

  if (BA_IsKeyValid(Allocator, Key))
  {
    Pointer  = (int32_t *)Allocator->BlobPointers[Key];
    *Pointer = Value; /* BA_ALIGNMENT */
    Success  = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_SetUint32 (struct BA_Allocator *Allocator,
                          BA_Key_t             Key,
                          uint32_t             Value)
{
  bool      Success;
  uint32_t *Pointer;

  if (BA_IsKeyValid(Allocator, Key))
  {
    Pointer  = (uint32_t *)Allocator->BlobPointers[Key];
    *Pointer = Value; /* BA_ALIGNMENT */
    Success  = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_SetInt64 (struct BA_Allocator *Allocator,
                         BA_Key_t             Key,
                         int64_t              Value)
{
  bool     Success;
  int64_t *Pointer;

  if (BA_IsKeyValid(Allocator, Key))
  {
    Pointer  = (int64_t *)Allocator->BlobPointers[Key];
    *Pointer = Value; /* BA_ALIGNMENT */
    Success  = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_SetUint64 (struct BA_Allocator *Allocator,
                          BA_Key_t             Key,
                          uint64_t             Value)
{
  bool      Success;
  uint64_t *Pointer;

  if (BA_IsKeyValid(Allocator, Key))
  {
    Pointer  = (uint64_t *)Allocator->BlobPointers[Key];
    *Pointer = Value; /* BA_ALIGNMENT */
    Success  = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_SetDouble (struct BA_Allocator *Allocator,
                          BA_Key_t             Key,
                          double               Value)
{
  bool    Success;
  double *Pointer;

  if (BA_IsKeyValid(Allocator, Key))
  {
    Pointer  = (double *)Allocator->BlobPointers[Key];
    *Pointer = Value; /* BA_ALIGNMENT */
    Success  = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

extern bool BA_SetPointer (struct BA_Allocator *Allocator,
                           BA_Key_t             Key,
                           void                *Value)
{
  bool   Success;
  void **Pointer;

  if (BA_IsKeyValid(Allocator, Key))
  {
    Pointer  = (void **)Allocator->BlobPointers[Key];
    *Pointer = Value; /* BA_ALIGNMENT */
    Success  = true;
  }
  else
  {
    Success = false;
  }

  return Success;
}

/*============================================================================*/
/* TESTS                                                                      */
/*============================================================================*/

#if 0

#include <assert.h> /* assert */

static void TEST_BasicOperations ()
{
  struct BA_Allocator *Allocator;
  BA_Key_t Key1, Key2, Key3;
  const char *RetrievedString;
  int32_t RetrievedInt32;
  uint64_t RetrievedUint64;
  bool Success;

  /* Test initialization */
  Allocator = BA_NewAllocator(4, 1024);

  /* Test string operations */
  Key1 = BA_PushString(Allocator, "TestString");
  Success = BA_GetString(Allocator, Key1, &RetrievedString);
  assert(Success && strcmp(RetrievedString, "TestString") == 0);

  /* Test integer operations */
  Key2 = BA_PushInt32(Allocator, 42);
  Success = BA_GetInt32(Allocator, Key2, &RetrievedInt32);
  assert(Success && RetrievedInt32 == 42);

  /* Test uint64 operations */
  Key3 = BA_PushUint64(Allocator, 123456789);
  Success = BA_GetUint64(Allocator, Key3, &RetrievedUint64);
  assert(Success && RetrievedUint64 == 123456789);

  /* Test invalid key */
  Success = BA_GetInt32(Allocator, BA_INVALID_KEY, &RetrievedInt32);
  assert(!Success);

  /* Cleanup */
  BPLAT_FreeAllocator(Allocator);
}

static void TEST_ResizeOperations ()
{
  struct BA_Allocator *Allocator;
  BA_Key_t Keys[100];
  int32_t Index;
  int32_t RetrievedValue;
  bool Success;

  /* Initialize with small capacity to force resizing */
  Allocator = BA_NewAllocator(2, 16);

  /* Push multiple values to trigger both key area and memory area resizing */
  for (Index = 1; Index <= 50; Index++)
  {
    Keys[Index - 1] = BA_PushInt32(Allocator, Index);
    Success = BA_GetInt32(Allocator, Keys[Index - 1], &RetrievedValue);
    assert(Success && RetrievedValue == Index);
  }

  /* Verify all values after resize operations */
  for (Index = 1; Index <= 50; Index++)
  {
    Success = BA_GetInt32(Allocator, Keys[Index - 1], &RetrievedValue);
    assert(Success && RetrievedValue == Index);
  }

  /* Cleanup */
  BPLAT_FreeAllocator(Allocator);
}

static void TEST_ClearAndReset ()
{
  struct BA_Allocator *Allocator;
  BA_Key_t Key1, Key2;
  int32_t RetrievedValue;
  bool Success;

  (void)Key1;

  Allocator = BA_NewAllocator(4, 64);

  /* Add some values */
  Key1 = BA_PushInt32(Allocator, 100);
  Key2 = BA_PushInt32(Allocator, 200);

  /* Verify other value is still accessible */
  Success = BA_GetInt32(Allocator, Key2, &RetrievedValue);
  assert(Success && RetrievedValue == 200);

  /* Reset allocator */
  BA_Reset(Allocator);

  /* Verify all values are inaccessible after reset */
  Success = BA_GetInt32(Allocator, Key2, &RetrievedValue);
  assert(!Success);

  /* Cleanup */
  BPLAT_FreeAllocator(Allocator);
}

static void TEST_LargeAllocationResize()
{
  struct BA_Allocator *Allocator;
  BA_Key_t Key1, Key2;
  const size_t InitialSize = 12;    /* Will be rounded to 16 by power of 2 */
  const size_t SmallBlobSize = 8;   /* First allocation */
  const size_t LargeBlobSize = 1024; /* Much larger than 2 * InitialSize (which is 32) */
  uint8_t *SmallBlob;
  uint8_t *LargeBlob;
  size_t RetrievedSize;

  /* Initialize with small capacity that will be rounded to 16 */
  Allocator = BA_NewAllocator(4, InitialSize);

  /* First allocation should succeed within initial capacity */
  BA_AllocateBlob(Allocator, SmallBlobSize, &Key1, &SmallBlob);
  assert(Key1 != BA_INVALID_KEY);

  /* Try to allocate a blob much larger than (InitialSize * 2) */
  BA_AllocateBlob(Allocator, LargeBlobSize, &Key2, &LargeBlob);

  /* Verify the large allocation succeeded */
  assert(Key2 != BA_INVALID_KEY);
  BA_GetBlob(Allocator, Key2, &LargeBlob, &RetrievedSize);
  assert(RetrievedSize == LargeBlobSize);

  /* Verify both allocations are still accessible and correct */
  BA_GetBlob(Allocator, Key1, &SmallBlob, &RetrievedSize);
  assert(RetrievedSize == SmallBlobSize);

  BPLAT_FreeAllocator(Allocator);
}

static void TEST_AllDataTypes()
{
  struct BA_Allocator *Allocator;
  BA_Key_t KeyInt32, KeyUint32, KeyInt64, KeyUint64, KeyDouble, KeyString, KeyPointer, KeyBlob;
  int32_t TestInt32 = -42;
  uint32_t TestUint32 = 42;
  int64_t TestInt64 = -1234567890LL;
  uint64_t TestUint64 = 1234567890ULL;
  double TestDouble = 3.14159;
  const char *TestString = "Hello World";
  void *TestPointer = (void*)0x12345678;
  uint8_t TestBlob[16] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};

  /* Test variables for retrieval */
  int32_t RetrievedInt32;
  uint32_t RetrievedUint32;
  int64_t RetrievedInt64;
  uint64_t RetrievedUint64;
  double RetrievedDouble;
  const char *RetrievedString;
  void *RetrievedPointer;
  uint8_t *RetrievedBlob;
  size_t RetrievedSize;

  /* Initialize allocator */
  Allocator = BA_NewAllocator(16, 256);

  /* Test pushing all types */
  KeyInt32 = BA_PushInt32(Allocator, TestInt32);
  KeyUint32 = BA_PushUint32(Allocator, TestUint32);
  KeyInt64 = BA_PushInt64(Allocator, TestInt64);
  KeyUint64 = BA_PushUint64(Allocator, TestUint64);
  KeyDouble = BA_PushDouble(Allocator, TestDouble);
  KeyString = BA_PushString(Allocator, TestString);
  KeyPointer = BA_PushPointer(Allocator, TestPointer);
  KeyBlob = BA_PushBlob(Allocator, TestBlob, sizeof(TestBlob));

  /* Verify all keys are valid */
  assert(KeyInt32 != BA_INVALID_KEY);
  assert(KeyUint32 != BA_INVALID_KEY);
  assert(KeyInt64 != BA_INVALID_KEY);
  assert(KeyUint64 != BA_INVALID_KEY);
  assert(KeyDouble != BA_INVALID_KEY);
  assert(KeyString != BA_INVALID_KEY);
  assert(KeyPointer != BA_INVALID_KEY);
  assert(KeyBlob != BA_INVALID_KEY);

  /* Test retrieving all types */
  assert(BA_GetInt32(Allocator, KeyInt32, &RetrievedInt32));
  assert(RetrievedInt32 == TestInt32);

  assert(BA_GetUint32(Allocator, KeyUint32, &RetrievedUint32));
  assert(RetrievedUint32 == TestUint32);

  assert(BA_GetInt64(Allocator, KeyInt64, &RetrievedInt64));
  assert(RetrievedInt64 == TestInt64);

  assert(BA_GetUint64(Allocator, KeyUint64, &RetrievedUint64));
  assert(RetrievedUint64 == TestUint64);

  assert(BA_GetDouble(Allocator, KeyDouble, &RetrievedDouble));
  assert(RetrievedDouble == TestDouble);

  assert(BA_GetString(Allocator, KeyString, &RetrievedString));
  assert(strcmp(RetrievedString, TestString) == 0);

  assert(BA_GetPointer(Allocator, KeyPointer, &RetrievedPointer));
  assert(RetrievedPointer == TestPointer);

  assert(BA_GetBlob(Allocator, KeyBlob, &RetrievedBlob, &RetrievedSize));
  assert(RetrievedSize == sizeof(TestBlob));
  assert(memcmp(RetrievedBlob, TestBlob, RetrievedSize) == 0);

  /* Test count */
  assert(BA_GetCount(Allocator) == 8);

  BPLAT_FreeAllocator(Allocator);
}

void TEST_BumpAllocator ()
{
  TEST_BasicOperations();
  TEST_ResizeOperations();
  TEST_ClearAndReset();
  TEST_LargeAllocationResize();
  TEST_AllDataTypes();
}

#endif
