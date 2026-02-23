/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-libwin32-com.c                                                *
 * CONTENT  Expose raw Windows COM functions to Lua (lightuserdata)           *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*
 * WARNING: This module exposes raw COM pointers (IDispatch*, VARIANT*, etc.) *
 * as lightuserdata. Lua code is responsible for all memory management and    *
 * correct usage. Misuse will cause memory leaks or crashes.                  *
 * This design is intended to keep C code trivial, moving complexity to Lua   *
 *----------------------------------------------------------------------------*/

/*
 * Note that Win32 API is slightly confusing:
 * - CLSID is a kind of ID to specify the type of a COM object
 * - Sometimes it's refered as GUID, IsEqualGUID also work for CLSID
 * - For IUNKNOWN QueryInterface an IID is required, which technically could be
 *   something intended for CLSID like CLSIDFromString
 *
 * COM Main APIs. To avoid difficulty to find proper names and proper
 * interfaces, we just stick to COM APIs. Clever things to be done on the Lua
 * side.
 * 
 * BSTR is a kind of Win32 fat string, which is basically a string prefixed by
 * a field containing its length, SysAllocString allocate and format such kind
 * of string. BSTR is composed of OLECHAR (which is WCHAR).
 *
 * In SAFEARRAY API, there is someting weird. SafeArrayCreate takes lower bounds
 * and element count. On the API side, we can find SAFEARRAY_GetLBound
 * (expected) and SAFEARRAY_GetUBound (unexpected) and not SAFEARRAY_GetDimCount.
 *
 * IUnknown::AddRef
 * IUnknown::QueryInterface
 * IUnknown::Release
 *
 * IDispatch::GetIDsOfNames
 * IDispatch::GetTypeInfo
 * IDispatch::GetTypeInfoCount
 * IDispatch::Invoke
 *
 * == SUPPORT ==
 * [x] VT_EMPTY
 * [x] VT_NULL
 * [ ] VT_I2
 * [ ] VT_I4
 * [x] VT_R4
 * [x] VT_R8
 * [ ] VT_CY --- Currency
 * [x] VT_DATE
 * [x] VT_BSTR
 * [x] VT_DISPATCH
 * [ ] VT_ERROR
 * [x] VT_BOOL
 * [x] VT_VARIANT
 * [x] VT_UNKNOWN
 * [ ] VT_DECIMAL
 * [ ] VT_I1
 * [ ] VT_UI1
 * [ ] VT_UI2
 * [x] VT_UI4
 * [x] VT_I8
 * [x] VT_UI8
 * [x] VT_INT
 * [x] VT_UINT
 * [x] VT_VOID
 * [ ] VT_HRESULT
 * [ ] VT_PTR
 * [x] VT_SAFEARRAY
 * [ ] VT_CARRAY
 * [ ] VT_USERDEFINED
 * [ ] VT_LPSTR
 * [ ] VT_LPWSTR
 * [ ] VT_RECORD
 * [ ] VT_INT_PTR
 * [ ] VT_UINT_PTR
 * [x] VT_ARRAY
 * [ ] VT_BYREF
 */

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/*---------*/
/* HEADERS */
/*---------*/

/* The external luaopen_XXX will be automatically generated, but it rely on
 * the type lua_State, so lua.h need to be included before luaopen_XXX */
#include <lua.h>

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <lauxlib.h> /* luaL_checkinteger */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <combaseapi.h> /* CLSIDFromString */

#include <stdbool.h>
#include <string.h> /* memcpy */

/*============================================================================*/
/* PRIVATE FUNCTIONS                                                          */
/*============================================================================*/

#define IF(Condition, TrueExpression, FalseExpression) ((Condition) ? (TrueExpression) : (FalseExpression))

/* VARIANT_BOOL: 0x0000 if false 0xFFFF true */
static VARIANT_BOOL COM_LuaBoolToVariant (lua_State *LuaState, int Index)
{
  VARIANT_BOOL Result;

  if (lua_toboolean(LuaState, Index))
  {
    Result = VARIANT_TRUE;
  }
  else
  {
    Result = VARIANT_FALSE;
  }

  return Result;
}

static void COM_PushVariantBool (lua_State *LuaState, VARIANT_BOOL Boolean)
{
  if (Boolean == VARIANT_FALSE)
  {
    lua_pushboolean(LuaState, 0);
  }
  else
  {
    lua_pushboolean(LuaState, 1);
  }
}

/*============================================================================*/
/* CLSID MANAGEMENT: HIGH-LEVEL, NOT RAW BINDINGS                             */
/*============================================================================*/

/* The CLSID format is {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx} 38 characters +
 * null terminator, totally 39 characters.
 *
 * Return a full userdata containing the raw CLSID (sizeof(CLSID)).
 */
static int COM_NewClsid (lua_State *LuaState)
{
  CLSID    Clsid;
  wchar_t *ClsidString = (wchar_t *)luaL_checkstring(LuaState, 1);
  HRESULT  Result      = CLSIDFromString(ClsidString, &Clsid);
  CLSID   *UserData;
  
  if (SUCCEEDED(Result) && !IsEqualGUID(&Clsid, &GUID_NULL))
  {
    UserData = lua_newuserdatauv(LuaState, sizeof(CLSID), 0);
    memcpy(UserData, &Clsid, sizeof(CLSID));
  }
  else
  {
    lua_pushnil(LuaState);
  }
  
  return 1; /* Number of values returned on the stack */
}

static int COM_ClsidToStringU16 (lua_State *LuaState)
{
  wchar_t  ClsidString[40];
  CLSID   *ClsidObject = lua_touserdata(LuaState, 1);
  int      MaxChars    = (sizeof(ClsidString) / sizeof(wchar_t));
  int      StringLength;
  size_t   ByteCount;

  if (ClsidObject)
  {
    /* StringFromGUID2 return value: number of characters including terminator */
    StringLength = StringFromGUID2(ClsidObject, ClsidString, MaxChars);

    if (StringLength <= 1)
    {
      lua_pushnil(LuaState);
    }
    else
    {
      ByteCount = ((StringLength - 1) * sizeof(wchar_t));
      lua_pushlstring(LuaState, (const char *)ClsidString, ByteCount);
    }
  }
  else
  {
    lua_pushnil(LuaState);
  }

  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* IUNKNOWN INTERFACE FUNCTIONS                                               */
/*============================================================================*/

static int IUNKNOWN_AddRef (lua_State *LuaState)
{
  IUnknown *Unknown  = lua_touserdata(LuaState, 1);
  ULONG     RefCount = Unknown->lpVtbl->AddRef(Unknown);

  lua_pushinteger(LuaState, RefCount);
  
  return 1; /* Number of values pushed on the stack */
}

static int IUNKNOWN_Release (lua_State *LuaState)
{
  IUnknown *Unknown  = lua_touserdata(LuaState, 1);
  ULONG     RefCount = Unknown->lpVtbl->Release(Unknown);

  printf("[DEBUG] IUNKNOWN_Release %p\n", Unknown);
  
  lua_pushinteger(LuaState, RefCount);
  
  return 1; /* Number of values pushed on the stack */
}

static int IUNKNOWN_QueryInterface (lua_State *LuaState)
{
  IUnknown  *Unknown   = lua_touserdata(LuaState, 1);
  const IID *RIID      = lua_touserdata(LuaState, 2);
  void      *Interface = NULL;
  
  HRESULT Result = Unknown->lpVtbl->QueryInterface(Unknown, RIID, &Interface);

  lua_pushinteger(LuaState, Result);
  lua_pushlightuserdata(LuaState, Interface);

  return 2; /* Number of values pushed on the stack */
}

/*============================================================================*/
/* PUBLIC API: VARIANTS                                                       */
/*============================================================================*/

static int VARIANT_GetSizeInBytes (lua_State *LuaState)
{
  lua_pushinteger(LuaState, sizeof(VARIANT));

  return 1; /* Number of values pushed on the stack */
}

static int VARIANT_Init (lua_State *LuaState)
{
  VARIANT *Variant = lua_touserdata(LuaState, 1);

  VariantInit(Variant);

  return 0; /* Number of values pushed on the stack */
}

static int VARIANT_Clear (lua_State *LuaState)
{
  VARIANT *Variant = lua_touserdata(LuaState, 1);
  HRESULT  Result  = VariantClear(Variant);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values pushed on the stack */
}

/* In this function COM_VariantSetString, the only source of error is
 * SysAllocString, like platform.c we simply exit on failure.
 */
static void VARIANT_SetString (VARIANT *Variant, const wchar_t *StringUtf16)
{
   /* The string will be free with a call to VARIANT_Clear */
  BSTR NewStringUtf16 = SysAllocString(StringUtf16);
  
  if (NewStringUtf16)
  {
    Variant->vt      = VT_BSTR;
    Variant->bstrVal = NewStringUtf16;
  }
  else
  {
    fprintf(stderr, "FATAL ERROR: Failed to allocate BSTR\n");
    exit(1);
  }
}

static int VARIANT_Set (lua_State *LuaState)
{
  VARIANT    *Variant       = lua_touserdata(LuaState, 1);
  int         VariantType   = lua_tointeger(LuaState, 2);
  int         ArgumentCount = lua_gettop(LuaState);
  wchar_t    *StringUtf16;
  IDispatch  *Dispatch;
  SAFEARRAY  *Array;

  VariantClear(Variant);

  /* For VT_EMPTY and VT_NULL, the 3rd parameter can be omited, it will be
   * ignored anyway */
  if ((ArgumentCount >= 2)
      && ((VariantType == VT_EMPTY)
          || (VariantType == VT_NULL)
          || (VariantType == VT_VOID)))
  {
    Variant->vt = VariantType;
  }
  else if (ArgumentCount == 3)
  {
    switch (VariantType)
    {
    case VT_BOOL:
      Variant->vt      = VT_BOOL;
      Variant->boolVal = COM_LuaBoolToVariant(LuaState, 3);
      break;
    case VT_I4:
      Variant->vt   = VT_I4;
      Variant->lVal = lua_tointeger(LuaState, 3);
      break;
    case VT_I8:
      Variant->vt    = VT_I8;
      Variant->llVal = lua_tointeger(LuaState, 3);
      break;
    case VT_R4:
      Variant->vt     = VT_R4;
      Variant->fltVal = lua_tonumber(LuaState, 3);
      break;
    case VT_R8:
      Variant->vt     = VT_R8;
      Variant->dblVal = lua_tonumber(LuaState, 3);
      break;
    case VT_DATE:
      Variant->vt   = VT_DATE;
      Variant->date = lua_tonumber(LuaState, 3);
      break;
    case VT_BSTR:
      StringUtf16 = (wchar_t *)lua_tostring(LuaState, 3);
      VARIANT_SetString(Variant, StringUtf16);
      break;
    case VT_UNKNOWN:
      Variant->vt      = VT_UNKNOWN;
      Variant->punkVal = lua_touserdata(LuaState, 3);
      if (Variant->punkVal)
      {
        /* VariantClear will Release */
        Variant->punkVal->lpVtbl->AddRef(Variant->punkVal);
      }
      break;
    case VT_DISPATCH:
      Dispatch          = lua_touserdata(LuaState, 3);
      Variant->vt       = VT_DISPATCH;
      Variant->pdispVal = Dispatch;
      if (Dispatch)
      {
        /* VariantClear will Release */
        Dispatch->lpVtbl->AddRef(Dispatch);
      }
      break;
    default:
      /* For arrays, variant takes ownership of SAFEARRAY and will call SafeArrayDestroy */
      if ((VariantType & VT_ARRAY) == VT_ARRAY)
      {
        Array           = lua_touserdata(LuaState, 3);
        Variant->vt     = VariantType;
        Variant->parray = Array;
        /* IMPORTANT: VariantClear will call SafeArrayDestroy on parray.
         * Caller must NOT destroy the SAFEARRAY after passing it here. */
      }
      else
      {
      	luaL_error(LuaState, "VT_ARRAY Type VT_XXX not supported: %d", VariantType);
      }
      break;
    }
  }
  else
  {
    luaL_error(LuaState, "Need 3 arguments");
  }

  /* Success */
  lua_pushboolean(LuaState, 1);

  return 1; /* Number of values pushed on the stack */
}

static int VARIANT_Get (lua_State *LuaState)
{
  VARIANT   *Variant     = lua_touserdata(LuaState, 1);
  VARTYPE    VariantType = Variant->vt;
  BSTR       StringUtf16;
  size_t     SizeInBytes;
  SAFEARRAY *Array;
  
  switch (VariantType)
  {
  case VT_EMPTY:
  case VT_NULL:
  case VT_VOID:
    lua_pushnil(LuaState);
    lua_pushinteger(LuaState, VariantType);
    lua_pushnil(LuaState);
    break;
  case VT_BOOL:
    COM_PushVariantBool(LuaState, Variant->boolVal);
    lua_pushinteger(LuaState, VariantType);
    lua_pushnil(LuaState);
    break;
  case VT_I4:
    lua_pushinteger(LuaState, Variant->lVal);
    lua_pushinteger(LuaState, VariantType);
    lua_pushnil(LuaState);
    break;
  case VT_I8:
    lua_pushinteger(LuaState, Variant->llVal);
    lua_pushinteger(LuaState, VariantType);
    lua_pushnil(LuaState);
    break;
  case VT_R4:
    lua_pushnumber(LuaState, Variant->fltVal);
    lua_pushinteger(LuaState, VariantType);
    lua_pushnil(LuaState);
    break;
  case VT_R8:
    lua_pushnumber(LuaState, Variant->dblVal);
    lua_pushinteger(LuaState, VariantType);
    lua_pushnil(LuaState);
    break;
  case VT_DATE:
    lua_pushnumber(LuaState, Variant->date);
    lua_pushinteger(LuaState, VariantType);
    lua_pushnil(LuaState);
    break;
  case VT_BSTR:
    StringUtf16 = Variant->bstrVal;
    if (StringUtf16)
    {
      SizeInBytes = (SysStringLen(StringUtf16) * sizeof(wchar_t));
      lua_pushlstring(LuaState, (const char *)StringUtf16, SizeInBytes);
      lua_pushinteger(LuaState, VariantType);
      lua_pushnil(LuaState);
    }
    else
    {
      lua_pushnil(LuaState);
      lua_pushinteger(LuaState, VariantType);
      lua_pushstring(LuaState, "BSTR value is NULL");
    }
    break;
  case VT_DISPATCH:
    /* Return IDispatch* as lightuserdata, or nil if not present */
    if (Variant->pdispVal)
    {
      Variant->pdispVal->lpVtbl->AddRef(Variant->pdispVal);
      lua_pushlightuserdata(LuaState, Variant->pdispVal);
      lua_pushinteger(LuaState, VariantType);
      lua_pushnil(LuaState);
    }
    else
    {
      lua_pushnil(LuaState);
      lua_pushinteger(LuaState, VariantType);
      lua_pushstring(LuaState, "IDispatch value is NULL");
    }
    break;
  case VT_UNKNOWN:
    if (Variant->punkVal)
    {
      Variant->punkVal->lpVtbl->AddRef(Variant->punkVal);
      lua_pushlightuserdata(LuaState, Variant->punkVal);
      lua_pushinteger(LuaState, VariantType);
      lua_pushnil(LuaState);
    }
    else
    {
      lua_pushnil(LuaState);
      lua_pushinteger(LuaState, VariantType);
      lua_pushstring(LuaState, "IUnknown value is NULL");
    }
    break;
  default:
    /* If it's an array type (VT_ARRAY | base) return the SAFEARRAY* */
    if ((VariantType & VT_ARRAY) == VT_ARRAY)
    {
      if ((VariantType & VT_BYREF) == VT_BYREF)
      {
        Array = IF(Variant->pparray, *(Variant->pparray), NULL);
        lua_pushlightuserdata(LuaState, Array);
        lua_pushinteger(LuaState, VariantType);
        lua_pushnil(LuaState);
      }
      else
      {
        /* Take ownership of the SAFEARRAY pointer so VariantClear won't destroy it */
        Array = Variant->parray;
        /* Clear ownership on the VARIANT first so re-entrancy can't observe
         * the VARIANT still owning the SAFEARRAY while Lua receives the pointer. */
        Variant->parray = NULL;
        Variant->vt     = VT_EMPTY;
        lua_pushlightuserdata(LuaState, Array);
        lua_pushinteger(LuaState, VariantType);
        lua_pushnil(LuaState);
      }
    }
    else
    {
      lua_pushnil(LuaState);
      lua_pushinteger(LuaState, VariantType);
      /* Include the numeric VARIANT type in the error message */
      lua_pushfstring(LuaState, "Unsupported VARIANT type: %d (0x%x)", VariantType, VariantType); /* Error */
    }
    break;
  }

  return 3; /* Number of values pushed on the stack */
}

/*============================================================================*/
/* COM OBJECTS                                                                */
/*============================================================================*/

/* From the CLSID got from COM_NewClsid (as Lua string), return IDispatch* as
 * lightuserdata
 */
static int DISPATCH_Create (lua_State *LuaState)
{
  CLSID     *ClassId  = lua_touserdata(LuaState, 1);
  IDispatch *Dispatch = NULL;

  HRESULT Result = CoCreateInstance(
    ClassId,
    NULL,
    (CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER),
    &IID_IDispatch,
    (void **)&Dispatch);

  lua_pushinteger(LuaState, Result);
  lua_pushlightuserdata(LuaState, Dispatch);

  return 2; /* Number of values returned on the stack */
}

/* Not raw: high level function */
static int DISPATCH_GetType (lua_State *LuaState)
{
  IDispatch *Dispatch = lua_touserdata(LuaState, 1);
  ITypeInfo *TypeInfo;
  BSTR       NameUtf16;
  size_t     SizeInBytes;
  
  HRESULT Result = Dispatch->lpVtbl->GetTypeInfo(Dispatch,
                                                 0,
                                                 LOCALE_USER_DEFAULT,
                                                 &TypeInfo);

  if (FAILED(Result))
  {
    lua_pushnil(LuaState);
    lua_pushstring(LuaState, "Failed to get type info");
  }
  else
  {
    Result = TypeInfo->lpVtbl->GetDocumentation(TypeInfo,
                                                MEMBERID_NIL,
                                                &NameUtf16,
                                                NULL,
                                                NULL,
                                                NULL);
    
    TypeInfo->lpVtbl->Release(TypeInfo); /* GetTypeInfo */
    
    if (FAILED(Result))
    {
      lua_pushnil(LuaState);
      lua_pushstring(LuaState, "Failed to get documentation");
    }
    else
    {
      SizeInBytes = (SysStringLen(NameUtf16) * sizeof(wchar_t));
      lua_pushlstring(LuaState, (const char *)NameUtf16, SizeInBytes);
      lua_pushnil(LuaState);
      SysFreeString(NameUtf16); /* Allocated with GetDocumentation */
    }
  }

  return 2; /* Number of values returned on the stack */
}

/* Not raw: high level function */
static int DISPATCH_ListMembers (lua_State *LuaState)
{
  IDispatch *Dispatch = lua_touserdata(LuaState, 1);
  ITypeInfo *TypeInfo = NULL;
  TYPEATTR  *TypeAttr = NULL;
  FUNCDESC  *Function;
  UINT       cNames;
  HRESULT    Result;
  int        Offset;
  BSTR       NameUtf16;
  int        SizeInBytes;

  Result = Dispatch->lpVtbl->GetTypeInfo(Dispatch, 0, LOCALE_USER_DEFAULT, &TypeInfo);

  if (FAILED(Result))
  {
    lua_pushnil(LuaState);
  }
  else
  {
    Result = TypeInfo->lpVtbl->GetTypeAttr(TypeInfo, &TypeAttr);
    
    if (FAILED(Result))
    {
      TypeInfo->lpVtbl->Release(TypeInfo);
      lua_pushnil(LuaState);
    }
    else
    {
      lua_createtable(LuaState, TypeAttr->cFuncs, 0);
      
      for (Offset = 0; (Offset < TypeAttr->cFuncs); Offset++)
      {
        Function = NULL;
        Result   = TypeInfo->lpVtbl->GetFuncDesc(TypeInfo, Offset, &Function);
        if (SUCCEEDED(Result))
        {
          /* Collect the function name */
          NameUtf16 = NULL;
          Result    = TypeInfo->lpVtbl->GetNames(TypeInfo,
                                                 Function->memid,
                                                 &NameUtf16,
                                                 1,
                                                 &cNames);
          if (SUCCEEDED(Result))
          {
            SizeInBytes = (SysStringLen(NameUtf16) * sizeof(wchar_t));
            lua_pushinteger(LuaState, Function->memid); /* key: memid */
            lua_pushlstring(LuaState, (const char *)NameUtf16, SizeInBytes); /* value: name */
            lua_settable(LuaState, -3); /* table[memid] = name */
            SysFreeString(NameUtf16);
          }
          TypeInfo->lpVtbl->ReleaseFuncDesc(TypeInfo, Function); /* GetFuncDesc */
        }
      }
      
      TypeInfo->lpVtbl->ReleaseTypeAttr(TypeInfo, TypeAttr); /* GetTypeAttr */
      TypeInfo->lpVtbl->Release(TypeInfo); /* GetTypeInfo */
    }
  }
  
  return 1; /* Number of values returned on the stack */
}

/*
 * NameUtf16 must be null-terminated (2 bytes 0x00)
 */
static int DISPATCH_GetIdOfName (lua_State *LuaState)
{
  IDispatch *Dispatch  = lua_touserdata(LuaState, 1);
  OLECHAR   *NameUtf16 = (OLECHAR *)lua_tostring(LuaState, 2);
  DISPID     DispatchId;

  HRESULT Result = Dispatch->lpVtbl->GetIDsOfNames(Dispatch,
                                                   &IID_NULL,
                                                   &NameUtf16,
                                                   1,
                                                   LOCALE_USER_DEFAULT,
                                                   &DispatchId);
  
  lua_pushinteger(LuaState, Result);
  lua_pushinteger(LuaState, DispatchId);

  return 2; /* Number of values returned on the stack */
}

static int DISPATCH_Invoke (lua_State *LuaState)
{
  IDispatch  *Dispatch      = lua_touserdata(LuaState,    1);
  int         Flags         = luaL_checkinteger(LuaState, 2); /* DISPATCH_PROPERTY XXX*/
  DISPID      MemberId      = luaL_checkinteger(LuaState, 3);
  VARIANT    *VariantResult = lua_touserdata(LuaState,    4);
  VARIANT    *VariantParam  = lua_touserdata(LuaState,    5);
  int         ParamCount    = luaL_checkinteger(LuaState, 6);
  DISPPARAMS  Params;
  HRESULT     Result;
  DISPID      PutPropId;
  int         NamedArgsCount;
  DISPID     *NamedArgIds;

  if (Flags == DISPATCH_PROPERTYPUTREF)
  {
    Result = E_NOTIMPL; /* DISPATCH_PROPERTYPUTREF not supported */
  }
  else if (!((Flags == DISPATCH_METHOD)
             || (Flags == DISPATCH_PROPERTYGET)
             || (Flags == DISPATCH_PROPERTYPUT)))
  {
    Result = E_INVALIDARG; /* Invalid dispatch flag */
  }
  else
  {
    if (Flags == DISPATCH_PROPERTYPUT)
    {
      PutPropId      = DISPID_PROPERTYPUT;
      NamedArgIds    = &PutPropId;
      NamedArgsCount = 1;
    }
    else
    {
      NamedArgIds    = NULL;
      NamedArgsCount = 0;
    }

    /* Setup DISPPARAMS */
    Params.rgvarg            = VariantParam;
    Params.cArgs             = ParamCount;
    Params.rgdispidNamedArgs = NamedArgIds;
    Params.cNamedArgs        = NamedArgsCount;

    VariantInit(VariantResult);
    
    Result = Dispatch->lpVtbl->Invoke(
      Dispatch,
      MemberId,
      &IID_NULL,
      LOCALE_USER_DEFAULT,
      Flags,
      &Params,
      VariantResult,
      NULL,
      NULL
    );
  }

  lua_pushinteger(LuaState, Result);

  /* At this stage, VariantResult is owned by the Lua side. Lua code should call
   * the VARIANT_Clear */

  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* IEnumVARIANT INTERFACE FUNCTIONS                                           */
/*============================================================================*/

static int IEnumVARIANT_Clone (lua_State *LuaState)
{
  IEnumVARIANT *Enum      = lua_touserdata(LuaState, 1);
  IEnumVARIANT *EnumClone = NULL;
  HRESULT       Result    = Enum->lpVtbl->Clone(Enum, &EnumClone);

  lua_pushinteger(LuaState, Result);
  lua_pushlightuserdata(LuaState, EnumClone);

  return 2; /* Number of values returned on the stack */
}

static int IEnumVARIANT_Next (lua_State *LuaState)
{
  IEnumVARIANT *Enum         = lua_touserdata(LuaState, 1);
  ULONG         Count        = luaL_checkinteger(LuaState, 2);
  VARIANT      *VariantArray = lua_touserdata(LuaState, 3);
  ULONG         Fetched;

  HRESULT Result = Enum->lpVtbl->Next(Enum, Count, VariantArray, &Fetched);

  /* When there is no more data, Result will be S_FALSE which is a SUCCESS, the
   * returned Fetched value will be 0 */
  
  lua_pushinteger(LuaState, Result);
  lua_pushinteger(LuaState, Fetched);

  return 2; /* Number of values returned on the stack */
}

static int IEnumVARIANT_Reset (lua_State *LuaState)
{
  IEnumVARIANT *Enum   = lua_touserdata(LuaState, 1);
  HRESULT       Result = Enum->lpVtbl->Reset(Enum);
  
  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static int IEnumVARIANT_Skip (lua_State *LuaState)
{
  IEnumVARIANT *Enum   = lua_touserdata(LuaState, 1);
  ULONG         Count  = luaL_checkinteger(LuaState, 2);
  HRESULT       Result = Enum->lpVtbl->Skip(Enum, Count);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* SAFEARRAY                                                                  */
/*============================================================================*/

/* SafeArray will try to release resources when possible */

/* Create a SAFEARRAY with multiple dimensions using
 * SafeArrayCreate(elementVt, cDims, rgsabound)
 * New Lua signature (primitives only):
 *   safearray_create(elementVt, lbound1, count1, lbound2, count2, ...)
 * - The number of dimensions is inferred as (#args - 1) / 2
 * - dimensions must be >= 1 and <= 32
 * - there must be an even number of additional arguments after elementVt
 */
static int SAFEARRAY_Create (lua_State *LuaState)
{
  VARTYPE         ElementType = luaL_checkinteger(LuaState, 1);
  int             ArgCount    = lua_gettop(LuaState);
  int             PairCount   = (ArgCount - 1);
  int             DimensionCount;
  SAFEARRAYBOUND  Bounds[32];
  int             Offset;
  SAFEARRAY      *NewArray;

  /* Validate arguments: need at least one pair [lbound,count] */
  if ((PairCount < 2) || ((PairCount % 2) != 0))
  {
    lua_pushnil(LuaState);
  }
  else
  {
    DimensionCount = (PairCount / 2);

    if ((DimensionCount <= 0) || (DimensionCount > 32))
    {
      lua_pushnil(LuaState);
    }
    else
    {
      /* Set the lower bound and element count for each dimension */
      for (Offset = 0; (Offset < DimensionCount); Offset++)
      {
        Bounds[Offset].lLbound   = luaL_checkinteger(LuaState, 2 + (Offset * 2));
        Bounds[Offset].cElements = luaL_checkinteger(LuaState, 3 + (Offset * 2));
      }

      NewArray = SafeArrayCreate(ElementType, DimensionCount, Bounds);

      if (NewArray)
      {
        lua_pushlightuserdata(LuaState, NewArray);
      }
      else
      {
        lua_pushnil(LuaState);
      }
    }
  }

  return 1; /* Number of values returned on the stack */
}

static int SAFEARRAY_Destroy (lua_State *LuaState)
{
  SAFEARRAY *Array  = lua_touserdata(LuaState, 1);
  HRESULT    Result = SafeArrayDestroy(Array);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static int SAFEARRAY_GetVartype (lua_State *LuaState)
{
  SAFEARRAY *Array  = lua_touserdata(LuaState, 1);
  VARTYPE    Type   = VT_EMPTY;
  HRESULT    Result = SafeArrayGetVartype(Array, &Type);
  
  lua_pushinteger(LuaState, Result);
  lua_pushinteger(LuaState, Type);
  
  return 2; /* Number of values returned on the stack */
}

static int SAFEARRAY_GetElemSize (lua_State *LuaState)
{
  SAFEARRAY *SafeArray   = lua_touserdata(LuaState, 1);
  UINT       SizeInBytes = SafeArrayGetElemsize(SafeArray);
  
  lua_pushinteger(LuaState, SizeInBytes);
  
  return 1; /* Number of values returned on the stack */
}

static int SAFEARRAY_GetDim (lua_State *LuaState)
{
  SAFEARRAY *Array          = lua_touserdata(LuaState, 1);
  UINT       DimensionCount = SafeArrayGetDim(Array);

  lua_pushinteger(LuaState, DimensionCount);

  return 1; /* Number of values returned on the stack */
}

static int SAFEARRAY_GetLBound (lua_State *LuaState)
{
  SAFEARRAY *Array      = lua_touserdata(LuaState, 1);
  UINT       Dimension  = luaL_checkinteger(LuaState, 2);
  LONG       LowerBound = 0;
  HRESULT    Result     = SafeArrayGetLBound(Array, Dimension, &LowerBound);

  lua_pushinteger(LuaState, Result);
  lua_pushinteger(LuaState, LowerBound);

  return 2; /* Number of values returned on the stack */
}

static int SAFEARRAY_GetUBound (lua_State *LuaState)
{
  SAFEARRAY *Array      = lua_touserdata(LuaState, 1);
  UINT       Dimension  = luaL_checkinteger(LuaState, 2);
  LONG       UpperBound = 0;
  HRESULT    Result     = SafeArrayGetUBound(Array, Dimension, &UpperBound);

  lua_pushinteger(LuaState, Result);
  lua_pushinteger(LuaState, UpperBound);

  return 2; /* Number of values returned on the stack */
}

/* The underlying SafeArrayPutElement will call VARIANT_Clear and release
 * resources automatically
 */
static int SAFEARRAY_PutElement (lua_State *LuaState)
{
  SAFEARRAY  *Array          = lua_touserdata(LuaState, 1);
  int         ArgCount       = lua_gettop(LuaState);
  int         DimensionCount = SafeArrayGetDim(Array);
  int         ExpectedArgs   = (1 + DimensionCount + 1);
  LONG        Indices[32];
  VARIANT    *Value;
  HRESULT     Result;
  int         Offset;

  if (ArgCount != ExpectedArgs)
  {
    Result = E_INVALIDARG;
  }
  else
  {
    for (Offset = 0; (Offset < DimensionCount); Offset++)
    {
      Indices[Offset] = luaL_checkinteger(LuaState, (2 + Offset));
    }

    Value  = lua_touserdata(LuaState, (2 + DimensionCount));
    Result = SafeArrayPutElement(Array, Indices, Value);
  }

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static int SAFEARRAY_AccessData (lua_State *LuaState)
{
  SAFEARRAY *Array  = lua_touserdata(LuaState, 1);
  void      *Data   = NULL;
  HRESULT    Result = SafeArrayAccessData(Array, &Data);
  
  lua_pushinteger(LuaState, Result);
  lua_pushlightuserdata(LuaState, Data);

  return 2; /* Number of values returned on the stack */
}

static int SAFEARRAY_UnaccessData (lua_State *LuaState)
{
  SAFEARRAY *Array  = lua_touserdata(LuaState, 1);
  HRESULT    Result = SafeArrayUnaccessData(Array);

  lua_pushinteger(LuaState, Result);

  return 1; /* Number of values returned on the stack */
}

static void COM_PushVariantToLua (lua_State *LuaState, VARIANT *Variant)
{
  BSTR       VariantString;
  size_t     SizeInBytes;
  SAFEARRAY *Array;

  switch (Variant->vt)
  {
  case VT_EMPTY:
  case VT_NULL:
  case VT_VOID:
    lua_pushnil(LuaState);
    break;
  case VT_BOOL:
    COM_PushVariantBool(LuaState, Variant->boolVal);
    break;
  case VT_I4:
    lua_pushinteger(LuaState, Variant->lVal);
    break;
  case VT_I8:
    lua_pushinteger(LuaState, Variant->llVal);
    break;
  case VT_R4:
    lua_pushnumber (LuaState, Variant->fltVal);
    break;
  case VT_R8:
    lua_pushnumber (LuaState, Variant->dblVal);
    break;
  case VT_DATE:
    lua_pushnumber (LuaState, Variant->date);
    break;
  case VT_BSTR:
    VariantString = Variant->bstrVal;
    if (VariantString)
    {
      /* SysStringLen return number of characters, without terminator */
      SizeInBytes = (SysStringLen(VariantString) * sizeof(wchar_t));
      lua_pushlstring(LuaState, (const char *)VariantString, SizeInBytes);
    }
    else
    {
      lua_pushnil(LuaState);
    }
    break;
  case VT_DISPATCH:
    if (Variant->pdispVal)
    {
      Variant->pdispVal->lpVtbl->AddRef(Variant->pdispVal);
      lua_pushlightuserdata(LuaState, Variant->pdispVal);
    }
    else
    {
      lua_pushnil(LuaState);
    }
    break;
  case VT_UNKNOWN:
    if (Variant->punkVal)
    {
      Variant->punkVal->lpVtbl->AddRef(Variant->punkVal);
      lua_pushlightuserdata(LuaState, Variant->punkVal);
    }
    else
    {
      lua_pushnil(LuaState);
    }
    break;
  default:
    if ((Variant->vt & VT_ARRAY) == VT_ARRAY)
    {
      if ((Variant->vt & VT_BYREF) == VT_BYREF)
      {
        Array = IF(Variant->pparray, *(Variant->pparray), NULL);
        lua_pushlightuserdata(LuaState, Array);
      }
      else
      {
        /* Take ownership of the SAFEARRAY pointer so VariantClear won't destroy it */
        Array = Variant->parray;
        /* Clear ownership on the VARIANT first so re-entrancy can't observe
         * the VARIANT still owning the SAFEARRAY while Lua receives the pointer. */
        Variant->parray = NULL;
        Variant->vt     = VT_EMPTY;
        lua_pushlightuserdata(LuaState, Array);
      }
    }
    else
    {
      lua_pushnil(LuaState);
    }
    break;
  }
}

static void COM_PushToLua (lua_State *LuaState, void *Address, VARTYPE Type)
{
  VARIANT_BOOL  VariantBool;
  BSTR          VariantString;
  size_t        SizeInBytes;
  IDispatch    *Dispatch;
  IUnknown     *Unknown;
  
  switch (Type)
  {
  case VT_EMPTY:
  case VT_NULL:
  case VT_VOID:
    lua_pushnil(LuaState);
    break;
  case VT_I4:  lua_pushinteger(LuaState,               *(long *)Address); break;
  case VT_I8:  lua_pushinteger(LuaState,          *(long long *)Address); break;
  case VT_UI4: lua_pushinteger(LuaState,      *(unsigned long *)Address); break;
  case VT_UI8: lua_pushinteger(LuaState, *(unsigned long long *)Address); break;
  case VT_R4:  lua_pushnumber (LuaState,              *(float *)Address); break;
  case VT_R8:  lua_pushnumber (LuaState,             *(double *)Address); break;
  case VT_BOOL:
    VariantBool = *(VARIANT_BOOL *)Address;
    COM_PushVariantBool(LuaState, VariantBool);
    break;
  case VT_BSTR:
    VariantString = *(BSTR *)Address;
    if (VariantString)
    {
      /* SysStringLen return number of characters, without terminator */
      SizeInBytes = (SysStringLen(VariantString) * sizeof(OLECHAR));
      lua_pushlstring(LuaState, (const char *)VariantString, SizeInBytes);
    }
    else
    {
      lua_pushnil(LuaState);
    }
    break;
  case VT_DISPATCH:
    Dispatch = *(IDispatch **)Address;
    if (Dispatch)
    {
      Dispatch->lpVtbl->AddRef(Dispatch);
      lua_pushlightuserdata(LuaState, Dispatch);
    }
    else
    {
      lua_pushnil(LuaState);
    }
    break;
  case VT_UNKNOWN:
    Unknown = *(IUnknown **)Address;
    if (Unknown)
    {
      Unknown->lpVtbl->AddRef(Unknown);
      lua_pushlightuserdata(LuaState, Unknown);
    }
    else
    {
      lua_pushnil(LuaState);
    }
    break;
  case VT_VARIANT:
    COM_PushVariantToLua(LuaState, Address);
    break;
  default:
    lua_pushnil(LuaState);
    break;
  }
}

static void COM_CopyLuaToVariant (lua_State *LuaState,
                                  int        LuaIndex,
                                  VARIANT   *Variant)
{
  const int   LuaType = lua_type(LuaState, LuaIndex);
  int         IntegerValue;
  const char *Buffer;
  size_t      SizeInBytes;

  VariantClear(Variant);

  switch (LuaType)
  {
  case LUA_TNIL:
    Variant->vt = VT_NULL;
    break;
  case LUA_TBOOLEAN:
    Variant->vt      = VT_BOOL;
    Variant->boolVal = COM_LuaBoolToVariant(LuaState, LuaIndex);
    break;
  case LUA_TNUMBER:
    if (lua_isinteger(LuaState, LuaIndex))
    {
      IntegerValue = lua_tointeger(LuaState, LuaIndex);
      if ((IntegerValue >= LONG_MIN) && (IntegerValue <= LONG_MAX))
      {
        Variant->vt   = VT_I4;
        Variant->lVal = IntegerValue;
      }
      else
      {
        Variant->vt    = VT_I8; 
        Variant->llVal = IntegerValue;
      }
    }
    else
    {
      Variant->vt     = VT_R8;
      Variant->dblVal = lua_tonumber(LuaState, LuaIndex);
    }
    break;
  case LUA_TSTRING:
    Buffer = lua_tolstring(LuaState, LuaIndex, &SizeInBytes);
    if (Buffer)
    {
      VARIANT_SetString(Variant, (const wchar_t *)Buffer);
    }
    break;
  case LUA_TLIGHTUSERDATA:
    Variant->vt      = VT_UNKNOWN;
    Variant->punkVal = lua_touserdata(LuaState, LuaIndex);
    if (Variant->punkVal)
    {
      Variant->punkVal->lpVtbl->AddRef(Variant->punkVal);
    }
    break;
  default:
    Variant->vt = VT_NULL;
    break;
  }
}

static void COM_CopyLuaToAddress (lua_State *LuaState,
                                  int        LuaIndex,
                                  void      *Address,
                                  VARTYPE    VariantType)
{
  VARIANT_BOOL  *VariantBool;
  size_t         SizeInBytes;
  BSTR          *String;
  IUnknown     **pUnknown;
  IDispatch    **pDispatch;
  IUnknown      *Unknown;
  IDispatch     *Dispatch;
  OLECHAR       *WideBuffer;

  switch (VariantType)
  {
  case VT_I4:                *(long *)Address = lua_tointeger(LuaState, LuaIndex); break;
  case VT_UI4:      *(unsigned long *)Address = lua_tointeger(LuaState, LuaIndex); break;
  case VT_I8:           *(long long *)Address = lua_tointeger(LuaState, LuaIndex); break;
  case VT_UI8: *(unsigned long long *)Address = lua_tointeger(LuaState, LuaIndex); break;
  case VT_R4:               *(float *)Address = lua_tonumber(LuaState, LuaIndex);  break;
  case VT_R8:              *(double *)Address = lua_tonumber(LuaState, LuaIndex);  break;
  case VT_BOOL:
    VariantBool  = Address;
    *VariantBool = COM_LuaBoolToVariant(LuaState, LuaIndex);
    break;
  case VT_BSTR:
    /* Collect garbage */
    String = Address;
    if (*String)
    {
      SysFreeString(*String);
      *String = NULL;
    }
    /* Copy string: need a properly UTF-16 null-terminated string */
    WideBuffer = (OLECHAR *)lua_tolstring(LuaState, LuaIndex, &SizeInBytes);
    *String    = SysAllocString(WideBuffer);
    break;
  case VT_UNKNOWN:
    pUnknown = (IUnknown **)Address;
    if (*pUnknown)
    {
      (*pUnknown)->lpVtbl->Release(*pUnknown);
      *pUnknown = NULL;
    }
    Unknown  = lua_touserdata(LuaState, LuaIndex);
    if (Unknown)
    {
      Unknown->lpVtbl->AddRef(Unknown);
    }
    *pUnknown = Unknown;
    break;
  case VT_DISPATCH:
    pDispatch = (IDispatch **)Address;
    if (*pDispatch)
    {
      (*pDispatch)->lpVtbl->Release(*pDispatch);
      *pDispatch = NULL;
    }
    Dispatch = lua_touserdata(LuaState, LuaIndex);
    if (Dispatch)
    {
      Dispatch->lpVtbl->AddRef(Dispatch);
    }
    *pDispatch = Dispatch;
    break;
  case VT_VARIANT:
    COM_CopyLuaToVariant(LuaState, LuaIndex, Address);
    break;
  }
}

/* Very unsafe: need the caller to have a properly sized array */
static int SAFEARRAY_ReadData (lua_State *LuaState)
{
  SAFEARRAY *Array       = lua_touserdata(LuaState, 1);
  void      *DataPointer = lua_touserdata(LuaState, 2);
  int        TableIndex  = 3;
  VARTYPE    Type;
  HRESULT    Result;
  int        Index;
  int        Count;
  int        ReturnCount;
  char      *Element;
  size_t     ElementSizeInBytes;

  luaL_checktype(LuaState, 1, LUA_TLIGHTUSERDATA);
  luaL_checktype(LuaState, 2, LUA_TLIGHTUSERDATA);
  luaL_checktype(LuaState, TableIndex, LUA_TTABLE);

  Result = SafeArrayGetVartype(Array, &Type);

  if (SUCCEEDED(Result))
  {
    ElementSizeInBytes = SafeArrayGetElemsize(Array);
    Count              = lua_rawlen(LuaState, TableIndex);
    Element            = DataPointer;

    for (Index = 1; Index <= Count; Index++)
    {
      COM_PushToLua(LuaState, Element, Type);
      lua_seti(LuaState, TableIndex, Index);
      Element = (((char *)Element) + ElementSizeInBytes);
    }

    ReturnCount = Count;
  }
  else
  {
    ReturnCount = 0;
  }

  lua_pushinteger(LuaState, ReturnCount);
  
  return 1; /* Number of values returned on the stack */
}

/* NOTE: that function is absolutely unsafe, the responsability of the caller to
 * provide a properly sized array
 */
static int SAFEARRAY_WriteData (lua_State *LuaState)
{
  SAFEARRAY *Array       = lua_touserdata(LuaState, 1);
  void      *DataPointer = lua_touserdata(LuaState, 2);
  int        TableIndex  = 3;
  VARTYPE    Type;
  HRESULT    Result;
  int        Index;
  int        Count;
  char      *Element;
  size_t     ElementSizeInBytes;
  int        ReturnCount;

  luaL_checktype(LuaState, 1, LUA_TLIGHTUSERDATA);
  luaL_checktype(LuaState, 2, LUA_TLIGHTUSERDATA);
  luaL_checktype(LuaState, TableIndex, LUA_TTABLE);

  Result = SafeArrayGetVartype(Array, &Type);

  if (SUCCEEDED(Result))
  {
    ElementSizeInBytes = SafeArrayGetElemsize(Array);

    if (ElementSizeInBytes > 0)
    {
      Count   = lua_rawlen(LuaState, TableIndex);
      Element = DataPointer;

      for (Index = 1; Index <= Count; Index++)
      {
        lua_rawgeti(LuaState, TableIndex, Index);
        COM_CopyLuaToAddress(LuaState, -1, Element, Type);
        lua_pop(LuaState, 1);
        Element = (((char *)Element) + ElementSizeInBytes);
      }

      ReturnCount = Count;
    }
    else
    {
      ReturnCount = 0;
    }
  }
  else
  {
    ReturnCount = 0;
  }

  lua_pushinteger(LuaState, ReturnCount);

  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* PUBLIC INTERFACE                                                           */
/*============================================================================*/

static const struct luaL_Reg LWC_FUNCTIONS[] =
{
  /* COM Class ID management CLSID */
  { "newclsid",                COM_NewClsid             },
  { "newiid",                  COM_NewClsid             },
  { "clsidtostringutf16",      COM_ClsidToStringU16     },
  /* IUnknown interface */
  { "iunknown_addref",         IUNKNOWN_AddRef          },
  { "iunknown_release",        IUNKNOWN_Release         },
  { "iunknown_queryinterface", IUNKNOWN_QueryInterface  },
  /* VARIANT */
  { "variant_init",            VARIANT_Init             },
  { "variant_clear",           VARIANT_Clear            },
  { "variant_set",             VARIANT_Set              },
  { "variant_get",             VARIANT_Get              },
  { "variant_getsize",         VARIANT_GetSizeInBytes   },
  /* SAFEARRAY */
  { "safearray_create",        SAFEARRAY_Create         },
  { "safearray_destroy",       SAFEARRAY_Destroy        },
  { "safearray_getvartype",    SAFEARRAY_GetVartype     },
  { "safearray_getelemsize",   SAFEARRAY_GetElemSize    },
  { "safearray_getdim",        SAFEARRAY_GetDim         },
  { "safearray_getlbound",     SAFEARRAY_GetLBound      },
  { "safearray_getubound",     SAFEARRAY_GetUBound      },
  { "safearray_putelement",    SAFEARRAY_PutElement     },
  { "safearray_accessdata",    SAFEARRAY_AccessData     },
  { "safearray_unaccessdata",  SAFEARRAY_UnaccessData   },
  { "safearray_readdata",      SAFEARRAY_ReadData       },
  { "safearray_writedata",     SAFEARRAY_WriteData      },
  /* IDispatch interface */
  { "idispatch_create",        DISPATCH_Create          },
  { "idispatch_getidofname",   DISPATCH_GetIdOfName     },
  { "idispatch_invoke",        DISPATCH_Invoke          },
  { "idispatch_members",       DISPATCH_ListMembers     },
  { "idispatch_gettype",       DISPATCH_GetType         },
  /* IEnumVARIANT interface */
  { "enumvariant_clone",       IEnumVARIANT_Clone       },
  { "enumvariant_next",        IEnumVARIANT_Next        },
  { "enumvariant_reset",       IEnumVARIANT_Reset       },
  { "enumvariant_skip",        IEnumVARIANT_Skip        },
  {NULL, NULL}
};

int luaopen_wincom_raw (lua_State *LuaState)
{
  luaL_newlib(LuaState, LWC_FUNCTIONS);
  
  return 1; /* Number of values returned on the stack */
}
