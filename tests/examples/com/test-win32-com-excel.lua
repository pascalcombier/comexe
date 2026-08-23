local EasyCom = require("com.win32.easycom")

local Filename = "test-win32-excel.xlsx"
local Excel    = EasyCom.newobject("Excel.Application")

if Excel then
  -- Configure Excel
  Excel:set("DisplayAlerts", false) -- Suppress confirmation dialogs
  Excel:set("Visible",       true)  -- Show the Excel window
  -- Add a new workbook
  local Workbooks   = Excel:get("Workbooks")
  local Workbook    = Workbooks:call("Add")
  local ActiveSheet = Excel:get("ActiveSheet")
  -- Simple write header
  ActiveSheet:get("Range", "A1"):set("Value", "Lua string")
  ActiveSheet:get("Range", "A2"):set("Value", "Lua integer")
  ActiveSheet:get("Range", "A3"):set("Value", "Lua number")
  ActiveSheet:get("Range", "A4"):set("Value", "Lua boolean true")
  ActiveSheet:get("Range", "A5"):set("Value", "Lua boolean false")
  ActiveSheet:get("Range", "A6"):set("Value", "Lua nil")
  ActiveSheet:get("Range", "A7"):set("Value", "Date")
  -- Simple write values
  ActiveSheet:get("Range", "B1"):set("Value", "Hello World!")
  ActiveSheet:get("Range", "B2"):set("Value", 123)
  ActiveSheet:get("Range", "B3"):set("Value", 123.456)
  ActiveSheet:get("Range", "B4"):set("Value", true)
  ActiveSheet:get("Range", "B5"):set("Value", false)
  ActiveSheet:get("Range", "B6"):set("Value", false)
  ActiveSheet:get("Range", "B6"):set("Value", nil)
  -- Write date
  local ExcelDate   = EasyCom.datetonumber("2024-03-14 15:30:45")
  local DateVariant = EasyCom.newvariant(ExcelDate, "VT_DATE")
  ActiveSheet:get("Range", "B7"):set("Value", DateVariant)
  -- Columns AutoFit
  ActiveSheet:get("Columns", "A"):call("AutoFit")
  ActiveSheet:get("Columns", "B"):call("AutoFit")
  -- Read simple values back
  print("READ B1", ActiveSheet:get("Range", "B1"):get("Value"))
  print("READ B2", ActiveSheet:get("Range", "B2"):get("Value"))
  print("READ B3", ActiveSheet:get("Range", "B3"):get("Value"))
  print("READ B4", ActiveSheet:get("Range", "B4"):get("Value"))
  print("READ B5", ActiveSheet:get("Range", "B5"):get("Value"))
  print("READ B6", ActiveSheet:get("Range", "B6"):get("Value"))
  print("READ B7", ActiveSheet:get("Range", "B7"):get("Value"))
  -- Interpret dates number: convert with Excel functions 
  local WorksheetFunction = Excel:get("WorksheetFunction")
  local DateValue         = ActiveSheet:get("Range", "B7"):get("Value")
  local IsoString, TypeName, ErrorString = WorksheetFunction:call("Text", DateValue, "yyyy-mm-dd hh:mm:ss")
  print("DATE", IsoString, "(expected 2024-03-14 15:30:45)")
  -- Write data in Lua (1D table, all the values of column A, then column B, then column C, etc)
  local Data = {}
  for ColIndex = 1, 10 do
    for RowIndex = 1, 20 do
      local Value = string.format("Row-%02d-Col-%02d", RowIndex, ColIndex)
      table.insert(Data, Value)
    end
  end
  -- Write the Lua data in the C-side SAFEARRAY (20 rows, 10 columns)
  local SafeArray = EasyCom.newsafearray("VT_VARIANT", 1, 20, 1, 10)
  SafeArray:write(Data)
  -- Write the SAFEARRAY to Excel sheet
  ActiveSheet:get("Range", "D2:M21"):set("Value", SafeArray)
  -- AutoFit the columns D to M
  ActiveSheet:get("Columns", "D:M"):call("AutoFit")
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
