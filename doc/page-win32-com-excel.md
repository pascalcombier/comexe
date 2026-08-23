# Using Easycom with Excel

* [Overview](#overview)
  * [Initialization](#initialization)
  * [IDispatch objects](#idispatch-objects)
  * [Type conversions](#type-conversions)
* [Writing single cells](#writing-single-cells)
  * [Writing simple values](#writing-simple-values)
  * [Writing dates](#writing-dates)
  * [Writing currencies](#writing-currencies)
* [Reading single cells](#reading-single-cells)
  * [Reading simple values](#reading-simple-values)
  * [Reading dates](#reading-dates)
  * [Reading currencies](#reading-currencies)
* [Reading and writing multiple cells with SafeArrays](#reading-and-writing-multiple-cells-with-safearrays)
  * [Writing](#writing)
  * [Reading](#reading)
* [Saving Excel file and closing](#saving-excel-file-and-closing)
* [Full listing](#full-listing)
* [Troubleshooting](#troubleshooting)

# Overview

The module `com.win32.easycom` exposes an API to control other programs through COM Automation: Microsoft Excel, Word, PowerPoint, etc. This module is Windows-only. Each application exposes its objects under a `ProgID`:

| Application          | ProgID                   | Documentation                                                                                   |
|----------------------|--------------------------|-------------------------------------------------------------------------------------------------|
| Microsoft Excel      | `Excel.Application`      | [Excel object model](https://learn.microsoft.com/en-us/office/vba/api/overview/excel)           |
| Microsoft Word       | `Word.Application`       | [Word object model](https://learn.microsoft.com/en-us/office/vba/api/overview/word)             |
| Microsoft PowerPoint | `PowerPoint.Application` | [PowerPoint object model](https://learn.microsoft.com/en-us/office/vba/api/overview/powerpoint) |
| Microsoft Outlook    | `Outlook.Application`    | [Outlook object model](https://learn.microsoft.com/en-us/office/vba/api/overview/outlook)       |
| Microsoft Access     | `Access.Application`     | [Access object model](https://learn.microsoft.com/en-us/office/vba/api/overview/access)         |

Many more COM components are available. This page focuses on Microsoft Excel and requires Excel to be installed.

## Initialization

`newobject(ProgId)` creates an instance of a registered COM class from its ProgID, or returns `nil` if the class is not registered. The returned object wraps an `IDispatch` interface.

```lua
local EasyCom = require("com.win32.easycom")
local Win32   = require("com.win32")

local Excel = EasyCom.newobject("Excel.Application")

if Excel then
  Excel:set("Visible", true) -- Show the Excel window
  -- Excel:call("XXX")       -- Do something
  Excel:call("Quit")         -- Quit
else
  Win32.messagebox(nil, "Failed to create Excel.Application, Excel might not be installed properly.", "Error", "OK", "ERROR")
  os.exit(1)
end
```

## IDispatch objects

Objects created by `EasyCom.newobject` expose **COM properties** and **COM methods**:

| Method                          | Description      |
|---------------------------------|------------------|
| `Object:get("Property", ...)`   | Read a property  |
| `Object:set("Property", Value)` | Write a property |
| `Object:call("Method", ...)`    | Call a method    |

Every call returns `Value, TypeName, ErrorString`. `TypeName` is a string naming a [VARENUM](https://learn.microsoft.com/en-us/windows/win32/api/wtypes/ne-wtypes-varenum) value, for example:

| TypeName         | Meaning                               |
|------------------|---------------------------------------|
| `"VT_EMPTY"`     | No value                              |
| `"VT_NULL"`      | Null value                            |
| `"VT_I4"`        | 32-bit signed integer                 |
| `"VT_R4"`        | 32-bit floating-point number          |
| `"VT_R8"`        | 64-bit floating-point number          |
| `"VT_CY"`        | Currency                              |
| `"VT_DATE"`      | Date, number of days since 1899-12-30 |
| `"VT_BSTR"`      | Unicode string, UTF-16                |
| `"VT_DISPATCH"`  | COM object, `IDispatch`               |
| `"VT_BOOL"`      | Boolean                               |
| `"VT_VARIANT"`   | Variant                               |
| `"VT_UNKNOWN"`   | COM object, `IUnknown`                |
| `"VT_DECIMAL"`   | Decimal                               |
| `"VT_UI4"`       | 32-bit unsigned integer               |
| `"VT_I8"`        | 64-bit signed integer                 |
| `"VT_UI8"`       | 64-bit unsigned integer               |
| `"VT_INT"`       | Signed integer                        |
| `"VT_UINT"`      | Unsigned integer                      |
| `"VT_VOID"`      | Void                                  |
| `"VT_SAFEARRAY"` | SafeArray                             |
| `"VT_LPSTR"`     | ANSI string pointer                   |
| `"VT_LPWSTR"`    | Unicode string pointer                |

`TypeName` can also refer to containers:

| Container                 | C expression           | `TypeName` string        |
|---------------------------|------------------------|--------------------------|
| Vector of 32-bit unsigned | `VT_VECTOR\|VT_UI4`    | `"VT_VECTOR\|VT_UI4"`    |
| SafeArray of variants     | `VT_ARRAY\|VT_VARIANT` | `"VT_ARRAY\|VT_VARIANT"` |
| Pointer to 32-bit integer | `VT_BYREF\|VT_I4`      | `"VT_BYREF\|VT_I4"`      |

Properties and methods may return new **IDispatch objects**:

```lua
local Workbooks   = Excel:get("Workbooks")
local Workbook    = Workbooks:call("Add")
local ActiveSheet = Excel:get("ActiveSheet")
```

Calls can be chained:

```lua
ActiveSheet:get("Range", "B1"):set("Value", "Hello World!")
```

## Type conversions

When called, COM properties and COM methods automatically convert Lua values to COM values:

| Lua value                     | COM type               | Comment                                                                                          |
|-------------------------------|------------------------|--------------------------------------------------------------------------------------------------|
| `string`                      | `VT_BSTR`              | UTF-8, converted to UTF-16 when written; read back as UTF-8                                      |
| `integer`                     | `VT_I4`                | Numbers like `123`, detected with `math.tointeger`                                               |
| `number`                      | `VT_R8`                | Numbers like `123.456`                                                                           |
| `boolean`                     | `VT_BOOL`              | `true` or `false`                                                                                |
| `nil`                         | `VT_NULL`              | Empty cell                                                                                       |
| Dispatch object               | `VT_DISPATCH`          | A Dispatch object returned by `get` or `call`                                                    |
| SafeArray object              | `VT_ARRAY\|VT_VARIANT` | Created by `newsafearray`, see [SafeArrays](#reading-and-writing-multiple-cells-with-safearrays) |
| `newvariant(Value, TypeName)` | User-specified         | Useful for [writing dates](#writing-dates) and [writing currencies](#writing-currencies)         |

# Writing single cells

## Writing simple values

Excel's cells are written by setting the `Value` property of a given `Range`:

```lua
-- Simple write header
ActiveSheet:get("Range", "A1"):set("Value", "UTF-8 string")
ActiveSheet:get("Range", "A2"):set("Value", "Lua integer")
ActiveSheet:get("Range", "A3"):set("Value", "Lua number")
ActiveSheet:get("Range", "A4"):set("Value", "Lua boolean true")
ActiveSheet:get("Range", "A5"):set("Value", "Lua boolean false")
ActiveSheet:get("Range", "A6"):set("Value", "Lua nil")
ActiveSheet:get("Range", "A7"):set("Value", "Date")
ActiveSheet:get("Range", "A8"):set("Value", "Currency")
-- Simple write values
ActiveSheet:get("Range", "B1"):set("Value", "Voilà €")
ActiveSheet:get("Range", "B2"):set("Value", 123)
ActiveSheet:get("Range", "B3"):set("Value", 123.456)
ActiveSheet:get("Range", "B4"):set("Value", true)
ActiveSheet:get("Range", "B5"):set("Value", false)
ActiveSheet:get("Range", "B6"):set("Value", false)
ActiveSheet:get("Range", "B6"):set("Value", nil) -- overwrite
```

## Writing dates

Excel stores dates as the number of days since December 30, 1899, plus the time as a fraction of a day. `datetonumber(IsoString)` converts an ISO date string to that number, as a plain Lua `number`. To write a date in a cell, wrap it with `newvariant(Value, "VT_DATE")`:

```lua
local ExcelDate   = EasyCom.datetonumber("2024-03-14 15:30:45")
local DateVariant = EasyCom.newvariant(ExcelDate, "VT_DATE")
ActiveSheet:get("Range", "B7"):set("Value", DateVariant)
```

## Writing currencies

A currency value is written with `newvariant(Value, "VT_CY")`:

```lua
-- Set the value
local CurrencyVariant = EasyCom.newvariant(1234.56, "VT_CY")
ActiveSheet:get("Range", "B8"):set("Value", CurrencyVariant)

-- Set the display format
-- Euro currency format, France locale (LCID 0x40C)
local EuroFormat = "[$€-40C]#,##0.00"
ActiveSheet:get("Range", "B8"):set("NumberFormat", EuroFormat)
```

The cell displays `€1,234.56`. Reading the value back returns `1234.56`.

# Reading single cells

## Reading simple values

Excel's cells are read by getting the `Value` property of a given `Range`:

```lua
-- Read single cells / simple values
for Index = 1, 9 do
  local Address         = string.format("B%d", Index)
  local Value, TypeName = ActiveSheet:get("Range", Address):get("Value")
  print(string.format("READ B%d %-8s LuaValue=%s", Index, TypeName, Value))
end
```

Output

```
READ B1 VT_BSTR  LuaValue=Voilà €
READ B2 VT_R8    LuaValue=123.0
READ B3 VT_R8    LuaValue=123.456
READ B4 VT_BOOL  LuaValue=true
READ B5 VT_BOOL  LuaValue=false
READ B6 VT_EMPTY LuaValue=nil
READ B7 VT_DATE  LuaValue=45365.646354166667
READ B8 VT_R8    LuaValue=1234.56
READ B9 VT_EMPTY LuaValue=nil
```

The read values may differ from the written ones:

| Lua value | Written                               | Read value           | Read TypeName |
|-----------|---------------------------------------|----------------------|---------------|
| Integer   | `123`                                 | `123.0`              | `"VT_R8"`     |
| Date      | `datetonumber("2024-03-14 15:30:45")` | `45365.646354166667` | `"VT_DATE"`   |
| Currency  | `newvariant(1234.56, "VT_CY")`        | `1234.56`            | `"VT_R8"`     |

Excel stores every numeric cell as a double. When read with `Value`, Excel converts date cells to `VT_DATE`, while currency cells are returned as `VT_R8`.

## Reading dates

Dates are read as numbers. To format a date as a string, use the Excel `Text` function:

```lua
-- Read and format dates with Excel functions
local DateValue         = ActiveSheet:get("Range", "B7"):get("Value")
local WorksheetFunction = Excel:get("WorksheetFunction")
local IsoDateString     = WorksheetFunction:call("Text", DateValue, "yyyy-mm-dd hh:mm:ss")
print("DATE", IsoDateString, "(expected 2024-03-14 15:30:45)")
```

Output

```
DATE    2024-03-14 15:30:45     (expected 2024-03-14 15:30:45)
```

## Reading currencies

Currencies are read as numbers. The displayed text is available through the `Text` property of the range:

```lua
-- Read currency as string
local CurrencyText, TypeName, ErrorString = ActiveSheet:get("Range", "B8"):get("Text")
print("CURRENCY", CurrencyText)
```

Output

```
CURRENCY        €1,234.56
```

# Reading and writing multiple cells with SafeArrays

Reading and writing single cells is slow for large amounts of data. Using a `SAFEARRAY` is faster.

## Writing

```lua
-- Write data in Lua (1D table, all the values of column A, then column B, then column C, etc)
local Data = {}
for ColIndex = 1, 10 do
  for RowIndex = 1, 20 do
    local Value = string.format("Row-%02d-Col-%02d", RowIndex, ColIndex)
    table.insert(Data, Value)
  end
end
-- Write the Lua data into the C-side SAFEARRAY (20 rows, 10 columns)
local SafeArray = EasyCom.newsafearray("VT_VARIANT", 1, 20, 1, 10)
SafeArray:write(Data)
-- Write the SAFEARRAY to Excel sheet
ActiveSheet:get("Range", "D2:M21"):set("Value", SafeArray)
```

The Lua table follows the `SAFEARRAY` memory order: all rows of column 1 first, then column 2, and so on.

## Reading

Getting the value of a multi-cell range returns a `SAFEARRAY`:

```lua
-- Read the SAFEARRAY of cell values
local SafeArray = ActiveSheet:get("Range", "A1:B8"):get("Value")
```

`SafeArray:newtable()` returns a Lua table of the right size and `SafeArray:read(Table)` fills it.

```lua
local ReadTable = SafeArray:newtable()
print("SAFEARRAY SIZE", #ReadTable)
-- Copy the SAFEARRAY values into the Lua table (1D)
SafeArray:read(ReadTable)
for Index, Value in pairs(ReadTable) do
  print("SAFEARRAY", Index, Value)
end
```

Output

```
SAFEARRAY SIZE  16
SAFEARRAY       1       UTF-8 string
SAFEARRAY       2       Lua integer
SAFEARRAY       3       Lua number
SAFEARRAY       4       Lua boolean true
SAFEARRAY       5       Lua boolean false
SAFEARRAY       6       Lua nil
SAFEARRAY       7       Date
SAFEARRAY       8       Currency
SAFEARRAY       9       Voilà €
SAFEARRAY       10      123.0
SAFEARRAY       11      123.456
SAFEARRAY       12      true
SAFEARRAY       13      false
SAFEARRAY       15      45365.646354166667
SAFEARRAY       16      1234.56
```

The example uses `pairs` instead of `ipairs` because index 14 is `nil`.

# Saving Excel file and closing

The workbook is saved with `SaveAs`:

```lua
local Success, TypeName, ErrorString = Workbook:call("SaveAs", Filename)
if Success then
  -- Retrieve where is the file written
  local FullName = Workbook:get("FullName")
  print(string.format("Saved to %s", FullName))
else
  print(string.format("ERROR: SaveAs failed: %s", ErrorString))
end
Excel:call("Quit")
```

# Full listing

Complete example

**[test-win32-com-excel.lua](../tests/examples/com/test-win32-com-excel.lua)**

Output

```console
> lua55ce tests\examples\com\test-win32-excel.lua
READ B1 VT_BSTR  LuaValue=Voilà €
READ B2 VT_R8    LuaValue=123.0
READ B3 VT_R8    LuaValue=123.456
READ B4 VT_BOOL  LuaValue=true
READ B5 VT_BOOL  LuaValue=false
READ B6 VT_EMPTY LuaValue=nil
READ B7 VT_DATE  LuaValue=45365.646354166667
READ B8 VT_R8    LuaValue=1234.56
READ B9 VT_EMPTY LuaValue=nil
DATE    2024-03-14 15:30:45     (expected 2024-03-14 15:30:45)
CURRENCY        €1,234.56
SAFEARRAY SIZE  16
SAFEARRAY       1       UTF-8 string
SAFEARRAY       2       Lua integer
SAFEARRAY       3       Lua number
SAFEARRAY       4       Lua boolean true
SAFEARRAY       5       Lua boolean false
SAFEARRAY       6       Lua nil
SAFEARRAY       7       Date
SAFEARRAY       8       Currency
SAFEARRAY       9       Voilà €
SAFEARRAY       10      123.0
SAFEARRAY       11      123.456
SAFEARRAY       12      true
SAFEARRAY       13      false
SAFEARRAY       15      45365.646354166667
SAFEARRAY       16      1234.56
Saved to C:\Users\PASCAL\Documents\test-win32-excel.xlsx
```

# Troubleshooting

* `Workbook:call("SaveAs")` can fail if the Excel file is already open by another Excel instance. The error message is not very clear:

```console
ERROR: SaveAs failed: Invoke failed with HRESULT 0x800A03EC
```

Close the file in the other Excel instance, or save under a different filename.

* When reading a cell with `Range:get("Text")`, the value can come back as `"########"`. It matches what Excel displays when the column is too narrow. AutoFit the column before reading:

```lua
ActiveSheet:get("Columns", "A:M"):call("AutoFit")
```
