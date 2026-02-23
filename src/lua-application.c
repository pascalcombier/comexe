/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua-application.c                                                 *
 * CONTENT  Implement a lightweight component-based application in Lua        *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

/*============================================================================*/
/* INFORMATION                                                                */
/*============================================================================*/

/* This is a multithread program, the main thread will create a dedicated thread
 * for each Lua state. It will be stored in struct LUA_Instance. It is crucial
 * that the address of these LUA_Instance objects don't change because they are
 * shared between main thread and lua_State (uv_thread_join).
 *
 * For that reason, LUA_Instance are not preallocated in groups, but instead
 * they are allocated one by one in a specific calloc in APP_CreateInstance.
 *
 * On x86-64, lua_tointeger return a lua_Integer which is typically a 64-bit
 * value, there is 1 bit for the sign, so max value would be 2^63.
 *
 * THREAD-MISUSE-DETECTION
 *
 * A thread can create multiple children threads. By design, when a thread
 * create children threads and then close, it will *not* wait for those children
 * threads to close. There are multiple reasons for that. The first one is that
 * it's recursive and seems not trivial to implement. But the most important
 * reason is that if the Lua developper forgot to close a child thread properly,
 * the program will be blocked in thread_join without ability to know where the
 * issue comes from. For these reasons, we choosed to simply DETECT this
 * situation when a thread is being close.
 *
 * EVENT SUPPORTED TYPES
 *
 * [X] LUA_TNIL
 * [X] LUA_TBOOLEAN
 * [X] LUA_TLIGHTUSERDATA
 * [X] LUA_TNUMBER
 * [X] LUA_TSTRING
 * [ ] LUA_TTABLE
 * [ ] LUA_TFUNCTION
 * [ ] LUA_TUSERDATA
 * [ ] LUA_TTHREAD
 *
 * STANDARD OUTPUT AND ERROR OUTPUT
 *
 * By design, this program don't print anything on the standard output. If a
 * critical problem is detected, it will print an error on the error stream and
 * exit.
 *
 * Exception is THREAD-MISUSE-DETECTION which is just a warning.
 *
 * MULTITHREAD
 *
 * LUA_RunEventLoop need to wait for 2 kind of things: events from other
 * LUA_Instance and state change from LUA_CloseEventLoop.
 *
 *
 * EMBEDDED VS SIMPLE MODE
 *
 * At some point, there were 2 modes of execution: embedded mode and simple
 * mode. The embedded was refering to the normal use case: the EXECUTABLE is
 * embedding Lua files, because this program is implemented in Lua the
 * parameters are copied verbatim from the Lua side to the C side.
 *
 * The second mode was a kind of failsafe mode, in case there is no embedded
 * file found, the program would take parameters which are a Lua script and its
 * parameters. To be a somehow compatible with lua54.exe interface requires to
 * handle negative index. This mean that index -1 correspond to the EXECUTABLE,
 * 0 correspond to the Lua script name and the rest of parameters are 1, 2,3
 * etc.
 * 
 * SIMPLE MODE was deleted because it was hiding problems.
 *
 * LOADER CONFIGURATION
 *
 * LoaderConfiguration aka package.searchers is a lua_State specific
 * configuration. And in the same time, it's pretty much a value that we want to
 * share amoung threads/instance. For that reasons it's stored in struct
 * LUA_Application.
 *
 * When the value of LoaderConfiguration change, it will only impact the current
 * threads and the threads that will be created later. The changes will not be
 * applied on other running threads.
 *
 * At some point, we tried to make the SetLoader update all the running threads
 * with the broadcast thing. It was a bad idea, it create a dependancy on event
 * loop to implement the notification.
 */

/*============================================================================*/
/* MAKEHEADERS PUBLIC INTERFACE                                               */
/*============================================================================*/

#if MKH_INTERFACE

/*---------*/
/* HEADERS */
/*---------*/

#include <stddef.h>  /* size_t */
#include <stdbool.h> /* bool   */

/* The external luaopen_XXX like luaopen_luv declarations require lua_State */
/* And they don't have a proper header */
#include <lua.h>

/*-------*/
/* TYPES */
/*-------*/

struct LUA_Application;

#endif

/*============================================================================*/
/* IMPLEMENTATION HEADERS                                                     */
/*============================================================================*/

#include <string.h>  /* memcpy */
#include <stdbool.h> /* bool   */
#include <time.h>    /* time   */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <uv.h>

#include "unzip.h" /* minizip headers */

#include "comexe.h"
#include "version.h"

#if !defined(WIN32)
#include <unistd.h>
#endif

/*============================================================================*/
/* PRIVATE CONSTANTS                                                          */
/*============================================================================*/

static const char *LUA_EMBEDDED_ENTRY_NAME = "comexe/init.lua";

#define APP_INITIAL_INSTANCE_CAPACITY 16

#define LUA_INSTANCE_PENDING_EVENT_COUNT 16
#define LUA_INSTANCE_PENDING_EVENT_SIZE  512

#define APP_BIT_SET(Value, Mask)                \
  do {                                          \
    Value = Value | (Mask);                     \
  } while (0)

#define APP_BIT_CLEAR(Value, Mask)               \
  do {                                           \
    Value = Value & ~(Mask);                     \
  } while (0)

/*============================================================================*/
/* PRIVATE TYPES                                                              */
/*============================================================================*/

#define INSTANCE_MASK_ACTIVE             ((uint8_t)(1 << 0))
#define INSTANCE_MASK_EVENTS_PENDING     ((uint8_t)(1 << 1))
#define INSTANCE_MASK_LOOP_CLOSE_REQUEST ((uint8_t)(1 << 2))

struct LUA_Instance
{
  const char             *ModuleName;
  struct LUA_Application *Application;
  const char             *ExitEventName;
  struct LUA_Instance    *Parent;
  size_t                  Offset;
  uv_thread_t             Thread;
  lua_State              *LuaState;
  uint8_t                 State;
  uv_mutex_t              StateMutex;
  uv_cond_t               StateCondition;
  struct BA_Allocator    *EventBufferReceive;
  struct BA_Allocator    *EventBufferTemp;
  uv_mutex_t              EventMutex;
  int                     EventHandlerRef;
  int                     WarningFunctionRef;
};

/* By design, we store struct LUA_Instance RootInstance as a statically
 * allocated structure. It avoid special cases, with that, even the main
 * instance has a parent.
 *
 * We do not create RootInstance with APP_CreateInstance, because it would
 * change the threads ID and start by 2 instead of the more natural 1, 2, 3 ...
 */
struct LUA_Application
{
  int32_t               Argc;
  const char          **Argv;
  struct LUA_Instance   RootInstance;
  struct TA_Array      *InstanceArray;
  uv_mutex_t            InstanceArrayMutex;
  uint8_t              *ComexeApi;
  size_t                ComexeApiSizeInBytes;
  char                  LoaderConfiguration[16];
};

typedef enum
{
  INSTANCE_EVENT_START,
  INSTANCE_EVENT_PARAM_INTEGER,
  INSTANCE_EVENT_PARAM_BOOLEAN,
  INSTANCE_EVENT_PARAM_DOUBLE,
  INSTANCE_EVENT_PARAM_STRING,
  INSTANCE_EVENT_PARAM_NIL,
  INSTANCE_EVENT_PARAM_USERDATA,
  INSTANCE_EVENT_END

} APP_EventType_t;

struct MAIN_Event
{
  APP_EventType_t Type;
  union
  {
    struct
    {
      int32_t ArgumentCount;
    } Start;

    struct
    {
      size_t  Length;
      char   *ValuePointer;
      char    Value[];
    } String;

    struct
    {
      int64_t Value;
    } Integer;

    struct
    {
      int32_t Value;
    } Boolean;

    struct
    {
      double Value;
    } Double;

    struct
    {
      void *Value;
    } UserData;

  } Data;
};

/*============================================================================*/
/* LUA-RELATED THINGS                                                         */
/*============================================================================*/

/* Those are not declared properly in any header */
extern int luaopen_luv         (lua_State *LuaState);
extern int luaopen_socket_core (lua_State *LuaState);
extern int luaopen_mime_core   (lua_State *LuaState);
extern int luaopen_mbedtls     (lua_State *LuaState);
extern int luaopen_libtcc      (lua_State *LuaState);

/*============================================================================*/
/* PRE-DECLARATIONS                                                           */
/*============================================================================*/

/* Pre-declaration of APP_CreateInstance is important, because it is used in LUA
 * API parts, before the definition of Instance-related functions (which are
 * actually using the LUA API) */

static struct LUA_Instance* APP_CreateInstance (struct LUA_Application *Application,
                                                struct LUA_Instance    *ParentInstance,
                                                const char             *ComponentName,
                                                const char             *ExitEventName);

static void APP_ReleaseInstance (struct LUA_Instance *Instance);

/*============================================================================*/
/* STANDARD LIBRARIES ADDONS                                                  */
/*============================================================================*/

static bool STRING_Equals (const char *String1, const char *String2)
{
  return (strcmp(String1, String2) == 0);
}

/*============================================================================*/
/* APPLICATION-RELATED LUA ADDONS                                             */
/*============================================================================*/

/* Preload implemented such as described in linit.c */
static void APP_RegisterPreload (lua_State     *LuaState,
                                 const char    *PreloadName,
                                 lua_CFunction  Function)
{
  luaL_getsubtable(LuaState, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  lua_pushcfunction(LuaState, Function);
  lua_setfield(LuaState, -2, PreloadName);
  lua_pop(LuaState, 1); /* LUA_PRELOAD_TABLE table */
}

/* Extraspace is a kind of non-standard UserData in the Lua API */
static void LUA_SetInstance (lua_State           *LuaState,
                             struct LUA_Instance *Instance)
{
  void **ExtraSpace = lua_getextraspace(LuaState);

  /* Update pointer */
  *ExtraSpace = Instance;
}

static struct LUA_Instance *LUA_GetInstance (lua_State *LuaState)
{
  void                **ExtraSpace = lua_getextraspace(LuaState);
  struct LUA_Instance  *Instance   = *ExtraSpace;
  
  return Instance;
}

/*============================================================================*/
/* THREAD API                                                                 */
/*============================================================================*/

/* NewThread(ComponentName, ExitEventName) */
static int LUA_NewThread (lua_State *LuaState)
{
  struct LUA_Instance    *Instance      = LUA_GetInstance(LuaState);
  struct LUA_Application *Application   = Instance->Application;
  int32_t                 ArgumentCount = lua_gettop(LuaState);
  const char             *ThreadEventName;
  const char             *ComponentName;
  size_t                  ComponentNameLength;
  struct LUA_Instance    *ChildInstance;

  if ((ArgumentCount >= 1) && (lua_isstring(LuaState, 1)))
  {
    ComponentName = lua_tolstring(LuaState, 1, &ComponentNameLength);

    if ((ArgumentCount >= 2) && lua_isstring(LuaState, 2))
    {
      ThreadEventName = lua_tostring(LuaState, 2);
    }
    else
    {
      ThreadEventName = NULL;
    }

    ChildInstance = APP_CreateInstance(Application, Instance, ComponentName, ThreadEventName);

    lua_pushinteger(LuaState, ChildInstance->Offset);
  }
  else
  {
    lua_pushnil(LuaState);
  }

  return 1; /* Number of values returned on the stack */
}

static int LUA_GetThreadId (lua_State *LuaState)
{
  struct LUA_Instance *Instance = LUA_GetInstance(LuaState);

  /* Push instance key on the stack */
  lua_pushinteger(LuaState, Instance->Offset);

  return 1; /* Number of values returned on the stack */
}

static int LUA_GetThreadModuleName (lua_State *LuaState)
{
  struct LUA_Instance *Instance = LUA_GetInstance(LuaState);

  /* Push module name on the stack */
  lua_pushstring(LuaState, Instance->ModuleName);

  return 1; /* Number of values returned on the stack */
}

static void LUA_WaitAndRelease (struct LUA_Application *Application,
                                struct LUA_Instance    *TargetInstance)
{
  /* Wait for thread execution */
  uv_thread_join(&TargetInstance->Thread);

  /* Remove from array */
  uv_mutex_lock(&Application->InstanceArrayMutex);
  TA_RemoveObject(Application->InstanceArray, TargetInstance->Offset);
  uv_mutex_unlock(&Application->InstanceArrayMutex);

  /* Release resources */
  APP_ReleaseInstance(TargetInstance);
}

static int LUA_JoinThread (lua_State *LuaState)
{
  struct LUA_Instance    *Instance      = LUA_GetInstance(LuaState);
  struct LUA_Application *Application   = Instance->Application;
  int32_t                 ArgumentCount = lua_gettop(LuaState);
  bool                    Success       = false;
  int64_t                 ThreadId;
  struct LUA_Instance    *TargetInstance;

  if ((ArgumentCount >= 1) && lua_isinteger(LuaState, 1))
  {
    ThreadId = lua_tointeger(LuaState, 1);

    uv_mutex_lock(&Application->InstanceArrayMutex);
    if (TA_IsValid(Application->InstanceArray, ThreadId))
    {
      TargetInstance = TA_GetObject(Application->InstanceArray, ThreadId);
    }
    else
    {
      TargetInstance = NULL;
    }
    uv_mutex_unlock(&Application->InstanceArrayMutex);

    if (TargetInstance)
    {
      LUA_WaitAndRelease(Application, TargetInstance);
      Success = true;
    }
  }

  lua_pushboolean(LuaState, Success);
  
  return 1; /* Number of values returned on the stack */
}

static const struct luaL_Reg THREADS_FUNCTIONS[] = 
{
  { "create",  LUA_NewThread           },
  { "getid",   LUA_GetThreadId         },
  { "getname", LUA_GetThreadModuleName },
  { "join",    LUA_JoinThread          },
  { NULL,      NULL                    }
};

static int luaopen_threads (lua_State *LuaState)
{
  luaL_newlib(LuaState, THREADS_FUNCTIONS);
  
  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* EVENTS API                                                                 */
/*============================================================================*/

static void APP_EnqueueEventArgument (struct BA_Allocator *EventQueue,
                                      struct MAIN_Event   *Event)
{
  size_t             Length;
  BA_Key_t           Key;
  uint8_t           *NewBlob;
  struct MAIN_Event *pEvent;
  
  if (Event->Type == INSTANCE_EVENT_PARAM_STRING)
  {
    Length = Event->Data.String.Length;

    BA_AllocateBlob(EventQueue, sizeof(struct MAIN_Event) + Length + 1, &Key, &NewBlob);

    pEvent                           = (struct MAIN_Event *)NewBlob;
    pEvent->Type                     = Event->Type;
    pEvent->Data.String.Length       = Length;
    pEvent->Data.String.ValuePointer = (char *)(NewBlob + sizeof(struct MAIN_Event));

    memcpy(pEvent->Data.String.Value, Event->Data.String.ValuePointer, Length + 1);
  }
  else
  {
    BA_PushBlob(EventQueue, Event, sizeof(struct MAIN_Event));
  }
}

static void APP_CopyEventArguments (lua_State           *LuaState,
                                    struct BA_Allocator *PendingEvents,
                                    uint32_t             StartIndex,
                                    uint32_t             EndIndex)
{
  struct MAIN_Event  Event;
  uint32_t           Index;
  int32_t            ValueType;
  const char        *EventString;
  size_t             EventStringLength;

  /* Enqueue event start */
  Event.Type                     = INSTANCE_EVENT_START;
  Event.Data.Start.ArgumentCount = (EndIndex - (StartIndex - 1));
  APP_EnqueueEventArgument(PendingEvents, &Event);

  for (Index = StartIndex; Index <= EndIndex; Index++)
  {
    ValueType = lua_type(LuaState, Index);

    switch (ValueType)
    {
    case LUA_TNUMBER:
      if (lua_isinteger(LuaState, Index))
      {
        Event.Type               = INSTANCE_EVENT_PARAM_INTEGER;
        Event.Data.Integer.Value = lua_tointeger(LuaState, Index);
      }
      else
      {
        Event.Type              = INSTANCE_EVENT_PARAM_DOUBLE;
        Event.Data.Double.Value = lua_tonumber(LuaState, Index);
      }
      APP_EnqueueEventArgument(PendingEvents, &Event);
      break;

    case LUA_TBOOLEAN:
      Event.Type               = INSTANCE_EVENT_PARAM_BOOLEAN;
      Event.Data.Boolean.Value = lua_toboolean(LuaState, Index);
      APP_EnqueueEventArgument(PendingEvents, &Event);
      break;

    case LUA_TSTRING:
      EventString                    = lua_tolstring(LuaState, Index, &EventStringLength);
      Event.Type                     = INSTANCE_EVENT_PARAM_STRING;
      Event.Data.String.Length       = EventStringLength;
      Event.Data.String.ValuePointer = (char *)EventString; /* Used temporarily */
      APP_EnqueueEventArgument(PendingEvents, &Event);
      break;

    case LUA_TLIGHTUSERDATA:
      Event.Type                = INSTANCE_EVENT_PARAM_USERDATA;
      Event.Data.UserData.Value = lua_touserdata(LuaState, Index);
      APP_EnqueueEventArgument(PendingEvents, &Event);
      break;

    case LUA_TNIL:
      Event.Type = INSTANCE_EVENT_PARAM_NIL;
      APP_EnqueueEventArgument(PendingEvents, &Event);
      break;

    default:
      fprintf(stderr,
              "ERROR: PostEvent param %d type is unsupported '%s'\n",
              Index,
              lua_typename(LuaState, ValueType));
      exit(2);
    }
  }

  /* Enqueue event end */
  Event.Type = INSTANCE_EVENT_END;
  APP_EnqueueEventArgument(PendingEvents, &Event);
}

static int LUA_PostEvent (lua_State *LuaState)
{
  uint32_t                ArgumentCount = lua_gettop(LuaState);
  struct LUA_Instance    *Instance      = LUA_GetInstance(LuaState);
  struct LUA_Application *Application   = Instance->Application;
  struct LUA_Instance    *TargetInstance;
  int64_t                 InstanceId;
  struct BA_Allocator    *PendingEvents;
  bool                    Success;

  if ((ArgumentCount >= 2) && (lua_isinteger(LuaState, 1)))
  {
    InstanceId = lua_tointeger(LuaState, 1);

    if (lua_type(LuaState, 2) != LUA_TSTRING)
    {
      luaL_error(LuaState, "PostEvent(EventName, ...): ERROR EventName must be a string");
    }
    else
    {
      uv_mutex_lock(&Application->InstanceArrayMutex);
      if (TA_IsValid(Application->InstanceArray, InstanceId))
      {
        TargetInstance = TA_GetObject(Application->InstanceArray, InstanceId);
      }
      else
      {
        TargetInstance = NULL;
      }
      uv_mutex_unlock(&Application->InstanceArrayMutex);
    }

    if (TargetInstance)
    {
      /* Enqueue the event */
      uv_mutex_lock(&TargetInstance->EventMutex);
      PendingEvents = TargetInstance->EventBufferReceive;
      APP_CopyEventArguments(LuaState, PendingEvents, 2, ArgumentCount);
      uv_mutex_unlock(&TargetInstance->EventMutex);

      /* Notify the event loop */
      uv_mutex_lock(&TargetInstance->StateMutex);
      APP_BIT_SET(TargetInstance->State, INSTANCE_MASK_EVENTS_PENDING);
      uv_cond_signal(&TargetInstance->StateCondition);
      uv_mutex_unlock(&TargetInstance->StateMutex);

      Success = true;
    }
    else
    {
      Success = false;
    }
  }
  else
  {
    Success = false;
  }

  /* Push success/failure result */
  lua_pushboolean(LuaState, Success);

  return 1; /* Number of values returned on the stack */
}

static int LUA_BroadcastEvent (lua_State *LuaState)
{
  uint32_t                ArgumentCount = lua_gettop(LuaState);
  struct LUA_Instance    *Instance      = LUA_GetInstance(LuaState);
  struct LUA_Application *Application   = Instance->Application;
  struct LUA_Instance    *TargetInstance;
  struct BA_Allocator    *PendingEvents;
  size_t                  InstanceCapacity;
  size_t                  InstanceOffset;
  bool                    Continue;

  if ((ArgumentCount >= 2) && (lua_isstring(LuaState, 2)))
  {
    InstanceOffset = 1;
    Continue       = true;

    while (Continue)
    {
      uv_mutex_lock(&Application->InstanceArrayMutex);
      InstanceCapacity = TA_GetCapacity(Application->InstanceArray);

      if (InstanceOffset <= InstanceCapacity)
      {
        if (TA_IsValid(Application->InstanceArray, InstanceOffset))
        {
          TargetInstance = TA_GetObject(Application->InstanceArray, InstanceOffset);

          if (TargetInstance)
          {
            uv_mutex_lock(&TargetInstance->EventMutex);
            PendingEvents = TargetInstance->EventBufferReceive;
            APP_CopyEventArguments(LuaState, PendingEvents, 2, ArgumentCount);
            uv_mutex_unlock(&TargetInstance->EventMutex);

            uv_mutex_lock(&TargetInstance->StateMutex);
            APP_BIT_SET(TargetInstance->State, INSTANCE_MASK_EVENTS_PENDING);
            uv_cond_signal(&TargetInstance->StateCondition);
            uv_mutex_unlock(&TargetInstance->StateMutex);
          }
        }
        InstanceOffset++;
      }
      else
      {
        Continue = false;
      }

      uv_mutex_unlock(&Application->InstanceArrayMutex);
    }
  }

  return 0; /* Number of values returned on the stack */
}

/* One could imagine that we could PostEvent an "ExitLoop" event to self but
 * this seems a bad idea. In LUA_RunEventLoop, we need an exit condition. This
 * exit condition is good to put the instance state. If we don't use that, we
 * would need an additional information such as ExitLoopProcessed, with
 * potentially another mutex/condition.
 */ 
static int LUA_CloseEventLoop (lua_State *LuaState)
{
  struct LUA_Instance *Instance = LUA_GetInstance(LuaState);

  uv_mutex_lock(&Instance->StateMutex);
  APP_BIT_SET(Instance->State, INSTANCE_MASK_LOOP_CLOSE_REQUEST);
  uv_cond_signal(&Instance->StateCondition);
  uv_mutex_unlock(&Instance->StateMutex);

  return 0; /* Number of values returned on the stack */
}

static size_t LUA_ProcessSingleEvent (lua_State           *LuaState,
                                      struct BA_Allocator *PendingEvents,
                                      uint32_t             TokenIndex,
                                      uint32_t             EventCount)
{
  size_t             TokenProcessed;
  struct MAIN_Event *Event;
  size_t             EventSizeInBytes;
  const char        *FunctionName;
  int32_t            ArgumentCount;
  bool               IsProcessing;
  int32_t            Status;

  /* Get argument count from START event */
  BA_GetBlob(PendingEvents, TokenIndex, (uint8_t **)&Event, &EventSizeInBytes);
  ArgumentCount = (Event->Data.Start.ArgumentCount - 1);
  TokenIndex++;

  /* Get function name */
  BA_GetBlob(PendingEvents, TokenIndex, (uint8_t **)&Event, &EventSizeInBytes);
  FunctionName = Event->Data.String.Value;
  TokenIndex++;

  TokenProcessed = 2;

  /* Get function */
  lua_getglobal(LuaState, FunctionName);

  if (lua_isnil(LuaState, -1))
  {
    lua_pop(LuaState, 1);  /* Pop the nil value */
    fprintf(stderr, "ERROR: function '%s' not found\n", FunctionName);
    exit(3);
  }

  IsProcessing = true;

  /* Process arguments */
  while (IsProcessing && (TokenIndex <= EventCount))
  {
    BA_GetBlob(PendingEvents, TokenIndex++, (uint8_t **)&Event, &EventSizeInBytes);
    TokenProcessed++;

    switch (Event->Type)
    {
    case INSTANCE_EVENT_PARAM_BOOLEAN:
      lua_pushboolean(LuaState, Event->Data.Boolean.Value);
      break;

    case INSTANCE_EVENT_PARAM_INTEGER:
      lua_pushinteger(LuaState, Event->Data.Integer.Value);
      break;

    case INSTANCE_EVENT_PARAM_DOUBLE:
      lua_pushnumber(LuaState, Event->Data.Double.Value);
      break;

    case INSTANCE_EVENT_PARAM_STRING:
      lua_pushlstring(LuaState, Event->Data.String.Value, Event->Data.String.Length);
      break;

    case INSTANCE_EVENT_PARAM_NIL:
      lua_pushnil(LuaState);
      break;

    case INSTANCE_EVENT_PARAM_USERDATA:
      lua_pushlightuserdata(LuaState, Event->Data.UserData.Value);
      break;

    case INSTANCE_EVENT_END:
      Status = lua_pcall(LuaState, ArgumentCount, 0, 0);
      if (Status != LUA_OK)
      {
        fprintf(stderr, "ERROR: Failed to call function '%s': %s\n",
                FunctionName, lua_tostring(LuaState, -1));
        lua_pop(LuaState, 1);  /* Pop the error message */
      }
      IsProcessing = false;
      break;

    default:
      fprintf(stderr, "ERROR: Unknown event type %d\n", Event->Type);
      exit(4);
      break;
    }
  }

  return TokenProcessed;
}

static void LUA_ProcessEventsIfNeeded (lua_State           *LuaState,
                                       struct LUA_Instance *Instance)
{
 struct BA_Allocator *PendingEvents;
 uint32_t             TokenCount;
 uint32_t             TokenIndex;
 uint32_t             ProcessedTokens;

  uv_mutex_lock(&Instance->EventMutex);
  TokenCount = BA_GetCount(Instance->EventBufferReceive);

  if (TokenCount == 0)
  {
    uv_mutex_unlock(&Instance->EventMutex);
  }
  else
  {
    /* Swap buffers and unlock */
    PendingEvents = Instance->EventBufferReceive;
    Instance->EventBufferReceive = Instance->EventBufferTemp;
    Instance->EventBufferTemp    = PendingEvents;

    /* Update state */
    uv_mutex_lock(&Instance->StateMutex);
    APP_BIT_CLEAR(Instance->State, INSTANCE_MASK_EVENTS_PENDING);
    uv_mutex_unlock(&Instance->StateMutex);

    /* Unlock event */
    uv_mutex_unlock(&Instance->EventMutex);

    /* Process events */
    TokenIndex = 1;

    /* During the processing, events can still be enqueued */
    while (TokenIndex <= TokenCount)
    {
      ProcessedTokens = LUA_ProcessSingleEvent(LuaState, PendingEvents, TokenIndex, TokenCount);
      TokenIndex += ProcessedTokens;
    }

    BA_Reset(PendingEvents);
  }
}

static int LUA_ProcessEvents (lua_State *LuaState)
{
  struct LUA_Instance *Instance = LUA_GetInstance(LuaState);

  LUA_ProcessEventsIfNeeded(LuaState, Instance);

  return 0; /* Number of values returned on the stack */
}

static int LUA_RunEventLoop (lua_State *LuaState)
{
  struct LUA_Instance *Instance = LUA_GetInstance(LuaState);
  bool                 Continue = true;
  
  const uint32_t MASK_STOP = (INSTANCE_MASK_EVENTS_PENDING | INSTANCE_MASK_LOOP_CLOSE_REQUEST);
  
  while (Continue)
  {
    LUA_ProcessEventsIfNeeded(LuaState, Instance);

    uv_mutex_lock(&Instance->StateMutex);
    while ((Instance->State & MASK_STOP) == 0)
    {
      uv_cond_wait(&Instance->StateCondition, &Instance->StateMutex);
    }
    Continue = ((Instance->State & INSTANCE_MASK_LOOP_CLOSE_REQUEST) == 0);
    uv_mutex_unlock(&Instance->StateMutex);
  }

  return 0; /* Number of values returned on the stack */
}

/* API will be reworked at runtime by init.lua */
static const struct luaL_Reg EVENTS_FUNCTIONS[] =
{
  { "runloop",   LUA_RunEventLoop   },
  { "stoploop",  LUA_CloseEventLoop },
  { "runonce",   LUA_ProcessEvents  },
  { "send",      LUA_PostEvent      },
  { "broadcast", LUA_BroadcastEvent },
  { NULL,        NULL               }
};

static int luaopen_events (lua_State *LuaState)
{
  luaL_newlib(LuaState, EVENTS_FUNCTIONS);
  
  return 1; /* Number of values returned on the stack */
}

/*============================================================================*/
/* RUNTIME API                                                                */
/*============================================================================*/

static int LUA_GetLoaderConfiguration (lua_State *LuaState)
{
  struct LUA_Instance    *Instance    = LUA_GetInstance(LuaState);
  struct LUA_Application *Application = Instance->Application;

  lua_pushstring(LuaState, (const char *)Application->LoaderConfiguration);

  return 1; /* Number of values returned on the stack */
}

static void APP_WarningCallback (void *ud, const char *msg, int tocont) 
{
  struct LUA_Instance *Instance = (struct LUA_Instance *)ud;
  lua_State           *LuaState = Instance->LuaState;
  int                  LuaType;
  const char          *ErrorMessage;
    
  /* Get the stored Lua warning function */
  if (Instance->WarningFunctionRef != LUA_REFNIL)
  {
    LuaType = lua_rawgeti(LuaState, LUA_REGISTRYINDEX, Instance->WarningFunctionRef);
    
    if (LuaType == LUA_TFUNCTION)
    {
      lua_pushstring(LuaState, msg);
      lua_pushboolean(LuaState, tocont);
      
      /* Call the Lua warning function */
      if (lua_pcall(LuaState, 2, 0, 0) != LUA_OK)
      {
        ErrorMessage = lua_tostring(LuaState, -1);
        fprintf(stderr, "Error in warning callback: %s\n", ErrorMessage);
        lua_pop(LuaState, 1); /* pop error message */
      }
    }
    else
    {
      fprintf(stderr, "Warning is not a function\n");
      /* Pop the invalid value */
      lua_pop(LuaState, 1);
    }
  }
}

static int LUA_SetLoaderConfiguration (lua_State *LuaState)
{
  size_t StringLength;
  
  struct LUA_Instance    *Instance     = LUA_GetInstance(LuaState);
  struct LUA_Application *Application  = Instance->Application;
  size_t                  MaxLength    = (sizeof(Application->LoaderConfiguration) - 1);
  const char             *ConfigString = luaL_checklstring(LuaState, 1, &StringLength);

  if (StringLength > MaxLength)
  {
    luaL_error(LuaState, "LoaderConfiguration must max %zu characters", MaxLength);
  }

  memcpy(Application->LoaderConfiguration, ConfigString, StringLength);
  Application->LoaderConfiguration[StringLength] = '\0';

  return 0; /* Number of values returned on the stack */
}

static int LUA_SetWarningFunction (lua_State *LuaState)
{
  struct LUA_Instance *Instance = LUA_GetInstance(LuaState);

  /* Remove previous warning function reference if it exists */
  if (Instance->WarningFunctionRef != LUA_REFNIL)
  {
    luaL_unref(LuaState, LUA_REGISTRYINDEX, Instance->WarningFunctionRef);
    Instance->WarningFunctionRef = LUA_REFNIL;
  }
  
  lua_setwarnf(LuaState, NULL, NULL);

  /* Set new warning function if provided */
  if (lua_isfunction(LuaState, 1))
  {
    lua_pushvalue(LuaState, 1); /* copy of the function for luaL_ref */
    Instance->WarningFunctionRef = luaL_ref(LuaState, LUA_REGISTRYINDEX);
    lua_setwarnf(LuaState, APP_WarningCallback, Instance);
  }

  return 0; /* Number of values returned on the stack */
}

static int LUA_SetEventHandler (lua_State *LuaState)
{
  struct LUA_Instance *Instance = LUA_GetInstance(LuaState);

  if (Instance->EventHandlerRef != LUA_REFNIL)
  {
    luaL_error(LuaState, "EventHandler already set");
  }

  if (!lua_isfunction(LuaState, 1))
  {
    luaL_error(LuaState, "seteventhandler expects a function");
  }

  lua_pushvalue(LuaState, 1); /* copy of the function for luaL_ref */
  Instance->EventHandlerRef = luaL_ref(LuaState, LUA_REGISTRYINDEX);

  return 0; /* Number of values returned on the stack */
}

/* For lua-libtcc.c */
bool LUA_PushEventHandler (lua_State *LuaState)
{
  struct LUA_Instance *Instance = LUA_GetInstance(LuaState);
  int                  LuaType;
  bool                 Success;

  if (Instance->EventHandlerRef != LUA_REFNIL)
  {
    LuaType = lua_rawgeti(LuaState, LUA_REGISTRYINDEX, Instance->EventHandlerRef);
    if (LuaType == LUA_TFUNCTION)
    {
      Success = true;
    }
    else
    {
      lua_pop(LuaState, 1);
      Success = false;
    }
  }
  else
  {
    Success = false;
  }

  return Success;
}

static int LUA_IsAtty (lua_State *LuaState)
{
  int32_t File = luaL_checkinteger(LuaState, 1);
  
  lua_pushboolean(LuaState, PLAT_IsAtty(File));

  return 1; /* Number of values returned on the stack */
}

static int LUA_Ref (lua_State *LuaState)
{
  int Reference;

  luaL_checkany(LuaState, 1);
  lua_pushvalue(LuaState, 1);
  Reference = luaL_ref(LuaState, LUA_REGISTRYINDEX);
  lua_pushinteger(LuaState, Reference);

  return 1; /* Number of values returned on the stack */
}

static int LUA_Unref (lua_State *LuaState)
{
  int Reference = luaL_checkinteger(LuaState, 1);

  luaL_unref(LuaState, LUA_REGISTRYINDEX, Reference);

  return 0; /* Number of values returned on the stack */
}

static const struct luaL_Reg COMRUNTIME_FUNCTIONS[] = 
{
  { "getloaderconfiguration", LUA_GetLoaderConfiguration },
  { "setloaderconfiguration", LUA_SetLoaderConfiguration },
  { "setwarningfunction",     LUA_SetWarningFunction     },
  { "seteventhandler",        LUA_SetEventHandler        },
  { "isatty",                 LUA_IsAtty                 },
  { "ref",                    LUA_Ref                    },
  { "unref",                  LUA_Unref                  },
  { NULL, NULL }
};

static int luaopen_runtime (lua_State *LuaState)
{
  /* Create function table */
  lua_createtable(LuaState, 0, 16); /* State, Array, Keys */

  /* Register functions */
  luaL_setfuncs(LuaState, COMRUNTIME_FUNCTIONS, 0);
  
  /* Register standard file descriptors */
  lua_pushinteger(LuaState, STDIN_FILENO);
  lua_setfield(LuaState, -2, "stdin");
  lua_pushinteger(LuaState, STDOUT_FILENO); 
  lua_setfield(LuaState, -2, "stdout");
  lua_pushinteger(LuaState, STDERR_FILENO);
  lua_setfield(LuaState, -2, "stderr");

  /* Other constants */

  lua_pushstring(LuaState, LUA_VERSION_MAJOR
                           "." LUA_VERSION_MINOR
                           "." LUA_VERSION_RELEASE);
  lua_setfield(LuaState, -2, "LUA_VERSION");

  lua_pushstring(LuaState, COMEXE_COMMIT);
  lua_setfield(LuaState, -2, "COMEXE_COMMIT");

  lua_pushstring(LuaState, COMEXE_BUILD_DATE);
  lua_setfield(LuaState, -2, "COMEXE_BUILD_DATE");

  lua_pushstring(LuaState, COMEXE_VERSION);
  lua_setfield(LuaState, -2, "COMEXE_VERSION");

  return 1; /* Number of values returned on the stack */
}

static void APP_PreloadLibraries (lua_State *LuaState)
{
  APP_RegisterPreload(LuaState, "com.raw.runtime",       luaopen_runtime);
  APP_RegisterPreload(LuaState, "com.thread",            luaopen_threads);
  APP_RegisterPreload(LuaState, "com.event",             luaopen_events);
  APP_RegisterPreload(LuaState, "com.raw.buffer",        luaopen_buffer);
  APP_RegisterPreload(LuaState, "com.raw.minizip",       luaopen_libminizip);
  APP_RegisterPreload(LuaState, "com.raw.libffi",        luaopen_libffiraw);
  APP_RegisterPreload(LuaState, "com.raw.libtcc",        luaopen_libtcc);
  APP_RegisterPreload(LuaState, "luv",                   luaopen_luv);
  APP_RegisterPreload(LuaState, "socket.core",           luaopen_socket_core);
  APP_RegisterPreload(LuaState, "mime.core",             luaopen_mime_core);
  APP_RegisterPreload(LuaState, "mbedtls",               luaopen_mbedtls);

#ifdef _WIN32
  APP_RegisterPreload(LuaState, "com.raw.win32",         luaopen_win32);
  APP_RegisterPreload(LuaState, "com.raw.win32.com",     luaopen_wincom_raw);
  APP_RegisterPreload(LuaState, "com.raw.win32.service", luaopen_service);
#endif

  /* Some package might leave some things on the stack */
  lua_settop(LuaState, 0);
}

static bool APP_LoadComexeApi (lua_State *LuaState, struct LUA_Application *Application)
{
  bool Success;
  
  if (luaL_loadbuffer(LuaState, 
                      (const char *)Application->ComexeApi,
                      Application->ComexeApiSizeInBytes,
                      LUA_EMBEDDED_ENTRY_NAME) != LUA_OK)
  {
    fprintf(stderr, "ERROR: Failed to load ComexeApi: %s\n", lua_tostring(LuaState, -1));
    lua_pop(LuaState, 1);
    Success = false;
  }
  else if (lua_pcall(LuaState, 0, 0, 0) != LUA_OK)
  {
    fprintf(stderr, "ERROR: Failed to run ComexeApi: %s\n", lua_tostring(LuaState, -1));
    lua_pop(LuaState, 1);
    Success = false;
  }
  else
  {
    Success = true;
  }

  return Success;
}

/*============================================================================*/
/* LUA INSTANCE                                                               */
/*============================================================================*/

static void APP_PrintThreadHierarchy (struct LUA_Application *Application,
                                      struct LUA_Instance    *Instance,
                                      int32_t                 Level)
{
  char                 Indent[256] = "";
  int32_t              Index;
  size_t               InstanceCapacity;
  size_t               InstanceOffset;
  struct LUA_Instance *ChildInstance;

  /* Create indentation with tree branches */
  if (Level == 0)
  {
    strcat(Indent, "* ");
  }
  else
  {
    strcat(Indent, "|");
    for (Index = 1; Index < Level; Index++)
    {
      strcat(Indent, "   |");
    }
    strcat(Indent, "---");
  }

  /* Print current instance info */
  printf("%s[%s] ThreadId=%zu\n", Indent, Instance->ModuleName, Instance->Offset);

  /* Recursively print children */
  InstanceCapacity = TA_GetCapacity(Application->InstanceArray);
  for (InstanceOffset = 1; InstanceOffset <= InstanceCapacity; InstanceOffset++)
  {
    if (TA_IsValid(Application->InstanceArray, InstanceOffset))
    {
      ChildInstance = TA_GetObject(Application->InstanceArray, InstanceOffset);
      if ((ChildInstance != Instance) && (ChildInstance->Parent == Instance))
      {
        APP_PrintThreadHierarchy(Application, ChildInstance, Level + 1);
      }
    }
  }
}

static void APP_SendExitEventToParent (struct LUA_Instance *Instance)
{
  struct LUA_Instance *ParentInstance = Instance->Parent;
  struct MAIN_Event    Event;
  struct BA_Allocator *PendingEvents;
  BA_Key_t             NewEventKey;
  size_t               EventNameLength;
  uint8_t             *NewEventData;
  struct MAIN_Event   *pEvent;

  /* Lock parent's event mutex for event operations */
  uv_mutex_lock(&ParentInstance->EventMutex);
    
  PendingEvents   = ParentInstance->EventBufferReceive;
  EventNameLength = strlen(Instance->ExitEventName);

  /* Send normal function call event first */
  Event.Type                     = INSTANCE_EVENT_START;
  Event.Data.Start.ArgumentCount = 2; /* EventName + InstanceId */
  BA_PushBlob(PendingEvents, &Event, sizeof(Event));

  /* Send EventName */
  Event.Type               = INSTANCE_EVENT_PARAM_STRING;
  Event.Data.String.Length = EventNameLength;
  BA_AllocateBlob(PendingEvents,
                  sizeof(struct MAIN_Event) + EventNameLength + 1,
                  &NewEventKey,
                  &NewEventData);

  /* Copy event structure and string data */
  pEvent = (struct MAIN_Event *)NewEventData;
  memcpy(pEvent, &Event, sizeof(struct MAIN_Event));
  memcpy(pEvent->Data.String.Value, Instance->ExitEventName, EventNameLength + 1);

  /* Send Instance ID */
  Event.Type = INSTANCE_EVENT_PARAM_INTEGER;
  Event.Data.Integer.Value = Instance->Offset;
  BA_PushBlob(PendingEvents, &Event, sizeof(Event));

  /* Send END event */
  Event.Type = INSTANCE_EVENT_END;
  BA_PushBlob(PendingEvents, &Event, sizeof(Event));

  uv_mutex_unlock(&ParentInstance->EventMutex);

  /* Wake up thread */
  uv_mutex_lock(&ParentInstance->StateMutex);
  APP_BIT_SET(ParentInstance->State, INSTANCE_MASK_EVENTS_PENDING);
  uv_cond_signal(&ParentInstance->StateCondition);
  uv_mutex_unlock(&ParentInstance->StateMutex);
}

/* Set positive arguments: arg[1], arg[2], ... */
static void APP_CreateArguments (lua_State   *LuaState,
                                 int32_t      ArgCount,
                                 const char **Argv)
{
  int32_t Offset;

  /* Create argument table */
  lua_createtable(LuaState, ArgCount, 0); /* State, Array, Keys */

  for (Offset = 0; Offset < ArgCount; Offset++)
  {
    lua_pushinteger(LuaState, (Offset + 1));
    lua_pushstring(LuaState, Argv[Offset]);
    lua_settable(LuaState, -3);
  }
  
  /* Override in the Lua standard "arg" variable */
  lua_setglobal(LuaState, "arg");
}

static void LUA_LuaThread (void *UserData)
{
  struct LUA_Instance    *Instance    = UserData;
  struct LUA_Application *Application = Instance->Application;
  lua_State              *LuaState    = Instance->LuaState;

  PLAT_ThreadInitalize();
  
  /* Unblock APP_CreateInstance using StateMutex/StateCondition */
  uv_mutex_lock(&Instance->StateMutex);
  APP_BIT_SET(Instance->State, INSTANCE_MASK_ACTIVE);
  uv_cond_signal(&Instance->StateCondition);
  uv_mutex_unlock(&Instance->StateMutex);

  /* Register Lua functions */
  APP_CreateArguments(LuaState, Application->Argc, Application->Argv);
  luaL_openlibs(LuaState); /* same as Lua 54/55 interpreter */
  APP_PreloadLibraries(LuaState);

  /* Load Lua API from ZIP */
  if (!((Application->ComexeApiSizeInBytes > 0)
        && APP_LoadComexeApi(LuaState, Application)))
  {
    fprintf(stderr, "ERROR: Failed to load ComEXE (%s)\n", LUA_EMBEDDED_ENTRY_NAME);
    exit(5);
  }
  
  /* Notify the parent event loop */
  if (Instance->ExitEventName)
  {
    APP_SendExitEventToParent(Instance);
  }

  PLAT_ThreadDeinitialize();
}

static void *APP_LuaAllocator (void* ud, void* ptr, size_t osize, size_t nsize)
{
  (void)ud;    /* unused parameter */
  (void)osize; /* unused parameter */

  if (nsize == 0)
  {
    PLAT_Free(ptr);
    return NULL;
  }
  else
  {
    return PLAT_SafeRealloc(ptr, nsize);
  }
}

static struct LUA_Instance *APP_CreateInstance (struct LUA_Application *Application,
                                                struct LUA_Instance    *ParentInstance,
                                                const char             *ComponentName,
                                                const char             *ExitEventName)
{
  struct LUA_Instance *NewInstance = PLAT_SafeAlloc0(1, sizeof(struct LUA_Instance));
  size_t               InstanceOffset;
  unsigned int         Seed;

  /* Update application */
  uv_mutex_lock(&Application->InstanceArrayMutex);
  InstanceOffset = TA_AddObject(Application->InstanceArray, NewInstance);
  uv_mutex_unlock(&Application->InstanceArrayMutex);

  /* Set new instance */
  NewInstance->Application = Application;
  NewInstance->Offset      = InstanceOffset;
  NewInstance->State       = 0;
  NewInstance->ModuleName  = PLAT_StrDup(ComponentName);

  if (ExitEventName)
  {
    NewInstance->ExitEventName = PLAT_StrDup(ExitEventName);
  } 
  else
  {
    NewInstance->ExitEventName = NULL;
  }

  Seed = luaL_makeseed(NULL);

  NewInstance->LuaState           = lua_newstate(APP_LuaAllocator, NULL, Seed);
  NewInstance->Parent             = ParentInstance;
  NewInstance->EventHandlerRef    = LUA_REFNIL;
  NewInstance->WarningFunctionRef = LUA_REFNIL;

  /* Stop GC while building state, like lua.c, will be restarted in init.lua */
  lua_gc(NewInstance->LuaState, LUA_GCSTOP);

  NewInstance->EventBufferReceive = BA_NewAllocator(LUA_INSTANCE_PENDING_EVENT_COUNT,
                                                    LUA_INSTANCE_PENDING_EVENT_SIZE);

  NewInstance->EventBufferTemp = BA_NewAllocator(LUA_INSTANCE_PENDING_EVENT_COUNT,
                                                 LUA_INSTANCE_PENDING_EVENT_SIZE);

  /* Attach important references to the LuaState */
  LUA_SetInstance(NewInstance->LuaState, NewInstance);

  uv_mutex_init(&NewInstance->StateMutex);
  uv_cond_init(&NewInstance->StateCondition);
  uv_mutex_init(&NewInstance->EventMutex);

  /* Start thread */
  uv_thread_create(&NewInstance->Thread, LUA_LuaThread, NewInstance);

  /* Blocking wait to ensure Instance->State is valid, before returning the
   * new instance */
  uv_mutex_lock(&NewInstance->StateMutex);
  while ((NewInstance->State & INSTANCE_MASK_ACTIVE) == 0)
  {
    uv_cond_wait(&NewInstance->StateCondition, &NewInstance->StateMutex);
  }
  uv_mutex_unlock(&NewInstance->StateMutex);

  return NewInstance;
}

static void APP_ReleaseInstance (struct LUA_Instance *Instance)
{
  uv_mutex_destroy(&Instance->StateMutex);
  uv_cond_destroy(&Instance->StateCondition);
  uv_mutex_destroy(&Instance->EventMutex);

  BA_FreeAllocator(Instance->EventBufferReceive);
  BA_FreeAllocator(Instance->EventBufferTemp);
  Instance->EventBufferReceive = NULL;
  Instance->EventBufferTemp    = NULL;

  lua_close(Instance->LuaState);

  /* Free the duplicated strings */
  PLAT_Free((void *)Instance->ModuleName);    /* Discard const */
  PLAT_Free((void *)Instance->ExitEventName); /* Discard const */

  PLAT_Free(Instance);
}

static uint8_t *APP_LoadEmbeddedFile (struct LUA_Application *Application,
                                      const char             *ZipEntryName,
                                      size_t                 *FileSize)
{
  const char      *ExeFilename = Application->Argv[0];
  unzFile          UnzFile     = unzOpen64(ExeFilename);
  char             CurrentFilename[256]; /* UNZ_MAXFILENAMEINZIP */
  bool             FileFound;
  uint8_t         *FileBuffer;
  unz_file_info64  FileInfo;
  size_t           BytesRead;
  int              Result;
  
  /* Initialize output  */
  FileBuffer = 0;

  if (UnzFile)
  {
    Result    = unzGoToFirstFile(UnzFile);
    FileFound = false;

    while (!FileFound && (Result == UNZ_OK))
    {
      /* Get current file info */
      if (unzGetCurrentFileInfo64(UnzFile,
                                  &FileInfo,
                                  CurrentFilename, 
                                  sizeof(CurrentFilename),
                                  NULL,
                                  0,
                                  NULL,
                                  0) == UNZ_OK)
      {
        if (STRING_Equals(CurrentFilename, ZipEntryName))
        {
          /* Found the requested file */
          if (unzOpenCurrentFile(UnzFile) == UNZ_OK)
          {
            /* Read file content */
            FileBuffer = PLAT_SafeAlloc0(1, FileInfo.uncompressed_size);
            BytesRead  = unzReadCurrentFile(UnzFile, FileBuffer, (unsigned int)FileInfo.uncompressed_size);

            if (BytesRead > 0)
            {
              *FileSize = BytesRead;
              FileFound = true;
            }
            else
            {
              /* Failed to read, cleanup */
              PLAT_Free(FileBuffer);
              FileBuffer = NULL;
            }
            
            unzCloseCurrentFile(UnzFile);
          }
        }
      }
      
      if (!FileFound)
      {
        Result = unzGoToNextFile(UnzFile);
      }
    }
    
    unzClose(UnzFile);
  }
  
  return FileBuffer;
}

extern struct LUA_Application *LUA_CreateApplication (size_t Argc, const char **Argv)
{
  struct LUA_Application *NewApplication = PLAT_SafeAlloc0(1, sizeof(struct LUA_Application));

  /* Store arguments for future instance creation */
  NewApplication->Argc = Argc;
  NewApplication->Argv = Argv;

  /* Set the default Searchers: PRELOAD, ZIP-RUNTIME, ZIP-ROOT
   * LoaderConfiguration string is used to implement the LOADER in
   * comexe/init.lua */
  strcpy(NewApplication->LoaderConfiguration, "1RZ");

  /* Load API from file embedded in ZIP */
  NewApplication->ComexeApi = APP_LoadEmbeddedFile(NewApplication,
                                                   LUA_EMBEDDED_ENTRY_NAME,
                                                   &NewApplication->ComexeApiSizeInBytes);

  /* Regardless the result, we start the thread for this instance, the choice
   * between STANDARD or SIMPLE mode will be done later */
  
  /* Initialize thread synchronization */
  uv_mutex_init(&NewApplication->InstanceArrayMutex);

  /* Initialize instance array */
  NewApplication->InstanceArray = TA_CreateArray(APP_INITIAL_INSTANCE_CAPACITY);

  /* Initialize RootInstance buffers and synchronization */
  uv_mutex_init(&NewApplication->RootInstance.StateMutex);
  uv_cond_init(&NewApplication->RootInstance.StateCondition);
  uv_mutex_init(&NewApplication->RootInstance.EventMutex);

  /* Create the initial instance (will execute LUA_LuaThread) */
  APP_CreateInstance(NewApplication, &NewApplication->RootInstance, "main", NULL);

  return NewApplication;
}

static bool APP_ContainsInstance (struct LUA_Application *Application,
                                  struct LUA_Instance    *Instance)
{
  size_t InstanceCapacity = TA_GetCapacity(Application->InstanceArray);
  size_t InstanceOffset   = 1;
  bool   Found            = false;
  
  struct LUA_Instance *CurrentInstance;
  
  while (!Found && (InstanceOffset <= InstanceCapacity))
  {
    if (TA_IsValid(Application->InstanceArray, InstanceOffset))
    {
      CurrentInstance = TA_GetObject(Application->InstanceArray, InstanceOffset);
      if (CurrentInstance == Instance)
      {
        Found = true;
      }
      else
      {
        InstanceOffset++;
      }
    }
    else
    {
      InstanceOffset++;
    }
  }

  return Found;
}

static void APP_CleanupOrphanedInstances (struct LUA_Application *Application,
                                          struct LUA_Instance    *OrphansRoot) 
{
  size_t InstanceCapacity = TA_GetCapacity(Application->InstanceArray);
  size_t Offset;
  
  struct LUA_Instance *CurrentInstance;
  struct LUA_Instance *ParentInstance;
  
  /* Reparent top-level orphaned instances (those whose parent is invalid) */
  for (Offset = 1; Offset <= InstanceCapacity; Offset++)
  {
    if (TA_IsValid(Application->InstanceArray, Offset))
    {
      CurrentInstance = TA_GetObject(Application->InstanceArray, Offset);
      ParentInstance  = CurrentInstance->Parent;
      
      if ((ParentInstance != OrphansRoot)
          && !APP_ContainsInstance(Application, ParentInstance))
      {
        CurrentInstance->Parent = OrphansRoot;
      }
    }
  }
}

static size_t APP_GetInstanceCount (struct LUA_Application *Application)
{
  size_t Count = 0;
  size_t Offset;

  /* Count all valid instances */
  for (Offset = 1; Offset <= TA_GetCapacity(Application->InstanceArray); Offset++)
  {
    if (TA_IsValid(Application->InstanceArray, Offset))
    {
      Count++;
    }
  }

  return Count;
}

extern void LUA_RunApplication (struct LUA_Application *Application)
{
  struct LUA_Instance  OrphansRoot;
  struct LUA_Instance *MainInstance;
  size_t               OrphanCount;

  /* Get the main instance (first created instance) */
  uv_mutex_lock(&Application->InstanceArrayMutex);
  MainInstance = TA_GetObject(Application->InstanceArray, 1);
  uv_mutex_unlock(&Application->InstanceArrayMutex);

  /* Wait for thread exit and cleanup resources */
  LUA_WaitAndRelease(Application, MainInstance);
  
  uv_mutex_lock(&Application->InstanceArrayMutex);
  
  /* Check for remaining threads */
  OrphanCount = APP_GetInstanceCount(Application);
  if (OrphanCount > 0)
  {
    /* Initialize OrphansRoot */
    memset(&OrphansRoot, 0, sizeof(struct LUA_Instance));
    OrphansRoot.Offset     = 1;
    OrphansRoot.Parent     = NULL;
    OrphansRoot.ModuleName = "Orphans";
    
    /* Clean up orphaned instances before printing hierarchy */
    APP_CleanupOrphanedInstances(Application, &OrphansRoot);
    
    printf("WARNING: %zu thread(s) are still active\n", OrphanCount);
    APP_PrintThreadHierarchy(Application, &OrphansRoot, 0);
  }

  uv_mutex_unlock(&Application->InstanceArrayMutex);
}

void SERVICE_NotifyInstance (struct LUA_Application *Application,
                             const char             *EventName,
                             unsigned int            ControlCode)
{
  struct LUA_Instance *TargetInstance;
  struct BA_Allocator *PendingEvents;
  struct MAIN_Event    Event;
  size_t               EventNameLength;
  
  uv_mutex_lock(&Application->InstanceArrayMutex);
  if (TA_IsValid(Application->InstanceArray, 1))
  {
    TargetInstance = TA_GetObject(Application->InstanceArray, 1);
  }
  else
  {
    TargetInstance = NULL;
  }
  uv_mutex_unlock(&Application->InstanceArrayMutex);

  if (TargetInstance)
  {
    /* Retrieve a lock EventQueue */
    uv_mutex_lock(&TargetInstance->EventMutex);
    PendingEvents = TargetInstance->EventBufferReceive;
    
    /* Enqueue START: function name + ctrlCode */
    Event.Type = INSTANCE_EVENT_START;
    Event.Data.Start.ArgumentCount = 2;
    APP_EnqueueEventArgument(PendingEvents, &Event);

    /* Enqueue function name as string */
    EventNameLength                = strlen(EventName);
    Event.Type                     = INSTANCE_EVENT_PARAM_STRING;
    Event.Data.String.ValuePointer = (char *)EventName;
    Event.Data.String.Length       = EventNameLength;
    APP_EnqueueEventArgument(PendingEvents, &Event);

    /* Enqueue ControlCode as integer */
    Event.Type               = INSTANCE_EVENT_PARAM_INTEGER;
    Event.Data.Integer.Value = ControlCode;
    APP_EnqueueEventArgument(PendingEvents, &Event);

    /* Enqueue END */
    Event.Type = INSTANCE_EVENT_END;
    APP_EnqueueEventArgument(PendingEvents, &Event);

    uv_mutex_unlock(&TargetInstance->EventMutex);

    /* Notify the event loop */
    uv_mutex_lock(&TargetInstance->StateMutex);
    APP_BIT_SET(TargetInstance->State, INSTANCE_MASK_EVENTS_PENDING);
    uv_cond_signal(&TargetInstance->StateCondition);
    uv_mutex_unlock(&TargetInstance->StateMutex);
  }
}

extern void LUA_FreeApplication (struct LUA_Application *Application)
{
  uv_mutex_destroy(&Application->InstanceArrayMutex);
  TA_FreeArray(Application->InstanceArray);
  PLAT_Free(Application->ComexeApi);
  PLAT_Free(Application);
}
