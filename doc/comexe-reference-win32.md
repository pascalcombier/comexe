# Win32 API reference

* [Overview](#overview)
* [Unicode conversion](#unicode-conversion)
* [Registry](#registry)
* [Key objects](#key-objects)
* [Dialogs](#dialogs)
* [ShellExecute](#shellexecute)
* [Utilities](#utilities)
* [Technical notes](#technical-notes)
  * [luv vs ComEXE conversion](#luv-vs-comexe-conversion)
  * [Sleep](#sleep)

# Overview

The `com.win32` module provides a minimal interface to the Win32 API. Functions not covered are available in the [Foreign Function Interface](./comexe-reference-ffi.md).

| Function          | Description                                              | Section                                   |
|-------------------|----------------------------------------------------------|-------------------------------------------|
| `getlasterror`    | Return the error code of the last Win32 call             | [Utilities](#utilities)                   |
| `formatmessage`   | Format a Win32 error code into a readable message string | [Utilities](#utilities)                   |
| `expandstrings`   | Expand environment variables                             | [Utilities](#utilities)                   |
| `utf8to16`        | UTF-8 to UTF-16                                          | [Unicode conversion](#unicode-conversion) |
| `utf16to8`        | UTF-16 to UTF-8                                          | [Unicode conversion](#unicode-conversion) |
| `pointertostring` | Read a C string from a pointer                           | [Unicode conversion](#unicode-conversion) |
| `regcreatekey`    | Create a key, or open it if it already exists            | [Registry](#registry)                     |
| `regopenkey`      | Open an existing key                                     | [Registry](#registry)                     |
| `regdeletekey`    | Delete a key                                             | [Registry](#registry)                     |
| `regsam`          | Calculate an integer `Sam` value                         | [Registry](#registry)                     |
| `regoptions`      | Calculate an integer `Options` value                     | [Registry](#registry)                     |
| `messagebox`      | Display a message box                                    | [Dialogs](#dialogs)                       |
| `shellexecute`    | Launch an application, a document or a URI               | [ShellExecute](#shellexecute)             |
| `openbrowser`     | Open a URI in the default browser                        | [ShellExecute](#shellexecute)             |

# Unicode conversion

## Functions

**Function** `utf8to16(StringUtf8)` -> `StringUtf16, ErrorString`

**Function** `utf16to8(StringUtf16)` -> `StringUtf8, ErrorString`

**Function** `pointertostring(Pointer, SourceEncoding, TargetEncoding)` -> `String, ErrorString`

Read a C string from a [libffi](./comexe-reference-ffi.md) pointer (light userdata).

* `SourceEncoding` and `TargetEncoding` can be `"utf8"` or `"utf16"`
* `pointertostring` expects a NUL-terminated string
* `pointertostring` returns `nil` for a `NULL` pointer or an empty string
* For technical details about conversions, refer to the [luv vs ComEXE conversion section](#luv-vs-comexe-conversion).

## Examples

utf8to16 and utf16to8

```lua
local win32 = require("com.win32")

local StringUtf16, ErrorString = win32.utf8to16("Hello")
if (not StringUtf16) then
  error(ErrorString)
end

local StringUtf8, ErrorString = win32.utf16to8(StringUtf16)
if (not StringUtf8) then
  error(ErrorString)
end

print(StringUtf8)
```

pointertostring

```lua
local libffi = require("com.ffi")
local win32  = require("com.win32")

-- @BEGIN FfiDeclarations("BindLibrary", "libffi")
-- void *GetCommandLineW(void);
-- @OUTPUT
-- Functions
local GetCommandLineW
-- Binding function
local function BindLibrary (Library)
  GetCommandLineW = Library:bind(libffi.pointer, "GetCommandLineW")
end
-- @END

local Kernel32 = libffi.loadlib("kernel32.dll")
BindLibrary(Kernel32)

local CommandLinePointer = GetCommandLineW()
local CommandLineUtf8    = win32.pointertostring(CommandLinePointer, "utf16", "utf8")
print(CommandLineUtf8)
```

# Registry

## Functions

Functions to create, open and delete [registry keys](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry). `regsam` and `regoptions` calculate the union of the [Win32 constants](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights).

**Function** `regcreatekey(KeyPath, Sam, Options)` -> `KeyObject, ErrorString`

Create a key, or open it if it already exists.

* `Sam` is optional and defaults to `regsam("KEY_READ")`
* `Sam` values can be created with `regsam`
* `Options` is optional and defaults to `regoptions("REG_OPTION_NON_VOLATILE")`
* `Options` values can be created with `regoptions`
* Returns a [Key Object](#key-objects)

**Function** `regopenkey(KeyPath, Sam)` -> `KeyObject, ErrorString`

Open an existing key.

* `Sam` is optional and defaults to `regsam("KEY_READ")`
* `Sam` values can be created with `regsam`
* Returns a [Key Object](#key-objects)

**Function** `regdeletekey(KeyPath)` -> `Success, ErrorString`

**Function** `regsam(...)` -> `Integer`

Calculate an integer `Sam` value from the given strings:

* `"KEY_ALL_ACCESS"`
* `"KEY_CREATE_LINK"`
* `"KEY_CREATE_SUB_KEY"`
* `"KEY_ENUMERATE_SUB_KEYS"`
* `"KEY_EXECUTE"`
* `"KEY_NOTIFY"`
* `"KEY_QUERY_VALUE"`
* `"KEY_READ"`
* `"KEY_SET_VALUE"`
* `"KEY_WOW64_32KEY"`
* `"KEY_WOW64_64KEY"`
* `"KEY_WRITE"`

**Function** `regoptions(...)` -> `Integer`

Calculate an integer `Options` value from the given strings:

* `"REG_OPTION_NON_VOLATILE"`
* `"REG_OPTION_VOLATILE"`
* `"REG_OPTION_CREATE_LINK"`
* `"REG_OPTION_BACKUP_RESTORE"`

## Examples

Create a key with a custom `Sam` and `Options`

```lua
local win32 = require("com.win32")

local Sam     = win32.regsam("KEY_ALL_ACCESS")
local Options = win32.regoptions("REG_OPTION_VOLATILE", "REG_OPTION_CREATE_LINK")

local Key, ErrorString = win32.regcreatekey("HKEY_CURRENT_USER\\Software\\MyApplication", Sam, Options)
```

# Key objects

## Methods

**Method** `get(Name)` -> `Value, Type, ErrorString`

| `Type`                                                               | `Value`            |
|----------------------------------------------------------------------|--------------------|
| `"REG_SZ"`, `"REG_EXPAND_SZ"`                                        | String             |
| `"REG_BINARY"`                                                       | String (raw bytes) |
| `"REG_MULTI_SZ"`                                                     | Array of strings   |
| `"REG_DWORD"`, `"REG_DWORD_LITTLE_ENDIAN"`, `"REG_DWORD_BIG_ENDIAN"` | Number             |
| `"REG_QWORD"`, `"REG_QWORD_LITTLE_ENDIAN"`                           | Number             |
| `"REG_NONE"`                                                         | `nil`              |
| `"REG_LINK"`                                                         | Not supported      |
| `"REG_RESOURCE_LIST"`                                                | Not supported      |
| `"REG_FULL_RESOURCE_DESCRIPTOR"`                                     | Not supported      |
| `"REG_RESOURCE_REQUIREMENTS_LIST"`                                   | Not supported      |

**Method** `set(Name, Value, Type)` -> `Success, ErrorString`

* The `Type` has the same meaning as in the `get` method

**Method** `delete(Name)` -> `Success, ErrorString`

**Method** `flush()` -> `Success, ErrorString`

Write pending changes to disk.

**Method** `values()` -> `Iterator`

* Returns `Type, Name, Value` at each step

**Method** `keys()` -> `Iterator`

* Returns the subkey name at each step

**Method** `open(Name, Sam)` -> `KeyObject, ErrorString`

**Method** `create(Name, Sam, Options)` -> `KeyObject, ErrorString`

**Method** `close()` -> `Success, ErrorString`

## Examples

Read a value

```lua
local win32 = require("com.win32")

local Key, ErrorString = win32.regopenkey("HKEY_CURRENT_USER\\Volatile Environment")
if Key then
  local Value, Type = Key:get("USERNAME")
  print(Value, Type)
  Key:close()
end
```

Create a key and write values

```lua
local win32 = require("com.win32")

local KeyPath          = "HKEY_CURRENT_USER\\Software\\MyApplication"
local Sam              = win32.regsam("KEY_ALL_ACCESS")
local Key, ErrorString = win32.regcreatekey(KeyPath, Sam)
if Key then
  Key:set("Version", "1.0", "REG_SZ")
  Key:set("Installed", 1, "REG_DWORD")
  Key:close()
end
```

Iterate over the values

```lua
local win32 = require("com.win32")

local Key, ErrorString = win32.regopenkey("HKEY_CURRENT_USER\\Software\\MyApplication")
if Key then
  for Type, Name, Value in Key:values() do
    print(Type, Name, Value)
  end
  Key:close()
end
```

Iterate over the subkeys

```lua
local win32 = require("com.win32")

local Key, ErrorString = win32.regopenkey("HKEY_CURRENT_USER\\Software\\MyApplication")
if Key then
  for SubKeyName in Key:keys() do
    print(SubKeyName)
  end
  Key:close()
end
```

Delete a key

```lua
local win32 = require("com.win32")

local Success, ErrorString = win32.regdeletekey("HKEY_CURRENT_USER\\Software\\MyApplication")
print(Success, ErrorString)
```

# Dialogs

## Functions

**Function** `messagebox(Hwnd, Text, Title, Type, Icon)` -> `ButtonString`

Display a [message box](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-messageboxw).

* `Hwnd` is the Win32 parent window. It can be `nil`
* `Text` and `Title` are UTF-8 strings
* `Title` defaults to `"Message"`
* Accepted values for `Type`: `"OK"` (default), `"OKCANCEL"`, `"YESNO"`, `"YESNOCANCEL"`
* Accepted values for `Icon`: `"NONE"`, `"INFORMATION"`, `"WARNING"`, `"ERROR"`, `"QUESTION"`, `nil` (default)
* `ButtonString` is the pressed button: `"ok"`, `"cancel"`, `"yes"` or `"no"`

## Examples

Display a message box

```lua
local win32 = require("com.win32")

local Button = win32.messagebox(nil, "Save the changes?", "My Application", "YESNO", "QUESTION")
if (Button == "yes") then
  print("Saving")
else
  print("Not saving")
end
```

# ShellExecute

## Functions

**Function** `shellexecute(Verb, File, Params, Dir, ShowCmd, WaitForProcess)` -> `Success, ExitCode, ErrorString`

Launch an application, a document or a URI.

* `Verb` is the operation (`"open"`, `"runas"`, `"explore"`, `"find"`, etc.)
* `File` is the file, application or URI
* `Params`, `Dir` and `ShowCmd` are optional
* Accepted values for `ShowCmd`:
  * `"SW_HIDE"`
  * `"SW_SHOWNORMAL"`
  * `"SW_NORMAL"` (default)
  * `"SW_SHOWMINIMIZED"`
  * `"SW_SHOWMAXIMIZED"`
  * `"SW_MAXIMIZE"`
  * `"SW_SHOWNOACTIVATE"`
  * `"SW_SHOW"`
  * `"SW_MINIMIZE"`
  * `"SW_SHOWMINNOACTIVE"`
  * `"SW_SHOWNA"`
  * `"SW_RESTORE"`
  * `"SW_SHOWDEFAULT"`
  * `"SW_FORCEMINIMIZE"`
* `WaitForProcess` defaults to `true`. The function then waits for the process and returns its exit code

**Function** `openbrowser(Uri)` -> `Success, ErrorString`

`openbrowser` is a specialized call to `shellexecute` that opens a URI in the default browser.

## Examples

Open the user profile directory

```lua
local win32 = require("com.win32")

local UserProfile, ErrorString = win32.expandstrings("%USERPROFILE%")
local Success, ExitCode, ErrorString = win32.shellexecute("open", UserProfile)
print(Success, ExitCode, ErrorString)
```

Open Explorer with administrator privileges

```lua
local win32 = require("com.win32")

local Success, ExitCode, ErrorString = win32.shellexecute("runas", "explorer.exe")
print(Success, ExitCode, ErrorString)
```

Open a URI in the default browser

```lua
local win32 = require("com.win32")

local Success, ErrorString = win32.openbrowser("https://github.com")
print(Success, ErrorString)
```

# Utilities

## Functions

**Function** `getlasterror()` -> `ErrorCode`

Return the error code of the last Win32 call.

**Function** `formatmessage(ErrorCode)` -> `MessageString`

Format a Win32 error code into a readable message string.

**Function** `expandstrings(StringUtf8)` -> `ExpandedString, ErrorString`

Expand environment variables.

## Examples

Error handling

**[test-win32-formatmessage.lua](../tests/examples/ffi/test-win32-formatmessage.lua)**

```lua
local libffi = require("com.ffi")
local win32  = require("com.win32")

-- @BEGIN FfiDeclarations("BindLibrary", "libffi")
-- int CopyFileA(void *Source, void *Target, int FailIfExists);
-- @OUTPUT
-- Functions
local CopyFileA
-- Binding function
local function BindLibrary (Library)
  CopyFileA = Library:bind(libffi.sint32, "CopyFileA", libffi.pointer, libffi.pointer, libffi.sint32)
end
-- @END

local Kernel32 = libffi.loadlib("kernel32.dll")
BindLibrary(Kernel32)

if (CopyFileA("Z:\\this-file-does-not-exist.txt", "C:\\target.txt", 0) == 0) then
  local ErrorCode = win32.getlasterror()
  print(win32.formatmessage(ErrorCode))
  print("TEST PASSED")
else
  error("CopyFileA should have failed")
end
```

Environment variables

```lua
local win32 = require("com.win32")

local ExpandedString, ErrorString = win32.expandstrings("%USERPROFILE%")
print(ExpandedString)
```

# Technical notes

## luv vs ComEXE conversion

The embedded `luv` library provides UTF conversion functions:
* [wtf8_to_utf16](https://github.com/luvit/luv/blob/master/docs/docs.md#uvwtf8_to_utf16wtf8)
* [utf16_to_wtf8](https://github.com/luvit/luv/blob/master/docs/docs.md#uvutf16_to_wtf8utf16)

The luv documentation states:

> Luv uses Lua-style strings, which means that all inputs and return values (UTF-8 or UTF-16 strings) do not include a NUL terminator.

Lua adds a single NUL character to each string for C compatibility. UTF-16 strings created by `luv` are not NUL terminated, which can lead to crashes in Win32 functions.

Summary for the string `"TEST"`:

| Creator               | Resulting string in Lua memory                      | Comment                                                 |
|-----------------------|-----------------------------------------------------|---------------------------------------------------------|
| `utf16_to_wtf8` (luv) | `\x54\x45\x53\x54\x00`                              | OK, compatible with C                                   |
| `utf16to8`            | `\x54\x45\x53\x54\x00`                              | OK, compatible with C                                   |
| `wtf8_to_utf16` (luv) | `\x54\x00 \x45\x00 \x53\x00 \x54\x00 \x00`          | Unsafe: only `\x00` from Lua, not the UTF-16 `\x00\x00` |
| `utf8to16`            | `\x54\x00 \x45\x00 \x53\x00 \x54\x00 \x00\x00 \x00` | OK: UTF-16 NUL `\x00\x00` plus the Lua NUL              |

## Sleep

[Sleep](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-sleep) is not provided. The recommended way is to use the [luv module](https://github.com/luvit/luv/blob/master/docs/docs.md#uvsleepmsec).

Example:

```lua
local uv = require("luv")

-- Pause for 1 second
uv.sleep(1000)
```
