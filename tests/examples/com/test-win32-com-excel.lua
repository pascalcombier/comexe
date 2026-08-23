local EasyCom = require("com.win32.easycom")

local Filename = "test-win32-excel.xlsx"
local Excel    = EasyCom.newobject("Excel.Application")

-- Excel alignment constants
local xlLeft   = -4131
local xlCenter = -4108
local xlRight  = -4152

-- Euro currency format, France locale (LCID 0x40C)
local EuroFormat = "[$€-40C]#,##0.00"

if Excel then
  -- Configure Excel
  Excel:set("DisplayAlerts", false) -- Suppress confirmation dialogs
  Excel:set("Visible",       true)  -- Show the Excel window
  -- Add a new workbook
  local Workbooks   = Excel:get("Workbooks")
  local Workbook    = Workbooks:call("Add")
  local ActiveSheet = Excel:get("ActiveSheet")
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
  -- Write date
  local ExcelDate   = EasyCom.datetonumber("2024-03-14 15:30:45")
  local DateVariant = EasyCom.newvariant(ExcelDate, "VT_DATE")
  ActiveSheet:get("Range", "B7"):set("Value", DateVariant)
  -- Write currency
  local CurrencyVariant = EasyCom.newvariant(1234.56, "VT_CY")
  ActiveSheet:get("Range", "B8"):set("Value", CurrencyVariant)
  ActiveSheet:get("Range", "B8"):set("NumberFormat", EuroFormat)
  -- Read single cells / simple values
  for Index = 1, 9 do
    local Address         = string.format("B%d", Index)
    local Value, TypeName = ActiveSheet:get("Range", Address):get("Value")
    print(string.format("READ B%d %-8s LuaValue=%s", Index, TypeName, Value))
  end
  -- Read and format dates with Excel functions
  local DateValue         = ActiveSheet:get("Range", "B7"):get("Value")
  local WorksheetFunction = Excel:get("WorksheetFunction")
  local IsoDateString     = WorksheetFunction:call("Text", DateValue, "yyyy-mm-dd hh:mm:ss")
  print("DATE", IsoDateString, "(expected 2024-03-14 15:30:45)")
  -- Read currency as string
  local CurrencyText, TypeName, ErrorString = ActiveSheet:get("Range", "B8"):get("Text")
  print("CURRENCY", CurrencyText)
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
  -- Column Alignment and AutoFit
  ActiveSheet:get("Columns", "B"):set("HorizontalAlignment", xlRight)
  ActiveSheet:get("Columns", "A:M"):call("AutoFit")
  -- Read the SAFEARRAY of cell values
  local SafeArray = ActiveSheet:get("Range", "A1:B8"):get("Value")
  local ReadTable = SafeArray:newtable()
  print("SAFEARRAY SIZE", #ReadTable)
  -- Copy the SAFEARRAY values into the Lua table (1D)
  SafeArray:read(ReadTable)
  for Index, Value in pairs(ReadTable) do
    print("SAFEARRAY", Index, Value)
  end
  -- Save the Excel file
  local Success, TypeName, ErrorString = Workbook:call("SaveAs", Filename)
  if Success then
    -- Retrieve where is the file written
    local FullName = Workbook:get("FullName")
    print(string.format("Saved to %s", FullName))
  else
    print(string.format("ERROR: SaveAs failed: %s", ErrorString))
  end
  Excel:call("Quit")
  if not Success then
    os.exit(1)
  end
end
