#include <stddef.h>
size_t PLAT_GetPageSizeInBytes();
int PLAT_IsAtty(int FileDescriptor);
void PLAT_ThreadInitalize();
void PLAT_ThreadDeinitialize();
void *PLAT_SafeAlloc0(size_t Count,size_t ObjectSizeInBytes);
void *PLAT_SafeRealloc(void *Object,size_t ObjectSizeInBytes);
void PLAT_Free(void *Object);
char *PLAT_StrDup(const char *String);
#include <stdbool.h>
#include <lua.h>
int luaopen_luv(lua_State *LuaState);
int luaopen_socket_core(lua_State *LuaState);
int luaopen_mime_core(lua_State *LuaState);
int luaopen_mbedtls(lua_State *LuaState);
int luaopen_libtcc(lua_State *LuaState);
bool LUA_PushEventHandler(lua_State *LuaState);
struct LUA_Application *LUA_CreateApplication(size_t Argc,const char **Argv);
void LUA_RunApplication(struct LUA_Application *Application);
void SERVICE_NotifyInstance(struct LUA_Application *Application,const char *EventName,unsigned int ControlCode);
void LUA_FreeApplication(struct LUA_Application *Application);
#include <stdint.h>
typedef size_t BA_Key_t;
struct BA_Allocator *BA_NewAllocator(size_t InitialCount,size_t InitialSizeInByte);
void BA_Reset(struct BA_Allocator *Allocator);
void BA_FreeAllocator(struct BA_Allocator *Allocator);
size_t BA_GetCount(struct BA_Allocator *Allocator);
void BA_AllocateBlob(struct BA_Allocator *Allocator,size_t SizeInByte,BA_Key_t *Key,uint8_t **BlobStart);
BA_Key_t BA_PushBlob(struct BA_Allocator *Allocator,const void *Memory,size_t SizeInByte);
BA_Key_t BA_PushInt32(struct BA_Allocator *Allocator,int32_t Value);
BA_Key_t BA_PushUint32(struct BA_Allocator *Allocator,uint32_t Value);
BA_Key_t BA_PushInt64(struct BA_Allocator *Allocator,int64_t Value);
BA_Key_t BA_PushUint64(struct BA_Allocator *Allocator,uint64_t Value);
BA_Key_t BA_PushDouble(struct BA_Allocator *Allocator,double Value);
BA_Key_t BA_PushString(struct BA_Allocator *Allocator,const char *String);
BA_Key_t BA_PushPointer(struct BA_Allocator *Allocator,void *Pointer);
bool BA_GetBlob(struct BA_Allocator *Allocator,BA_Key_t Key,uint8_t **Blob,size_t *BlobSizesInBytes);
bool BA_GetInt32(struct BA_Allocator *Allocator,BA_Key_t Key,int32_t *Value);
bool BA_GetUint32(struct BA_Allocator *Allocator,BA_Key_t Key,uint32_t *Value);
bool BA_GetInt64(struct BA_Allocator *Allocator,BA_Key_t Key,int64_t *Value);
bool BA_GetUint64(struct BA_Allocator *Allocator,BA_Key_t Key,uint64_t *Value);
bool BA_GetDouble(struct BA_Allocator *Allocator,BA_Key_t Key,double *Value);
bool BA_GetString(struct BA_Allocator *Allocator,BA_Key_t Key,const char **String);
bool BA_GetPointer(struct BA_Allocator *Allocator,BA_Key_t Key,void **Value);
bool BA_SetInt32(struct BA_Allocator *Allocator,BA_Key_t Key,int32_t Value);
bool BA_SetUint32(struct BA_Allocator *Allocator,BA_Key_t Key,uint32_t Value);
bool BA_SetInt64(struct BA_Allocator *Allocator,BA_Key_t Key,int64_t Value);
bool BA_SetUint64(struct BA_Allocator *Allocator,BA_Key_t Key,uint64_t Value);
bool BA_SetDouble(struct BA_Allocator *Allocator,BA_Key_t Key,double Value);
bool BA_SetPointer(struct BA_Allocator *Allocator,BA_Key_t Key,void *Value);
struct PB_Allocator {
  size_t (*GetPageSizeInBytes)(void);
  
  void * (*Alloc)  (size_t Count, size_t SizeInBytes);
  void   (*Free)   (void *Pointer);
  void * (*Realloc)(void *Pointer, size_t NewSizeInBytes);
};
struct PB_Buffer *PB_NewBuffer(struct PB_Allocator *Allocator,size_t InitialSizeInBytes);
void PB_FreeBuffer(struct PB_Buffer *Buffer);
struct PB_Buffer *PB_EnsureCapacity(struct PB_Buffer *Buffer,size_t NeededCapacity);
size_t PB_GetCapacity(struct PB_Buffer *Buffer);
void *PB_GetData(struct PB_Buffer *Buffer);
struct TQU_Queue *TQU_CreateQueue(size_t InitialCapacity);
void TQU_FreeQueue(struct TQU_Queue *Queue);
bool TQU_Enqueue(struct TQU_Queue *Queue,size_t Value);
size_t TQU_Peek(struct TQU_Queue *Queue);
size_t TQU_Dequeue(struct TQU_Queue *Queue);
size_t TQU_GetCapacity(struct TQU_Queue *Queue);
size_t TQU_GetCount(struct TQU_Queue *Queue);
bool TQU_IsEmpty(struct TQU_Queue *Queue);
bool TQU_IsFull(struct TQU_Queue *Queue);
struct TA_Array *TA_CreateArray(size_t InitialCapacity);
void TA_FreeArray(struct TA_Array *Array);
size_t TA_AddObject(struct TA_Array *Array,void *Object);
size_t TA_GetCapacity(struct TA_Array *Array);
bool TA_IsValid(struct TA_Array *Array,size_t Offset);
void *TA_GetObject(struct TA_Array *Array,size_t Offset);
void TA_RemoveObject(struct TA_Array *Array,size_t Offset);
int luaopen_libminizip(lua_State *LuaState);
LUALIB_API int luaopen_libffiraw(lua_State *LuaState);
int luaopen_win32(lua_State *LuaState);
int luaopen_buffer(lua_State *LuaState);
void SERVICE_Initialize(struct LUA_Application *Application);
int luaopen_service(lua_State *LuaState);
int luaopen_wincom_raw(lua_State *LuaState);
#define MKH_INTERFACE 0
#define MKH_EXPORT_INTERFACE 0
#define MKH_LOCAL_INTERFACE 0
#define EXPORT
#define LOCAL static
#define PUBLIC
#define PRIVATE
#define PROTECTED
