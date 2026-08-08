# ComEXE's Preprocessor Reference

* [Overview](#overview)
* [Generate bindings from inline C](#generate-bindings-from-inline-c)
  * [Input file](#input-file)
  * [Signature](#signature)
  * [Output file](#output-file)
  * [Complete example](#complete-example)
* [Generate bindings from a C header](#generate-bindings-from-a-c-header)
  * [Input file](#input-file-1)
  * [Signature](#signature-1)
  * [Output file](#output-file-1)
  * [Complete example](#complete-example-1)

# Overview

The main purpose of the preprocessor is to help write FFI bindings. It parses C code and generates Lua code ahead of time.

> **Warning:** the preprocessor rewrites the file in place, PLEASE MAKE BACKUPS!

**example.lua**

```lua
LINE-01
LINE-02
LINE-03
-- @BEGIN HandlerName("arg1", "arg2", ...)
-- INPUT-BLOCK-LINE-1
-- INPUT-BLOCK-LINE-2
-- INPUT-BLOCK-LINE-N
-- @OUTPUT
-- @END
LINE-04
LINE-05
LINE-06
```

The preprocessor will overwrite `example.lua`:

```console
lua55ce -x --preprocess example.lua
```

New file content:

```lua
LINE-01
LINE-02
LINE-03
-- @BEGIN HandlerName("arg1", "arg2", ...)
-- INPUT-BLOCK-LINE-1
-- INPUT-BLOCK-LINE-2
-- INPUT-BLOCK-LINE-N
-- @OUTPUT
-- GENERATED-LINE-1 <------ UPDATED!
-- GENERATED-LINE-2 <------ UPDATED!
-- GENERATED-LINE-3 <------ UPDATED!
-- @END
LINE-04
LINE-05
LINE-06
```

The content between `@OUTPUT` and `@END` is refreshed.

The `@BEGIN` line calls one of the built-in handlers.

* The `FfiDeclarations` generates bindings from inline C declarations
* The `FfiHeader` generates FFI bindings from a C header file

Those are described in the following chapters.

# Generate bindings from inline C

## Input file

**example.lua**

```lua
-- @BEGIN FfiDeclarations("BindLibrary", "libffi")
-- int puts(const char *s);
-- void exit(int status);
-- @OUTPUT
-- @END
```

## Signature

`FfiDeclarations(FunctionName, LibVariable)`

- **`FunctionName`** is the name of the generated bind function (`BindLibrary`)
- **`LibVariable`** is the name of the variable containing libffi (from `require("com.ffi")`)

## Output file

Run the preprocessor:

```console
lua55ce -x --preprocess example.lua
```

The block now contains the generated bindings:

```lua
-- @BEGIN FfiDeclarations("BindLibrary", "libffi")
-- int puts(const char *s);
-- void exit(int status);
-- @OUTPUT
-- Functions
local exit
local puts
-- Binding function
local function BindLibrary (Library)
  exit = Library:bind(libffi.void, "exit", libffi.sint32)
  puts = Library:bind(libffi.sint32, "puts", libffi.pointer)
end
-- @END
```

## Complete example

```lua
local libffi = require("com.ffi")

-- @BEGIN FfiDeclarations("BindLibrary", "libffi")
-- int puts(const char *s);
-- void exit(int status);
-- @OUTPUT
-- Functions
local exit
local puts
-- Binding function
local function BindLibrary (Library)
  exit = Library:bind(libffi.void, "exit", libffi.sint32)
  puts = Library:bind(libffi.sint32, "puts", libffi.pointer)
end
-- @END

local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so.6")
BindLibrary(libc)
puts("Hello, world!")
```

# Generate bindings from a C header

## Input file

**example.lua**

```lua
-- @BEGIN FfiHeader("BindLibrary", "libffi", "tiny-libc.h")
-- @OUTPUT
-- @END
```

## Signature

`FfiHeader(FunctionName, LibVariable, File)`

- **`FunctionName`** is the name of the generated bind function (`BindLibrary`)
- **`LibVariable`** is the name of the variable containing libffi (from `require("com.ffi")`)
- **`File`** is the path to a C header file

## Output file

Run the preprocessor:

```console
lua55ce -x --preprocess example.lua
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

## Complete example

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

local libc = libffi.loadlib("windows", "msvcrt.dll", "linux", "libc.so.6")
BindLibrary(libc)
puts("Hello, world!")
```
