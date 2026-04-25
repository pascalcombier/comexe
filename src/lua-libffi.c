/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-libffi.c                                                      *
 * CONTENT  Raw bindings to call functions with libffi and callbacks          *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/* This library implements libffi raw bindings: stick to the concepts exposed by
 * libffi and propose a light interface to them. With that, it's easier to
 * develop better ffi APIs on the Lua side. This C code don't check the validity
 * of the inputs. This is responsability of the Lua side to do it (ffi.lua)
 *
 * LUA CALLING C FUNCTIONS
 * =======================
 *
 *   ffi_cif: call interface, need to be prepared with ffi_prep_cif. It is
 *   callable with ffi_call in the case of Lua->C interface.
 *
 *   Status = ffi_prep_cif(&Closure->cif,
 *                         FFI_DEFAULT_ABI,
 *                         ArgCount, 
 *                         Closure->ReturnType,
 *                         Closure->ArgTypes);
 *
 * And then call:
 *
 *     ffi_call(&Function->cif,
 *       FFI_FN(Function->FunctionPointer),
 *       Function->ReturnValue,
 *       Function->ArgValues);
 *
 *  Here, Function->FunctionPointer is typically a symbol from GetProcAddress
 *  Function->ReturnValue is a pointer to where the value will be returned
 *  Function->ArgValues is the (packed) arguments to provide to the function
 *
 * C CALLING LUA FUNCTIONS (CALLBACK IMPLEMENTED IN LUA)
 * =====================================================
 *
 * This concept is named "Closure" in libffi. It's created with
 * ffi_closure_alloc and ffi_prep_closure_loc. It will jump to
 * FFI_ClosureCallback. Only 1 return value is accepted.
 *
 * Here we also need:
 *   Status = ffi_prep_cif(&Closure->cif,
 *                         FFI_DEFAULT_ABI,
 *                         ArgCount, 
 *                         Closure->ReturnType,
 *                         Closure->ArgTypes);
 *
 *
 * LIMITATIONS
 * ===========
 *
 * X86-64 Windows and Linux
 * Not supported: 32-bits FFI_STDCALL / FFI_FASTCALL / FFI_MS_CDECL
 * Not supported: ffi_type_longdouble
 * Not supported: ffi_type_complex_longdouble
 * Not supported: variadics not supported
 */

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/*---------*/
/* HEADERS */
/*---------*/

/* The external luaopen_libffiraw declarations require lua_State */
#include <lua.h>

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <lua.h>
#include <lauxlib.h>
#include <ffi.h>
#include <stdbool.h>
#include <stdio.h> /* stderr */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h> /* strcmp */

#include <uv.h>

#include "comexe.h"

/*============================================================================*/
/* CONSTANTS & TYPES                                                          */
/*============================================================================*/

/* Take the biggest value (like MAX) */
#define FFI_AT_LEAST(Value, Min) ((Value) > (Min) ? (Value) : (Min))

/* This CIF "Call Interface" can be shared/cached between the functions sharing
 * the same signature
 */
struct FFI_Cif
{
  ffi_cif    cif;
  ffi_type  *ReturnType;
  size_t     ArgCount;
  ffi_type **ArgTypes; /* pointer to ffi_type_xxx like ffi_type_void */
};

/* Contains the call argument values and return value */
struct FFI_CallContext
{
  struct FFI_Cif  *Cif;
  void           **ArgValues;   /* array of pointers to argument values */
  void            *ReturnValue; /* buffer for return value              */
};

struct FFI_Closure
{
  lua_State      *LuaState;
  int             FunctionRef;
  struct FFI_Cif *Cif;
  ffi_closure    *Closure;
};

struct FFI_StructType
{
  ffi_type Type; /* Contains Type->elements */
  size_t   FieldCount;
};

static struct PB_Allocator FFI_BufferAllocator =
{
  PLAT_GetPageSizeInBytes,
  PLAT_SafeAlloc0,
  PLAT_Free,
  PLAT_SafeRealloc
};

static const char FFI_BUFFER_KEY;

/*============================================================================*/
/* HELPER FUNCTIONS                                                           */
/*============================================================================*/

static bool STRING_Equals (const char *StringLeft, const char *StringRight)
{
  return (strcmp(StringLeft, StringRight) == 0);
}

/* Lazy: allocate the buffer when needed by FFI_GetStructOffsets */
static struct PB_Buffer *FFI_GetOffsetsBuffer (lua_State *LuaState)
{
  size_t InitialSizeInBytes = (64 * sizeof(size_t)); /* 64 structure fields */
  struct PB_Buffer *Buffer;

  lua_rawgetp(LuaState, LUA_REGISTRYINDEX, &FFI_BUFFER_KEY);
  Buffer = lua_touserdata(LuaState, -1);
  lua_pop(LuaState, 1);

  if (Buffer == NULL)
  {
    Buffer = PB_NewBuffer(&FFI_BufferAllocator, InitialSizeInBytes);

    lua_pushlightuserdata(LuaState, Buffer);
    lua_rawsetp(LuaState, LUA_REGISTRYINDEX, &FFI_BUFFER_KEY);
  }

  return Buffer;
}

/* Return an array of offsets (type: size_t)*/
static size_t *FFI_GetOffsetBufferData (lua_State *LuaState,
                                        size_t     FieldCount)
{
  size_t  NeededSizeInBytes = (FieldCount * sizeof(size_t));
  struct  PB_Buffer *Buffer;
  size_t *OffsetArray;

  /* Resize buffer if needed */
  Buffer = FFI_GetOffsetsBuffer(LuaState);
  Buffer = PB_EnsureCapacity(Buffer, NeededSizeInBytes);

  /* Buffer address might changed, need to update Lua registry */
  lua_pushlightuserdata(LuaState, Buffer);
  lua_rawsetp(LuaState, LUA_REGISTRYINDEX, &FFI_BUFFER_KEY);

  /* Return the data */
  OffsetArray = PB_GetData(Buffer);

  return OffsetArray;
}

static int FFI_FreeOffsetsBuffer (lua_State *LuaState)
{
  struct PB_Buffer *Buffer;

  /* Check buffer */
  lua_rawgetp(LuaState, LUA_REGISTRYINDEX, &FFI_BUFFER_KEY);
  Buffer = lua_touserdata(LuaState, -1);
  lua_pop(LuaState, 1);

  /* Free memory if buffer exist */
  if (Buffer)
  {
    lua_pushnil(LuaState);
    lua_rawsetp(LuaState, LUA_REGISTRYINDEX, &FFI_BUFFER_KEY);
    PB_FreeBuffer(Buffer);
  }

  return 0; /* Number of return values */
}

static void FFI_PushValue (lua_State *LuaState, ffi_type *Type, void *Value)
{
#ifdef FFI_TARGET_HAS_COMPLEX_TYPE
  float  *FloatValue;
  double *DoubleValue;
#endif

  switch (Type->type)
  {
    case FFI_TYPE_VOID:
      lua_pushnil(LuaState);
      break;
    case FFI_TYPE_UINT8:
      lua_pushinteger(LuaState, *(uint8_t *)Value);
      break;
    case FFI_TYPE_SINT8:
      lua_pushinteger(LuaState, *(int8_t *)Value);
      break;
    case FFI_TYPE_UINT16:
      lua_pushinteger(LuaState, *(uint16_t *)Value);
      break;
    case FFI_TYPE_SINT16:
      lua_pushinteger(LuaState, *(int16_t *)Value);
      break;
    case FFI_TYPE_UINT32:
      lua_pushinteger(LuaState, *(uint32_t *)Value);
      break;
    case FFI_TYPE_SINT32:
      lua_pushinteger(LuaState, *(int32_t *)Value);
      break;
    case FFI_TYPE_UINT64:
      lua_pushinteger(LuaState, *(uint64_t *)Value);
      break;
    case FFI_TYPE_SINT64:
      lua_pushinteger(LuaState, *(int64_t *)Value);
      break;
    case FFI_TYPE_FLOAT:
      lua_pushnumber(LuaState, *(float *)Value);
      break;
    case FFI_TYPE_DOUBLE:
      lua_pushnumber(LuaState, *(double *)Value);
      break;
    case FFI_TYPE_POINTER:
      lua_pushlightuserdata(LuaState, *(void **)Value);
      break;
    case FFI_TYPE_STRUCT:
      lua_pushlightuserdata(LuaState, Value);
      break;
#ifdef FFI_TARGET_HAS_COMPLEX_TYPE
    case FFI_TYPE_COMPLEX:
      lua_createtable(LuaState, 2, 0);
      if (Type->size == (sizeof(float) * 2))
      {
        FloatValue = Value;
        lua_pushnumber(LuaState, FloatValue[0]);
        lua_rawseti(LuaState, -2, 1);
        lua_pushnumber(LuaState, FloatValue[1]);
        lua_rawseti(LuaState, -2, 2);
      }
      else if (Type->size == (sizeof(double) * 2))
      {
        DoubleValue = Value;
        lua_pushnumber(LuaState, DoubleValue[0]);
        lua_rawseti(LuaState, -2, 1);
        lua_pushnumber(LuaState, DoubleValue[1]);
        lua_rawseti(LuaState, -2, 2);
      }
      else
      {
        luaL_error(LuaState, "Unsupported complex type size: %zu", Type->size);
      }
      break;
#endif
    default:
      lua_pushnil(LuaState);
      break;
  }
}

static void FFI_CopyLuaValueToCif (lua_State *LuaState,
                                   int        Index,
                                   ffi_type  *Type,
                                   void      *Value)
{
  void *StructPointer;
  
#ifdef FFI_TARGET_HAS_COMPLEX_TYPE
  lua_Number  RealPart;
  lua_Number  ImagPart;
  float      *ComplexFloatValue;
  double     *ComplexDoubleValue;
#endif

  switch (Type->type)
  {
    case FFI_TYPE_VOID:
      break;
    case FFI_TYPE_UINT8:
      *(uint8_t *)Value = (uint8_t)luaL_checkinteger(LuaState, Index);
      break;
    case FFI_TYPE_SINT8:
      *(int8_t *)Value = (int8_t)luaL_checkinteger(LuaState, Index);
      break;
    case FFI_TYPE_UINT16:
      *(uint16_t *)Value = (uint16_t)luaL_checkinteger(LuaState, Index);
      break;
    case FFI_TYPE_SINT16:
      *(int16_t *)Value = (int16_t)luaL_checkinteger(LuaState, Index);
      break;
    case FFI_TYPE_UINT32:
      *(uint32_t *)Value = (uint32_t)luaL_checkinteger(LuaState, Index);
      break;
    case FFI_TYPE_SINT32:
      *(int32_t *)Value = (int32_t)luaL_checkinteger(LuaState, Index);
      break;
    case FFI_TYPE_UINT64:
      *(uint64_t *)Value = (uint64_t)luaL_checkinteger(LuaState, Index);
      break;
    case FFI_TYPE_SINT64:
      *(int64_t *)Value = (int64_t)luaL_checkinteger(LuaState, Index);
      break;
    case FFI_TYPE_FLOAT:
      *(float *)Value = (float)luaL_checknumber(LuaState, Index);
      break;
    case FFI_TYPE_DOUBLE:
      *(double *)Value = (double)luaL_checknumber(LuaState, Index);
      break;
    case FFI_TYPE_POINTER:
      if (lua_isnil(LuaState, Index))
      {
        *(void **)Value = NULL;
      }
      else if (lua_isstring(LuaState, Index))
      {
        *(const char **)Value = lua_tostring(LuaState, Index);
      }
      else
      {
        *(void **)Value = lua_touserdata(LuaState, Index);
      }
      break;
    case FFI_TYPE_STRUCT:
      StructPointer = lua_touserdata(LuaState, Index);
      if (StructPointer == NULL)
      {
        memset(Value, 0, Type->size);
      }
      else
      {
        memcpy(Value, StructPointer, Type->size);
      }
      break;
#ifdef FFI_TARGET_HAS_COMPLEX_TYPE
    case FFI_TYPE_COMPLEX:
      luaL_checktype(LuaState, Index, LUA_TTABLE);
      lua_rawgeti(LuaState, Index, 1);
      RealPart = luaL_checknumber(LuaState, -1);
      lua_pop(LuaState, 1);
      lua_rawgeti(LuaState, Index, 2);
      ImagPart = luaL_checknumber(LuaState, -1);
      lua_pop(LuaState, 1);
      if (Type->size == (sizeof(float) * 2))
      {
        ComplexFloatValue    = Value;
        ComplexFloatValue[0] = (float)RealPart;
        ComplexFloatValue[1] = (float)ImagPart;
      }
      else if (Type->size == (sizeof(double) * 2))
      {
        ComplexDoubleValue    = Value;
        ComplexDoubleValue[0] = (double)RealPart;
        ComplexDoubleValue[1] = (double)ImagPart;
      }
      else
      {
        luaL_error(LuaState, "Unsupported complex type size: %zu", Type->size);
      }
      break;
#endif
    default:
      luaL_error(LuaState, "Unsupported ffi type: %zu", Type->type);
      break;
  }
}

/*============================================================================*/
/* DYNAMIC LIBRARY MANAGEMENT                                                 */
/*============================================================================*/

/* Those functions are not provided by luv */

static int FFI_LoadLibrary (lua_State *LuaState)
{
  const char *DllFilename = luaL_checkstring(LuaState, 1);
  uv_lib_t   *Library     = PLAT_SafeAlloc0(1, sizeof(uv_lib_t));
  
  /* return 0 on success */
  if (uv_dlopen(DllFilename, Library) != 0)
  {
    PLAT_Free(Library);
    Library = NULL;
    lua_pushfstring(LuaState, "Failed to load library %s: %s", DllFilename, uv_dlerror(Library));
    lua_error(LuaState);
  }

  lua_pushlightuserdata(LuaState, Library);

  return 1; /* Number of values returned on the stack */  
}

static int FFI_GetProcAddress (lua_State *LuaState)
{
  uv_lib_t   *Library        =  lua_touserdata(LuaState, 1);
  const char *FunctionName    = luaL_checkstring(LuaState, 2);
  void       *FunctionPointer = NULL;
    
  if (uv_dlsym(Library, FunctionName, &FunctionPointer) != 0)
  {
    lua_pushfstring(LuaState, "Failed to find function '%s' in library: %s", FunctionName, uv_dlerror(Library));
    lua_error(LuaState);
  }

  lua_pushlightuserdata(LuaState, FunctionPointer);

  return 1; /* Number of values returned on the stack */  
}

static int FFI_FreeLibrary (lua_State *LuaState)
{
  uv_lib_t *Library = lua_touserdata(LuaState, 1);

  uv_dlclose(Library);
  PLAT_Free(Library);

  return 0; /* No values returned on the stack */
}

/*============================================================================*/
/* STRUCT-BY-VALUE SUPPORT                                                    */
/*============================================================================*/

/* Note: inputs must be validated by caller:
*  At least 1 field
*  All fields must be valid ffi_type pointers
*
* Create a new FFI Type for StructureByValue calls (NOT related to structure
* packing, does not support custom padding/layout: just support standard calls
* with structure in order to call functions with StructureByValue in parameter)
*
* This is not common. Usually code use StructureByReference (pointers) in most
* APIs.
*/
static int FFI_NewStructureType (lua_State *LuaState)
{
  struct FFI_StructType *NewStructType;
  ffi_type             **Elements;
  ffi_type              *FieldType;
  size_t                 FieldCount;
  size_t                 Offset;
  int                    LuaIndex;

  FieldCount = lua_gettop(LuaState);
  Elements   = PLAT_SafeAlloc0((FieldCount + 1), sizeof(ffi_type *));

  for (Offset = 0; (Offset < FieldCount); Offset++)
  {
    LuaIndex  = (Offset + 1);
    FieldType = lua_touserdata(LuaState, LuaIndex);

    /* Assume FieldType is valid */
    Elements[Offset] = FieldType;
  }

  /* Sentinel, required by libffi at the end of the list */
  Elements[FieldCount] = NULL;

  NewStructType = PLAT_SafeAlloc0(1, sizeof(struct FFI_StructType));

  NewStructType->Type.size      = 0; /* Calculated by ffi_get_struct_offsets */
  NewStructType->Type.alignment = 0; /* Calculated by ffi_get_struct_offsets */
  NewStructType->Type.type      = FFI_TYPE_STRUCT;
  NewStructType->Type.elements  = Elements;
  NewStructType->FieldCount     = FieldCount;

  lua_pushlightuserdata(LuaState, NewStructType);

  return 1; /* Number of values returned on the stack */
}

/* Note: inputs must be validated by caller */
static int FFI_GetStructOffsets (lua_State *LuaState)
{
  struct FFI_StructType *StructType = lua_touserdata(LuaState, 1);
  size_t                 FieldCount = StructType->FieldCount;
  size_t                *Offsets    = FFI_GetOffsetBufferData(LuaState, FieldCount);
  size_t                 Offset;
  size_t                 LuaIndex;
  ffi_status             Status;

  Status = ffi_get_struct_offsets(FFI_DEFAULT_ABI, &StructType->Type, Offsets);

  lua_pushinteger(LuaState, Status);

  if (Status == FFI_OK)
  {
    lua_createtable(LuaState, FieldCount, 0);
    for (Offset = 0; (Offset < FieldCount); Offset++)
    {
      LuaIndex = (Offset + 1);
      lua_pushinteger(LuaState, Offsets[Offset]);
      lua_rawseti(LuaState, -2, LuaIndex);
    }
  }
  else
  {
    lua_pushnil(LuaState);
  }

  return 2; /* Number of values returned on the stack */
}

/* Note: inputs must be validated by caller */
static int FFI_GetStructInfo (lua_State *LuaState)
{
  ffi_type *StructType = lua_touserdata(LuaState, 1);

  lua_pushinteger(LuaState, StructType->size);
  lua_pushinteger(LuaState, StructType->alignment);

  return 2; /* Number of values returned on the stack */
}

/*============================================================================*/
/* LIBFFI RAW INTERFACE                                                       */
/*============================================================================*/

/* Note: inputs must be validated by caller */
/* Usage: FFI_NewCif(SignatureTable) */
static int FFI_NewCif (lua_State *LuaState)
{
  struct FFI_Cif *Cif      = PLAT_SafeAlloc0(1, sizeof(struct FFI_Cif));
  size_t          Count    = lua_rawlen(LuaState, 1);
  size_t          ArgCount = (Count - 1);
  ffi_type       *ReturnType;
  ffi_type       *ArgType;
  size_t          Offset;
  ffi_status      Status;
  size_t          LuaIndex;

  /* Return type */
  lua_rawgeti(LuaState, 1, 1);
  ReturnType = lua_touserdata(LuaState, -1);
  lua_pop(LuaState, 1);

  /* Assume ReturnType is correct: ReturnType not NULL */
  Cif->ReturnType = ReturnType;
  Cif->ArgCount   = ArgCount;

  /* Format list of Cif->ArgTypes if needed */
  if (ArgCount == 0)
  {
    Cif->ArgTypes = NULL;
  }
  else
  {
    Cif->ArgTypes = PLAT_SafeAlloc0(ArgCount, sizeof(ffi_type *));
    Offset        = 0;

    while (Offset < ArgCount)
    {
      LuaIndex = (Offset + 2);
      
      /* Extract argument type from table */
      lua_rawgeti(LuaState, 1, LuaIndex);
      ArgType = lua_touserdata(LuaState, -1);
      lua_pop(LuaState, 1);

      /* Assume ArgType is correct */
      Cif->ArgTypes[Offset] = ArgType;
      Offset++;
    }
  }

  Status = ffi_prep_cif(&Cif->cif,
                        FFI_DEFAULT_ABI,
                        ArgCount,
                        Cif->ReturnType,
                        Cif->ArgTypes);
  
  /* Return value */
  if (Status == FFI_OK)
  {
    lua_pushlightuserdata(LuaState, Cif);
  }
  else
  {
    /* Cleanup resources */
    if (Cif->ArgTypes)
    {
      PLAT_Free(Cif->ArgTypes);
    }
    PLAT_Free(Cif);

    lua_pushnil(LuaState);
  }

  lua_pushinteger(LuaState, Status);

  return 2; /* Number of values returned on the stack */
}

static int FFI_NewCallContext (lua_State *LuaState)
{
  struct FFI_Cif          *Cif             = lua_touserdata(LuaState, 1);
  ffi_type                *ReturnType      = Cif->ReturnType;
  size_t                   ReturnValueSize = FFI_AT_LEAST(ReturnType->size, 8);
  size_t                   ArgCount        = Cif->ArgCount;
  ffi_type               **ArgTypes        = Cif->ArgTypes;
  struct FFI_CallContext  *NewContext;
  size_t                   Offset;
  size_t                   ArgSize;

  NewContext = PLAT_SafeAlloc0(1, sizeof(struct FFI_CallContext));

  /* Fill context */
  NewContext->Cif         = Cif;
  NewContext->ReturnValue = PLAT_SafeAlloc0(1, ReturnValueSize);

  if (ArgCount > 0)
  {
    NewContext->ArgValues = PLAT_SafeAlloc0(ArgCount, sizeof(void *));
    for (Offset = 0; (Offset < ArgCount); Offset++)
    {
      /* At least 8 bytes to ensure pointer alignment */
      ArgSize                       = FFI_AT_LEAST(ArgTypes[Offset]->size, 8);
      NewContext->ArgValues[Offset] = PLAT_SafeAlloc0(1, ArgSize);
    }
  }
  else
  {
    NewContext->ArgValues = NULL;
  }

  lua_pushlightuserdata(LuaState, NewContext);
  
  return 1; /* Number of values returned on the stack */
}

/* This function is for CallStructByValue. It simply returns a pointer to the
 * return value of the CIF (created with FFI_NewCallContext). It allows the Lua
 * side to avoid the need for copying the value back and forth between C and
 * Lua. */
static int FFI_GetCifReturnPointer (lua_State *LuaState)
{
  struct FFI_CallContext *Context = lua_touserdata(LuaState, 1);

  lua_pushlightuserdata(LuaState, Context->ReturnValue);

  return 1; /* Number of values returned on the stack */
}

static int FFI_CallFunction (lua_State *LuaState)
{
  struct FFI_CallContext  *CallContext     = lua_touserdata(LuaState, 1);
  void                    *FunctionPointer = lua_touserdata(LuaState, 2);
  struct FFI_Cif          *Cif             = CallContext->Cif;
  ffi_type                *ReturnType      = Cif->ReturnType;
  ffi_type               **ArgTypes        = Cif->ArgTypes;
  size_t                   Offset;
  size_t                   LuaIndex;
  size_t                   ArgSize;
  size_t                   ReturnValueSize;

  /* Retrieve table size */
  luaL_checktype(LuaState, 3, LUA_TTABLE);

  /* Clear return value */
  ReturnValueSize = FFI_AT_LEAST(ReturnType->size, 8);
  memset(CallContext->ReturnValue, 0, ReturnValueSize);

  /* Note that we use Cif->ArgCount and not table size */
  /* Copy arguments from Lua stack */
  for (Offset = 0; (Offset < Cif->ArgCount); Offset++)
  {
    ArgSize = FFI_AT_LEAST(ArgTypes[Offset]->size, 8);
    memset(CallContext->ArgValues[Offset], 0, ArgSize);
    LuaIndex = (Offset + 1);
    lua_rawgeti(LuaState, 3, LuaIndex);
    FFI_CopyLuaValueToCif(LuaState, -1, ArgTypes[Offset], CallContext->ArgValues[Offset]);
    lua_pop(LuaState, 1);
  }

  /* Call */
  ffi_call(&Cif->cif,
           FFI_FN(FunctionPointer),
           CallContext->ReturnValue,
           CallContext->ArgValues);

  /* Push return value */
  FFI_PushValue(LuaState, Cif->ReturnType, CallContext->ReturnValue);

  return 1; /* Number of values returned on the stack */
}

static int FFI_FreeCallContext (lua_State *LuaState)
{
  struct FFI_CallContext *Context = lua_touserdata(LuaState, 1);
  struct FFI_Cif         *Cif     = Context->Cif;
  size_t                  Offset;

  /* Return Value */
  PLAT_Free(Context->ReturnValue);
  
  /* Release ArgValues if existing */
  if (Context->ArgValues)
  {
    for (Offset = 0; (Offset < Cif->ArgCount); Offset++)
    {
      if (Context->ArgValues[Offset])
      {
        PLAT_Free(Context->ArgValues[Offset]);
      }
    }
    
    PLAT_Free(Context->ArgValues);
  }

  /* Main context */
  PLAT_Free(Context);
  
  return 0; /* Number of values returned on the stack */
}

static int FFI_FreeCif (lua_State *LuaState)
{
  struct FFI_Cif *Cif = lua_touserdata(LuaState, 1);

  /* Argument types */
  if (Cif->ArgTypes)
  {
    PLAT_Free(Cif->ArgTypes);
  }

  /* Main structure */
  PLAT_Free(Cif);

  return 0; /* Number of values returned on the stack */
}

static void FFI_ClosureCallback (ffi_cif  *cif,
                                 void     *ReturnValue,
                                 void    **Args,
                                 void     *UserData)
{
  struct FFI_Closure *Closure  = UserData;
  struct FFI_Cif     *Cif      = Closure->Cif;
  lua_State          *LuaState = Closure->LuaState;
  size_t              Offset;
  const char         *ErrorMessage;

  /* Unused parameter */
  (void)cif;
  
  /* Push the Lua function to the Lua stack */
  lua_rawgeti(LuaState, LUA_REGISTRYINDEX, Closure->FunctionRef);

  /* Push arguments to the Lua stack */
  for (Offset = 0; (Offset < Cif->ArgCount); Offset++)
  {
    FFI_PushValue(LuaState, Cif->ArgTypes[Offset], Args[Offset]);
  }

  /* Call the Lua function, expects 1 return value */
  if (lua_pcall(LuaState, Cif->ArgCount, 1, 0) == LUA_OK)
  {
    /* Copy the Lua return value to ffi */
    if (Cif->ReturnType != &ffi_type_void)
    {
      FFI_CopyLuaValueToCif(LuaState, -1, Cif->ReturnType, ReturnValue);
    }

    /* Remove the value from the stack */
    lua_pop(LuaState, 1);
  }
  else
  {
    /* Error handling */
    ErrorMessage = lua_tostring(LuaState, -1);
    fprintf(stderr, "Error: %s\n", ErrorMessage);
    lua_pop(LuaState, 1);
  }
}

static int FFI_NewClosure (lua_State *LuaState)
{
  struct FFI_Cif     *Cif = lua_touserdata(LuaState, 1);
  struct FFI_Closure *NewClosure;
  ffi_closure        *FfiClosure;
  int                 FunctionRef;
  ffi_status          Status;
  void               *ExecutableAddress;

  /* Check parameters */
  luaL_checktype(LuaState, 2, LUA_TFUNCTION);
  
  /* Allocate ffi closure */
  ExecutableAddress = NULL;
  FfiClosure        = ffi_closure_alloc(sizeof(ffi_closure),
                                        &ExecutableAddress);

  if (FfiClosure == NULL)
  {
    return luaL_error(LuaState, "Failed to allocate FFI closure");
  }
  
  /* Store the Lua function reference */
  lua_pushvalue(LuaState, 2);
  FunctionRef = luaL_ref(LuaState, LUA_REGISTRYINDEX);
  
  /* Allocate a new closure data structure */
  NewClosure              = PLAT_SafeAlloc0(1, sizeof(struct FFI_Closure));
  NewClosure->LuaState    = LuaState;
  NewClosure->FunctionRef = FunctionRef;
  NewClosure->Cif         = Cif;
  NewClosure->Closure     = FfiClosure;
  
  /* Prepare closure */
  Status = ffi_prep_closure_loc(FfiClosure,
                                &Cif->cif,
                                FFI_ClosureCallback,
                                NewClosure,
                                ExecutableAddress);
  
  if (Status != FFI_OK)
  {
    ffi_closure_free(FfiClosure);
    luaL_unref(LuaState, LUA_REGISTRYINDEX, FunctionRef);
    PLAT_Free(NewClosure);
    return luaL_error(LuaState, "Failed to prepare FFI closure");
  }

  lua_pushlightuserdata(LuaState, NewClosure);        /* Closure context    */
  lua_pushlightuserdata(LuaState, ExecutableAddress); /* C function pointer */
  
  return 2; /* Number of values returned on the stack */
}

static int FFI_FreeClosure (lua_State *LuaState)
{
  struct FFI_Closure *CifClosure = lua_touserdata(LuaState, 1);
  
  luaL_unref(LuaState, LUA_REGISTRYINDEX, CifClosure->FunctionRef);

  ffi_closure_free(CifClosure->Closure);

  PLAT_Free(CifClosure);
  
  return 0; /* Number of values returned on the stack */
}

/*============================================================================*/
/* MEMORY AND POINTERS                                                        */
/*============================================================================*/

/* read memory blob into Lua binary string */
static int FFI_ReadMemory (lua_State *LuaState)
{
  char   *Address = lua_touserdata(LuaState, 1);
  size_t  Offset  = luaL_checkinteger(LuaState, 2);
  size_t  Length  = luaL_checkinteger(LuaState, 3);

  lua_pushlstring(LuaState, &Address[Offset], Length);
  
  return 1; /* Number of values returned on the stack */
}

/* write memory blob from Lua binary string */
static int FFI_WriteMemory (lua_State *LuaState)
{
  char       *Address = lua_touserdata(LuaState, 1);
  size_t      Offset = luaL_checkinteger(LuaState, 2);
  size_t      Length;
  const char *Source = luaL_checklstring(LuaState, 3, &Length);
        
  memcpy(&Address[Offset], Source, Length);
  
  return 0; /* Number of values returned on the stack */
}

static int FFI_NewPointerFromLuaInts (lua_State *LuaState)
{
  int32_t  HighValue = luaL_checkinteger(LuaState, 1);
  int32_t  LowValue  = luaL_checkinteger(LuaState, 2);
  void    *Pointer;

  /* Combine the two int32 values into a pointer value */
  Pointer = (void*)(((uintptr_t)HighValue << 32) | (uintptr_t)LowValue);

  /* Push the pointer as lightuserdata */
  lua_pushlightuserdata(LuaState, Pointer);

  return 1; /* Number of values returned on the stack */
}

/* read pointer value from memory and return it as lightuserdata */
static int FFI_ReadPointer (lua_State *LuaState)
{
  char   *Address = lua_touserdata(LuaState, 1);
  size_t  Offset  = luaL_checkinteger(LuaState, 2);
  void   *Value   = NULL;

  memcpy(&Value, &Address[Offset], sizeof(void *));
  
  lua_pushlightuserdata(LuaState, Value);

  return 1; /* Number of values returned on the stack */
}

/* write pointer from lightuserdata */
static int FFI_WritePointer (lua_State *LuaState)
{
  char   *Address = lua_touserdata(LuaState, 1);
  size_t  Offset  = luaL_checkinteger(LuaState, 2);
  void   *Value   = lua_touserdata(LuaState, 3);

  memcpy(&Address[Offset], &Value, sizeof(void *));
  
  return 0; /* Number of values returned on the stack */
}

static int FFI_ConvertPointer (lua_State *LuaState)
{
  void       *Pointer = lua_touserdata(LuaState, 1);
  const char *Type    = luaL_checkstring(LuaState, 2);
  uint32_t    HighValue;
  uint32_t    LowValue;
  size_t      SizeInBytes;
  int32_t     ReturnedValues;
  
  if (STRING_Equals(Type, "integer"))
  {
    HighValue = (uint32_t)(((uintptr_t)Pointer >> 32) & 0xFFFFFFFF);
    LowValue  = (uint32_t)(((uintptr_t)Pointer >>  0) & 0xFFFFFFFF);
    
    lua_pushinteger(LuaState, HighValue);
    lua_pushinteger(LuaState, LowValue);

    ReturnedValues = 2;
  }
  else if (STRING_Equals(Type, "string"))
  {
    SizeInBytes = sizeof(void *);
    lua_pushlstring(LuaState, (const char*)&Pointer, SizeInBytes);

    ReturnedValues = 1;
  }
  else
  {
    return luaL_error(LuaState, "Unknown type: %s", Type);
  }

  return ReturnedValues; /* Number of values returned on the stack */
}

static int FFI_PointerOffset (lua_State *LuaState)
{
  void      *Pointer    = lua_touserdata(LuaState, 1);
  ptrdiff_t  Offset     = (ptrdiff_t)luaL_checkinteger(LuaState, 2);
  void      *NewPointer = (void *)((uintptr_t)Pointer + Offset);
  
  lua_pushlightuserdata(LuaState, NewPointer);
  
  return 1; /* Number of values returned on the stack */
}

static int FFI_PointerDiff (lua_State *LuaState)
{
  void      *PointerA = lua_touserdata(LuaState, 1);
  void      *PointerB = lua_touserdata(LuaState, 2);
  ptrdiff_t  Diff     = (ptrdiff_t)((uintptr_t)PointerA - (uintptr_t)PointerB);
  
  lua_pushinteger(LuaState, Diff);
  
  return 1; /* Number of values returned on the stack */
}

static int FFI_DereferencePointer (lua_State *LuaState)
{
  void **PointerToPointer = lua_touserdata(LuaState, 1);
  
  if (PointerToPointer == NULL)
  {
    return luaL_error(LuaState, "Cannot dereference NULL pointer");
  }
  
  /* Dereference pointer to get the actual pointer value */
  void *Value = *PointerToPointer;
  
  lua_pushlightuserdata(LuaState, Value);
  
  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* MIMALLOC MEMORY MANAGEMENT                                                 */
/*============================================================================*/

static int32_t FFI_GetPageSizeInBytes (lua_State *LuaState)
{
  size_t PageSizeInBytes = PLAT_GetPageSizeInBytes();
  
  lua_pushinteger(LuaState, PageSizeInBytes);
  
  return 1; /* Number of values returned on the stack */
}

static int32_t FFI_Malloc (lua_State *LuaState)
{
  size_t  SizeInBytes = luaL_checkinteger(LuaState, 1);
  void   *Pointer     = PLAT_SafeAlloc0(1, SizeInBytes);
  
  lua_pushlightuserdata(LuaState, Pointer);
  
  return 1; /* Number of values returned on the stack */
}

static int32_t FFI_Realloc (lua_State *LuaState)
{
  void   *Pointer     = lua_touserdata(LuaState, 1);
  size_t  SizeInBytes = luaL_checkinteger(LuaState, 2);
  void   *NewPointer  = PLAT_SafeRealloc(Pointer, SizeInBytes);

  lua_pushlightuserdata(LuaState, NewPointer);

  return 1; /* Number of values returned on the stack */
}

static int32_t FFI_Free (lua_State *LuaState)
{
  void *Pointer = lua_touserdata(LuaState, 1);
  
  PLAT_Free(Pointer);
  
  return 0; /* No values returned on the stack */
}

static int32_t FFI_Memset (lua_State *LuaState)
{
  void   *Pointer     = lua_touserdata(LuaState, 1);
  int32_t Value       = luaL_checkinteger(LuaState, 2);
  size_t  SizeInBytes = luaL_checkinteger(LuaState, 3);
  
  memset(Pointer, Value, SizeInBytes);
  
  return 0; /* Number of values returned on the stack */
}

/*============================================================================*/
/* PUBLIC API                                                                 */
/*============================================================================*/

static const struct luaL_Reg FFI_FUNCTIONS[] =
{
  /* Dynamic library management */
  { "loadlib",              FFI_LoadLibrary           },
  { "getproc",              FFI_GetProcAddress        },
  { "freelib",              FFI_FreeLibrary           },
  /* Struct-by-value support */
  { "newstruct",            FFI_NewStructureType      },
  { "getstructinfo",        FFI_GetStructInfo         },
  { "getstructoffsets",     FFI_GetStructOffsets      },
  /* low-level interface to libffi */
  { "newcif",               FFI_NewCif                },
  { "getcifreturnpointer",  FFI_GetCifReturnPointer   },
  { "newcallcontext",       FFI_NewCallContext        },
  { "call",                 FFI_CallFunction          },
  { "freecallcontext",      FFI_FreeCallContext       },
  { "freecif",              FFI_FreeCif               },
  { "newclosure",           FFI_NewClosure            },
  { "freeclosure",          FFI_FreeClosure           },
  /* Memory and pointers */
  { "readmemory",           FFI_ReadMemory            },
  { "writememory",          FFI_WriteMemory           },
  { "readpointer",          FFI_ReadPointer           },
  { "writepointer",         FFI_WritePointer          },
  { "newpointer",           FFI_NewPointerFromLuaInts },
  { "convertpointer",       FFI_ConvertPointer        },
  { "derefpointer",         FFI_DereferencePointer    },
  { "pointeroffset",        FFI_PointerOffset         },
  { "pointerdiff",          FFI_PointerDiff           },
  /* mimalloc */
  { "getpagesize",          FFI_GetPageSizeInBytes    },
  { "malloc",               FFI_Malloc                },
  { "realloc",              FFI_Realloc               },
  { "free",                 FFI_Free                  },
  { "memset",               FFI_Memset                },
  /* over-engineered shit */
  { "freeresources",        FFI_FreeOffsetsBuffer     },
  /* End of list */
  { NULL, NULL }
};

LUALIB_API int luaopen_libffiraw (lua_State *LuaState)
{
  /* Register functions */
  luaL_newlib(LuaState, FFI_FUNCTIONS);

  /* Expose type constants as lightuserdata */
  lua_pushlightuserdata(LuaState, &ffi_type_void);
  lua_setfield(LuaState, -2, "void");
  lua_pushlightuserdata(LuaState, &ffi_type_uint8);
  lua_setfield(LuaState, -2, "uint8");
  lua_pushlightuserdata(LuaState, &ffi_type_sint8);
  lua_setfield(LuaState, -2, "sint8");
  lua_pushlightuserdata(LuaState, &ffi_type_uint16);
  lua_setfield(LuaState, -2, "uint16");
  lua_pushlightuserdata(LuaState, &ffi_type_sint16);
  lua_setfield(LuaState, -2, "sint16");
  lua_pushlightuserdata(LuaState, &ffi_type_uint32);
  lua_setfield(LuaState, -2, "uint32");
  lua_pushlightuserdata(LuaState, &ffi_type_sint32);
  lua_setfield(LuaState, -2, "sint32");
  lua_pushlightuserdata(LuaState, &ffi_type_uint64);
  lua_setfield(LuaState, -2, "uint64");
  lua_pushlightuserdata(LuaState, &ffi_type_sint64);
  lua_setfield(LuaState, -2, "sint64");
  lua_pushlightuserdata(LuaState, &ffi_type_float);
  lua_setfield(LuaState, -2, "float");
  lua_pushlightuserdata(LuaState, &ffi_type_double);
  lua_setfield(LuaState, -2, "double");
  lua_pushlightuserdata(LuaState, &ffi_type_pointer);
  lua_setfield(LuaState, -2, "pointer");
#ifdef FFI_TARGET_HAS_COMPLEX_TYPE
  lua_pushlightuserdata(LuaState, &ffi_type_complex_float);
  lua_setfield(LuaState, -2, "complex_float");
  lua_pushlightuserdata(LuaState, &ffi_type_complex_double);
  lua_setfield(LuaState, -2, "complex_double");
#endif
  lua_pushinteger(LuaState, FFI_TYPE_STRUCT);
  lua_setfield(LuaState, -2, "struct");
  lua_pushinteger(LuaState, FFI_OK);
  lua_setfield(LuaState, -2, "FFI_OK");
  
  /* Add NULL constant as lightuserdata */
  lua_pushlightuserdata(LuaState, NULL);
  lua_setfield(LuaState, -2, "NULL");
  
  return 1; /* Number of values returned on the stack */
}
