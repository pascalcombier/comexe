# Foreign Function Interface in ComEXE

* [Overview](#overview)
  * [Generating bindings](#generating-bindings)
  * [Loading a shared library](#loading-a-shared-library)
  * [Calling foreign functions](#calling-foreign-functions)
  * [Sorting arrays of structures](#sorting-arrays-of-structures)
* [FFI module API](#ffi-module-api)
  * [Basic workflow](#basic-workflow)
  * [Constants](#constants)
  * [Main functions](#main-functions)
  * [Library objects](#library-objects)
  * [Array objects](#array-objects)
  * [Structure type objects](#structure-type-objects)
  * [Structure instance objects](#structure-instance-objects)
  * [Callback objects](#callback-objects)
* [Memory allocation](#memory-allocation)
  * [Allocate memory using mimalloc](#allocate-memory-using-mimalloc)
  * [Allocate memory without mimalloc](#allocate-memory-without-mimalloc)
  * [Functions](#functions)
  * [Memory ownership](#memory-ownership)
  * [Comparing pointers and NULL](#comparing-pointers-and-null)
* [Limitations](#limitations)

# Overview

This module uses [libffi](https://github.com/libffi/libffi) to call **foreign functions** in shared libraries (`.dll` on Windows, `.so` on Linux). Lua can call them like normal Lua functions, no C compiler needed.

- Pointers, `malloc`, `free` and segfaults for Lua ♥
- Call foreign functions, including variadics like `sprintf`
- Implement callbacks in Lua for functions like `qsort`
- Structures and arrays

## Generating bindings

ComEXE's [preprocessor](./comexe-reference-preprocessor.md), based on [Facebook CParser](https://github.com/facebookresearch/CParser), generates bindings from `C` headers.

**[tiny-libc.h](../tests/examples/ffi/tiny-libc.h)**

```
void *malloc  (size_t size);
void  free    (void *ptr);
int   puts    (const char* str);
int   sprintf (char *str, const char *format, ...);
void  qsort   (void *base, size_t num, size_t size, void *compar);
```

This header is referenced from a block in the Lua source file:

```lua
-- @BEGIN FfiHeader("BindLibrary", "libffi", "tiny-libc.h")
-- @END
```

The preprocessor generates the bindings in place:

```console
lua55ce.exe -x --preprocess tests/examples/ffi/test-tiny-libc.lua
```

The block now contains the generated bindings:

```lua
-- @BEGIN FfiHeader("BindLibrary", "libffi", "tiny-libc.h")
-- @OUTPUT
-- Functions
local free
local malloc
local puts
local qsort
local sprintf
-- Binding function
local function BindLibrary (Library)
  free = Library:bind(libffi.void, "free", libffi.pointer)
  malloc = Library:bind(libffi.pointer, "malloc", libffi.uint64)
  puts = Library:bind(libffi.sint32, "puts", libffi.pointer)
  qsort = Library:bind(libffi.void, "qsort", libffi.pointer, libffi.uint64, libffi.uint64, libffi.pointer)
  sprintf = Library:variadicbind(libffi.sint32, "sprintf", libffi.pointer, libffi.pointer)
end
-- @END
```

The generated `BindLibrary(Library)` function registers functions, constants, and structures as **local variables** in the source file.

## Loading a shared library

```lua
local libffi = require("com.ffi")

local libc = libffi.loadlib("msvcrt.dll")
```

It searches standard OS paths (executable directory, `PATH`, system directories) and returns a library object if found, or `nil` if the library is not found. Library names differ across operating systems, so it also accepts a list of OS and library name pairs:

```lua
local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so", "linux", "libc.so.1")
```

Returns the first matching pair. On Windows it tries `"msvcrt.dll"`, on Linux `"libc.so"` then `"libc.so.1"`. String case matters: use `"linux"`, not `"Linux"`.

## Calling foreign functions

**[test-tiny-libc.lua](../tests/examples/ffi/test-tiny-libc.lua)**

```lua
local libffi = require("com.ffi")

-- @BEGIN FfiHeader("BindLibrary", "libffi", "tiny-libc.h")
-- @OUTPUT
-- Functions
local free
local malloc
local puts
local qsort
local sprintf
-- Binding function
local function BindLibrary (Library)
  free = Library:bind(libffi.void, "free", libffi.pointer)
  malloc = Library:bind(libffi.pointer, "malloc", libffi.uint64)
  puts = Library:bind(libffi.sint32, "puts", libffi.pointer)
  qsort = Library:bind(libffi.void, "qsort", libffi.pointer, libffi.uint64, libffi.uint64, libffi.pointer)
  sprintf = Library:variadicbind(libffi.sint32, "sprintf", libffi.pointer, libffi.pointer)
end
-- @END

-- Load DLL and apply the bindings
local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so", "linux", "libc.so.6")
BindLibrary(libc)

local Buffer = malloc(1024)

if (Buffer ~= libffi.NULL) then
  local Count = sprintf(Buffer, "Hello, %s! int=%d float=%f", "FFI", 42, 3.14)
  print(string.format("snprintf returned %d", Count))
  puts(Buffer)
  free(Buffer)
  print("OK")
else
  error("sprintf failed")
end
```

Note that pointers are *light userdata* and **the `NULL` pointer is not `nil`**. That program should output:

```console
> lua55ce tests/examples/ffi/test-tiny-libc.lua
snprintf returned 33
Hello, FFI! int=42 float=3.140000
OK
```

## Sorting arrays of structures

This example sorts an **array of structures** by calling `qsort` with a **Lua callback**.

**[test-doc-struct-qsort.lua](../tests/examples/ffi/test-doc-struct-qsort.lua)**

```lua
local libffi = require("com.ffi")

local format = string.format

-- @BEGIN FfiHeader("BindLibrary", "libffi", "tiny-libc.h")
-- @OUTPUT
-- Functions
local free
local malloc
local puts
local qsort
local sprintf
-- Binding function
local function BindLibrary (Library)
  free = Library:bind(libffi.void, "free", libffi.pointer)
  malloc = Library:bind(libffi.pointer, "malloc", libffi.uint64)
  puts = Library:bind(libffi.sint32, "puts", libffi.pointer)
  qsort = Library:bind(libffi.void, "qsort", libffi.pointer, libffi.uint64, libffi.uint64, libffi.pointer)
  sprintf = Library:variadicbind(libffi.sint32, "sprintf", libffi.pointer, libffi.pointer)
end
-- @END

local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so", "linux", "libc.so.6")
BindLibrary(libc)

local UserStruct = libffi.newstructure("User",
  libffi.int32_t, "Id",
  libffi.cstring, "Name",
  libffi.int32_t, "Age"
)

local function CompareByAge (PointerA, PointerB)
  local UserA = UserStruct:cast(PointerA)
  local UserB = UserStruct:cast(PointerB)
  return (UserA:get("Age") - UserB:get("Age"))
end

local CompareCallback = libffi.newcallback(CompareByAge, libffi.int32_t, libffi.pointer, libffi.pointer)

local function ConfigureUser (Array, Index, Id, Name, Age)
  local User = Array:get(Index)
  User:set("Id",   Id)
  User:set("Name", Name)
  User:set("Age",  Age)
end

local function PrintUsers (Array, Label)
  print(Label)
  local ElementCount = Array:getcount()
  for Index = 1, ElementCount do
    local User = Array:get(Index)
    local Name = User:get("Name")
    local Age  = User:get("Age")
    print(format("  %4.4s - Age %d", Name, Age))
  end
end

local Users = libffi.newarray(UserStruct, 4)

ConfigureUser(Users, 1, 3, "Zoe",  28)
ConfigureUser(Users, 2, 1, "Amy",  35)
ConfigureUser(Users, 3, 4, "Carl", 22)
ConfigureUser(Users, 4, 2, "Bob",  42)

local UserStructSize = libffi.sizeof(UserStruct)
local ArrayPointer   = Users:getpointer()
local ComparePointer = CompareCallback:getpointer()

PrintUsers(Users, "Before")
local Count = Users:getcount()
qsort(ArrayPointer, Count, UserStructSize, ComparePointer)
PrintUsers(Users, "After")
```

The program sorts the users by age and outputs:

```console
> lua55ce tests/examples/ffi/test-doc-struct-qsort.lua
Before
   Zoe - Age 28
   Amy - Age 35
  Carl - Age 22
   Bob - Age 42
After
  Carl - Age 22
   Zoe - Age 28
   Amy - Age 35
   Bob - Age 42
```

# FFI module API

## Basic workflow

```lua
local libffi = require("com.ffi")

-- @BEGIN FfiHeader("BindInterface", "libffi", "interface.h")
-- @END

-- Load the DLL
local dll = libffi.loadlib("library.dll")

BindInterface(dll)

-- Call the functions
myfunction()
```

## Constants

| Constant             | C type        | Description                               |
|----------------------|---------------|-------------------------------------------|
| `ffi.void`           | `void`        | No return / no parameter                  |
| `ffi.int8_t`         | `int8_t`      | Signed 8-bit integer                      |
| `ffi.uint8_t`        | `uint8_t`     | Unsigned 8-bit integer                    |
| `ffi.int16_t`        | `int16_t`     | Signed 16-bit integer                     |
| `ffi.uint16_t`       | `uint16_t`    | Unsigned 16-bit integer                   |
| `ffi.int32_t`        | `int32_t`     | Signed 32-bit integer                     |
| `ffi.uint32_t`       | `uint32_t`    | Unsigned 32-bit integer                   |
| `ffi.int64_t`        | `int64_t`     | Signed 64-bit integer                     |
| `ffi.uint64_t`       | `uint64_t`    | Unsigned 64-bit integer                   |
| `ffi.float`          | `float`       | 32-bit IEEE floating-point                |
| `ffi.double`         | `double`      | 64-bit IEEE floating-point                |
| `ffi.pointer`        | `void*`       | Generic pointer                           |
| `ffi.complex_float`  | `float[2]`    | Complex float (compiler-dependent)        |
| `ffi.complex_double` | `double[2]`   | Complex double (compiler-dependent)       |
| `ffi.size_t`         | `size_t`      | Convenience                               |
| `ffi.cstring`        | `const char*` | Auto conversion between C and Lua strings |
| `ffi.NULL`           | `NULL`        | Null pointer (light userdata)             |

## Main functions

| Function                                                           | Returns                    | Description                                                           |
|--------------------------------------------------------------------|----------------------------|-----------------------------------------------------------------------|
| `ffi.loadlib("library.dll")`                                       | Library object or nil      | Load a shared library.                                                |
| `ffi.loadlib("os", "dll", ...)`                                    | Library object or nil      | Load a shared library. Accepts OS-name and library-name pairs.        |
| `ffi.newcallback(Function, ReturnType, ...)`                       | Callback object            | Wrap a Lua function into a C callback.                                |
| `ffi.newstructure("Name", fieldtype, "fieldname", ...)`            | StructureType, ErrorString | Create a structure type from alternating field types and field names. |
| `ffi.newarray(Type, Count)`                                        | Array object               | Allocate a GC-managed array of `Count` elements of the given type.    |
| `ffi.newinstance(Type)`                                            | Structure instance         | Allocate and return one structure instance.                           |
| `ffi.sizeof(Type)`                                                 | size in bytes              | Return the size in bytes of any FFI type, including structures.       |
| `ffi.importfunction(FunctionPointer, ReturnType, ParamType1, ...)` | Function, PrivateContext   | Import a C function into Lua from a pointer.                          |
| `ffi.readmemory(Pointer, Offset, Length)`                          | string                     | Read `Length` bytes from a pointer at the given byte `Offset`.        |
| `ffi.readstring(Pointer [, Offset])`                               | string                     | Read a null-terminated C string from a pointer.                       |
| `ffi.readstringw(Pointer [, Offset])`                              | string                     | Read a null-terminated UTF-16 string from a pointer.                  |

## Library objects

Library objects are returned by `ffi.loadlib`.

| Method                                                       | Description                                                                                                                          |
|--------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| `lib:bind(ReturnType, "Name", ParamType1, ...)`              | Return a Lua function that calls the named symbol with the given signature.                                                          |
| `lib:variadicbind(ReturnType, "Name", FixedParamType1, ...)` | Return a Lua variadic wrapper. Types of variadic arguments are inferred on each call and wrappers are cached per inferred signature. |
| `lib:addlibrary(...)`                                        | Load an additional shared library. Symbols resolve across all loaded libraries. Accepts same args as `ffi.loadlib`.                  |

Example:

```lua
local libffi = require("com.ffi")
local libc   = libffi.loadlib("msvcrt.dll")

local void    = libffi.void
local int32_t = libffi.int32_t
local pointer = libffi.pointer

local puts    = libc:bind(int32_t, "puts", pointer)
local sprintf = libc:variadicbind(int32_t, "sprintf", pointer)
```

For `variadicbind`, C types are inferred:

| Lua value            | Inferred C type | Notes                                                                     |
|----------------------|-----------------|---------------------------------------------------------------------------|
| `nil`                | `pointer`       | Resolves to NULL                                                          |
| `string`             | `pointer`       |                                                                           |
| `boolean`            | `int32_t`       | 1 or 0                                                                    |
| `number` *"integer"* | `int32_t`       | Via [math.type](https://www.lua.org/manual/5.5/manual.html#pdf-math.type) |
| `number` *"float"*   | `double`        | Via [math.type](https://www.lua.org/manual/5.5/manual.html#pdf-math.type) |
| `lightuserdata`      | `pointer`       |                                                                           |
| structure instance   | `pointer`       | Via `instance:getpointer()`                                               |
| array                | `pointer`       | Via `array:getpointer()`                                                  |

`lib:addlibrary` loads additional shared libraries. This allows a single binding file to link multiple DLLs. Symbols are looked up across all loaded libraries:

```lua
local libffi = require("com.ffi")

-- @BEGIN FfiHeader("BindWin32", "libffi", "win32.h")
-- @END

local win32 = libffi.loadlib("kernel32.dll")
win32:addlibrary("user32.dll")
win32:addlibrary("advapi32.dll")
win32:addlibrary("shell32.dll")
BindWin32(win32)
```

## Array objects

Resizable array objects are returned by `ffi.newarray(Type, Count)`. The array grows automatically when `array:set` is called.

| Method                      | Description                                                          |
|-----------------------------|----------------------------------------------------------------------|
| `Array:get(Index)`          | Read the structure instance at the given 1-based index.              |
| `Array:set(Index, Value)`   | Write a value to the given 1-based index.                            |
| `Array:getcount()`          | Return the number of elements in the array.                          |
| `Array:copyfrom(LuaTable)`  | Copy elements from a Lua table into the array, resizing if needed.   |
| `Array:totable()`           | Convert the array to a plain Lua table of structure instances.       |
| `Array:getpointer([Index])` | Return pointer to first element, or to element at `Index` (1-based). |

## Structure type objects

Structure type objects are returned by `ffi.newstructure`.

| Method                           | Description                                                                            |
|----------------------------------|----------------------------------------------------------------------------------------|
| `StructType:gettypename()`       | Return structure type name.                                                            |
| `StructType:getffitype()`        | Return underlying ffi_type handle.                                                     |
| `StructType:getalignment()`      | Return required alignment in bytes.                                                    |
| `StructType:getoffsets()`        | Return an array of field offsets in bytes.                                             |
| `StructType:setoffsets(Offsets)` | Override field offsets computed by libffi. Returns nil on success, or an error string. |
| `StructType:cast(Pointer)`       | Create a structure instance view over existing memory. No allocation is performed.     |

Ways to create structure instances:

* `ffi.newarray(Type, Count)` allocates an array.
* `ffi.newinstance(Type)` allocates a single instance.

## Structure instance objects

Structure instance objects are returned by `ffi.newinstance`, `ffi.newarray`, or `StructType:cast`.

| Method                      | Description                                           |
|-----------------------------|-------------------------------------------------------|
| `Instance:set(Name, Value)` | Write one field by name.                              |
| `Instance:get(Name)`        | Read one field by name.                               |
| `Instance:getpointer()`     | Return the pointer to this instance in native memory. |

## Callback objects

**Callback objects** wrap a Lua function in a C-callable function pointer.

Callback objects are returned by `ffi.newcallback(Function, ReturnType, ...)`.

| Method                  | Description                                      |
|-------------------------|--------------------------------------------------|
| `Callback:getpointer()` | Return the C function pointer for this callback. |

# Memory allocation

ComEXE uses [mimalloc](https://github.com/microsoft/mimalloc) as its system allocator. It follows the same design as [GLib](https://docs.gtk.org/glib/memory.html#memory-allocation): if an allocation fails, the program prints an error message and exits.

## Allocate memory using mimalloc

```lua
local libffi = require("com.ffi")

local Buffer = libffi.malloc(1024)

-- The pointer is always valid and can be used directly

libffi.free(Buffer)
```

## Allocate memory without mimalloc

`malloc` can also be called directly from the standard C library, bypassing `mimalloc`. Unlike `ffi.malloc`, the returned pointer may be `NULL`.

```lua
local libffi = require("com.ffi")

-- @BEGIN FfiDeclarations("BindLibrary", "libffi")
-- void *malloc (size_t size);
-- void  free   (void *ptr);
-- @OUTPUT
-- Functions
local free
local malloc
-- Binding function
local function BindLibrary (Library)
  free = Library:bind(libffi.void, "free", libffi.pointer)
  malloc = Library:bind(libffi.pointer, "malloc", libffi.uint64)
end
-- @END

local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so")
BindLibrary(libc)

local Buffer = malloc(1024)
if (Buffer ~= libffi.NULL) then
  -- use Buffer
  free(Buffer)
end
```

## Functions

| Function                          | Returns       | Description                                                                                                                        |
|-----------------------------------|---------------|------------------------------------------------------------------------------------------------------------------------------------|
| `ffi.getpagesize()`               | integer       | Return the OS page size in bytes.                                                                                                  |
| `ffi.malloc(Size)`                | lightuserdata | Allocate `Size` bytes (zero-initialized). Always returns a valid pointer.                                                          |
| `ffi.realloc(Pointer, Size)`      | lightuserdata | Resize an existing allocation. Always returns a valid pointer.                                                                     |
| `ffi.free(Pointer)`               |               | Release memory allocated by `ffi.malloc` or `ffi.realloc`.                                                                         |
| `ffi.memset(Pointer, Byte, Size)` |               | Fill `Size` bytes at `Pointer` with `Byte` value.                                                                                  |
| `ffi.stringpointer(String)`       | lightuserdata | Return a pointer to the internal buffer of a Lua string. The pointer is valid as long as the string is referenced on the Lua side. |

## Memory ownership

| Source                       | Memory Management | Details                   |
|------------------------------|-------------------|---------------------------|
| `ffi.malloc(Size)`           | Manual            | `ffi.free`                |
| `ffi.realloc(Pointer, Size)` | Manual            | `ffi.free`                |
| `ffi.newarray(Type, Count)`  | Automatic         | Garbage collector         |
| `ffi.newinstance(Type)`      | Automatic         | Garbage collector         |
| `Struct:cast(Pointer)`       | None              | View over existing memory |

## Comparing pointers and NULL

The `NULL` pointer in FFI is a **light userdata**, not Lua's `nil`. Always use `ffi.NULL` for comparison, never `nil`:

```lua
local libffi = require("com.ffi")

-- @BEGIN FfiDeclarations("BindLibrary", "libffi")
-- void *malloc (size_t size);
-- void  free   (void *ptr);
-- @OUTPUT
-- Functions
local free
local malloc
-- Binding function
local function BindLibrary (Library)
  free = Library:bind(libffi.void, "free", libffi.pointer)
  malloc = Library:bind(libffi.pointer, "malloc", libffi.uint64)
end
-- @END

local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so")
BindLibrary(libc)

local Buffer = malloc(1024)
if (Buffer == libffi.NULL) then
  error("allocation failed")
end
free(Buffer)
```

# Limitations

- Currently only 64-bit
- 32-bit calling convention split (cdecl vs stdcall) is not supported.
- Nested or recursive callbacks are not supported.
