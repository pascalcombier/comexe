--------------------------------------------------------------------------------
-- TESTS BOILERPLATE FOR PACKAGE.PATH                                         --
--------------------------------------------------------------------------------

-- This kind of code should not appear in the real use of ComEXE
--
-- Initialize package.path to include ..\lib\xxx because test libraries are in
-- this directory

local function TEST_UpdatePackagePath (RelativeDirectory)
  -- Retrieve package confiuration (file loadlib.c, function luaopen_package)
  local Configuration = package.config
  local LUA_DIRSEP    = Configuration:sub(1, 1)
  local LUA_PATH_SEP  = Configuration:sub(3, 3)
  local LUA_PATH_MARK = Configuration:sub(5, 5)
  -- Load required modules
  local Runtime   = require("com.runtime")
  local Directory = Runtime.getrelativepath(RelativeDirectory) -- relative to arg[0] directory
  -- Prepend path in a Linux/Windows compatible way
  package.path = string.format("%s%s%s.lua%s%s", Directory, LUA_DIRSEP, LUA_PATH_MARK, LUA_PATH_SEP, package.path)
end

TEST_UpdatePackagePath("../lib")

--------------------------------------------------------------------------------
-- MODULE IMPORTS                                                             --
--------------------------------------------------------------------------------

local reporter = require("mini-reporter")
local com      = require("com.win32.easycom")

local format = string.format
local insert = table.insert

local newobject    = com.newobject
local newdate      = com.newdate
local newsafearray = com.newsafearray

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

local Reporter = reporter.new()

--------------------------------------------------------------------------------
-- TEST CASES                                                                 --
--------------------------------------------------------------------------------

function TestCom_001_WrongName (Filename)
  local Excel
  Excel = newobject("Test.NotExisting")
  Reporter:expect("WRONG-NAME-01", (Excel == nil))
  Excel = newobject("\x00\x00")
  Reporter:expect("WRONG-NAME-02", (Excel == nil))
  Excel = newobject("")
  Reporter:expect("WRONG-NAME-03", (Excel == nil))
  Excel = newobject(nil)
  Reporter:expect("WRONG-NAME-04", (Excel == nil))
  -- No file created
  return nil, nil
end

function TestCom_002_ExcelApi (Filename)
  -- New object
  local Excel = newobject("Excel.Application")
  Reporter:expect("EXCEL-API-001", Excel)
  
  -- Early exit
  if (not Excel) then
    Reporter:expect("EXCEL-API-002_EXIT", false)
    return nil, nil
  end

  -- Start
  local Value, Type, ErrorMessage = Excel:set("DisplayAlerts", false)
  Reporter:expect("EXCEL-API-002", (Value == nil))
  Reporter:expect("EXCEL-API-003", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-004", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = Excel:set("Visible", true)
  Reporter:expect("EXCEL-API-005", (Value == nil))
  Reporter:expect("EXCEL-API-006", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-007", (ErrorMessage == nil))

  local Workbooks, Type, ErrorMessage = Excel:get("Workbooks")
  Reporter:expect("EXCEL-API-008", (Workbooks ~= nil))
  Reporter:expect("EXCEL-API-009", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-010", (ErrorMessage == nil))

  if (not Workbooks) then
    Reporter:expect("EXCEL-API-011_EXIT", false)
    return nil, nil
  end

  local Workbook, Type, ErrorMessage = Workbooks:call("Add")
  Reporter:expect("EXCEL-API-011", (Workbook ~= nil))
  Reporter:expect("EXCEL-API-012", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-013", (ErrorMessage == nil))

  if (not Workbook) then
    Reporter:expect("EXCEL-API-014_EXIT", false)
    return nil, nil
  end

  local ActiveSheet, Type, ErrorMessage = Excel:get("ActiveSheet")
  Reporter:expect("EXCEL-API-014", (ActiveSheet ~= nil))
  Reporter:expect("EXCEL-API-015", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-016", (ErrorMessage == nil))

  if (not ActiveSheet) then
    Reporter:expect("EXCEL-API-017_EXIT", false)
    return nil, nil
  end

  local Sheets, Type, ErrorMessage = Workbook:get("Sheets")
  Reporter:expect("EXCEL-API-017", (Sheets ~= nil))
  Reporter:expect("EXCEL-API-018", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-019", (ErrorMessage == nil))

  if (not Sheets) then
    Reporter:expect("EXCEL-API-020_EXIT", false)
    return nil, nil
  end

  -- New sheet TestNewSheet1
  local NewActiveSheet, Type, ErrorMessage = Sheets:call("Add")
  Reporter:expect("EXCEL-API-020", (NewActiveSheet ~= nil))
  Reporter:expect("EXCEL-API-021", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-022", (ErrorMessage == nil))
  
  if NewActiveSheet then
  local Value, Type, ErrorMessage = NewActiveSheet:set("Name", "TestNewSheet1")
    Reporter:expect("EXCEL-API-023", (Value == nil))
    Reporter:expect("EXCEL-API-024", (ErrorMessage == nil))
    Reporter:expect("EXCEL-API-025", (Type == "VT_EMPTY"))
  end

  -- New sheet TestNewSheet2
  local NewActiveSheet, Type, ErrorMessage = Sheets:call("Add")
  Reporter:expect("EXCEL-API-026", ((NewActiveSheet ~= nil)))
  Reporter:expect("EXCEL-API-027", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-028", (ErrorMessage == nil))
  
  if NewActiveSheet then
  local Value, Type, ErrorMessage = NewActiveSheet:set("Name", "TestNewSheet2")
    Reporter:expect("EXCEL-API-029", (Value == nil))
    Reporter:expect("EXCEL-API-030", (ErrorMessage == nil))
    Reporter:expect("EXCEL-API-031", (Type == "VT_EMPTY"))
  end

  -- New sheet TestNewSheet3
  local NewActiveSheet, Type, ErrorMessage = Sheets:call("Add")
  Reporter:expect("EXCEL-API-032", (NewActiveSheet ~= nil))
  Reporter:expect("EXCEL-API-033", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-034", (ErrorMessage == nil))

  if NewActiveSheet then
  local Value, Type, ErrorMessage = NewActiveSheet:set("Name", "TestNewSheet3")
    Reporter:expect("EXCEL-API-035", (Value == nil))
    Reporter:expect("EXCEL-API-036", (ErrorMessage == nil))
    Reporter:expect("EXCEL-API-037", (Type == "VT_EMPTY"))
  end

  local function SetCellValue (Sheet, Address, Value)
  local Range, Type, ErrorMessage = Sheet:get("Range", Address)
    -- simplified prefix (uses Address which is stable and readable)
    local Prefix = format("EXCEL_API_038_%s", Address)
    Reporter:expect(format("%s_01", Prefix), (Range ~= nil))
    Reporter:expect(format("%s_02", Prefix), (Type == "VT_DISPATCH"))
    Reporter:expect(format("%s_03", Prefix), (ErrorMessage == nil))
    if (not Range) then
      Reporter:expect(format("%s_04_EXIT", Prefix), false)
      return false
    end
  local Value2, Type, ErrorMessage = Range:set("Value", Value)
    Reporter:expect(format("%s_04", Prefix), (Value2 == nil))
    Reporter:expect(format("%s_05", Prefix), (Type == "VT_EMPTY"))
    Reporter:expect(format("%s_06", Prefix), (ErrorMessage == nil))
    return true
  end
  
  -- Reselect Sheet1 
  if ActiveSheet then
    ActiveSheet:call("Activate")
  end
  -- Additional dates to test createdate
  local Date1String = "2024-03-14 15:30:45"
  local Date2String = "1899-12-30 15:30:45"
  local Date3String = "1900-01-01 15:30:45"
  local Date1       = { newdate(Date1String), "VT_DATE" }
  local Date2       = { newdate(Date2String), "VT_DATE" }
  local Date3       = { newdate(Date3String), "VT_DATE" }

  SetCellValue(ActiveSheet, "A1", "Type")
  SetCellValue(ActiveSheet, "B1", "Example of value")
  SetCellValue(ActiveSheet, "C1", "Comment")
  SetCellValue(ActiveSheet, "A2", "Basic string")
  SetCellValue(ActiveSheet, "B2", "Hello World! 你好")
  SetCellValue(ActiveSheet, "A3", "Integer")
  SetCellValue(ActiveSheet, "B3", 123)
  SetCellValue(ActiveSheet, "A4", "Real VT_R8")
  SetCellValue(ActiveSheet, "B4", 123.456)
  SetCellValue(ActiveSheet, "A5", "Date")
  SetCellValue(ActiveSheet, "B5", { 0.0, "VT_DATE" } )
  SetCellValue(ActiveSheet, "C5", "'0.0")
  SetCellValue(ActiveSheet, "A6", "ISO Date")
  SetCellValue(ActiveSheet, "B6", Date1)
  SetCellValue(ActiveSheet, "C6", format("'%s", Date1String))
  SetCellValue(ActiveSheet, "A7", "ISO Date")
  SetCellValue(ActiveSheet, "B7", Date2)
  SetCellValue(ActiveSheet, "C7", format("'%s", Date2String))
  SetCellValue(ActiveSheet, "A8", "ISO Date")
  SetCellValue(ActiveSheet, "B8", Date3)
  SetCellValue(ActiveSheet, "C8", format("'%s", Date3String))
  SetCellValue(ActiveSheet, "A9", "boolean")
  SetCellValue(ActiveSheet, "B9", true)
  SetCellValue(ActiveSheet, "A10", "boolean")
  SetCellValue(ActiveSheet, "B10", false)

  -- Select columns A to F
  local ColumnsRange, Type, ErrorMessage = ActiveSheet:get("Range", "A:C")
  Reporter:expect("EXCEL-API-039", (ColumnsRange ~= nil))
  Reporter:expect("EXCEL-API-040", (ErrorMessage == nil))
  Reporter:expect("EXCEL-API-041", (Type == "VT_DISPATCH"))

  -- Get the EntireColumn property and then auto-fit
  local EntireColumn, Type, ErrorMessage = ColumnsRange:get("EntireColumn")
  Reporter:expect("EXCEL-API-042", (EntireColumn ~= nil))
  Reporter:expect("EXCEL-API-043", (ErrorMessage == nil))
  Reporter:expect("EXCEL-API-044", (Type == "VT_DISPATCH"))

  local Value, Type, ErrorMessage = EntireColumn:call("AutoFit")
  Reporter:expect("EXCEL-API-045", (Value ~= nil))
  Reporter:expect("EXCEL-API-046", (ErrorMessage == nil))
  Reporter:expect("EXCEL-API-047", (Type == "VT_BOOL"))
  -- Example for chart

  SetCellValue(ActiveSheet, "E1", "Jan")
  SetCellValue(ActiveSheet, "F1", "Feb")
  SetCellValue(ActiveSheet, "G1", "Mar")
  SetCellValue(ActiveSheet, "H1", "Apr")

  SetCellValue(ActiveSheet, "D2", "Type1")
  SetCellValue(ActiveSheet, "D3", "Type2")
  SetCellValue(ActiveSheet, "D4", "Type3")
  SetCellValue(ActiveSheet, "D5", "Sum")

  -- Type 1
  SetCellValue(ActiveSheet, "E2", 100)
  SetCellValue(ActiveSheet, "F2",  80)
  SetCellValue(ActiveSheet, "G2",  90)
  SetCellValue(ActiveSheet, "H2",  95)

  -- Type 2
  SetCellValue(ActiveSheet, "E3", 120)
  SetCellValue(ActiveSheet, "F3",  90)
  SetCellValue(ActiveSheet, "G3", 110)
  SetCellValue(ActiveSheet, "H3",  60)

  -- Type 3
  SetCellValue(ActiveSheet, "E4", 200)
  SetCellValue(ActiveSheet, "F4", 150)
  SetCellValue(ActiveSheet, "G4", 120)
  SetCellValue(ActiveSheet, "H4", 180)

  -- Add SUM formula in row 5
  SetCellValue(ActiveSheet, "E5", "=SUM(E2:E4)")
  SetCellValue(ActiveSheet, "F5", "=SUM(F2:F4)")
  SetCellValue(ActiveSheet, "G5", "=SUM(G2:G4)")
  SetCellValue(ActiveSheet, "H5", "=SUM(H2:H4)")

  SetCellValue(ActiveSheet, "J1", "Fill 2D Range Example")

  -- Create the 4x4 grid (starting at J2)
  local Range3, Type, ErrorMessage = ActiveSheet:get("Cells", 11, 2)   -- Row 11, Column 2 (B11)
  Reporter:expect("EXCEL-API-048", (Range3 ~= nil))
  Reporter:expect("EXCEL-API-049", (ErrorMessage == nil))
  Reporter:expect("EXCEL-API-050", (Type == "VT_DISPATCH"))

  local Range4, Type, ErrorMessage = ActiveSheet:get("Cells", 14, 5)   -- Row 14, Column 5 (E14)
  Reporter:expect("EXCEL-API-051", (Range4 ~= nil))
  Reporter:expect("EXCEL-API-052", (ErrorMessage == nil))
  Reporter:expect("EXCEL-API-053", (Type == "VT_DISPATCH"))

  local RangeGrid, Type, ErrorMessage = ActiveSheet:get("Range", Range3, Range4)
  Reporter:expect("EXCEL-API-054", (RangeGrid ~= nil))
  Reporter:expect("EXCEL-API-055", (ErrorMessage == nil))
  Reporter:expect("EXCEL-API-056", (Type == "VT_DISPATCH"))

  -- Create a 2D SafeArray for 4x4 grid (4 columns × 4 rows)
  local SafeArray = newsafearray("VT_VARIANT", 1, 4, 1, 4)
  Reporter:expect("EXCEL-API-058", (SafeArray ~= nil))

  -- Create test data table (4x4 array)
  local TestData = {
    101, 102, 103, 104,
    201, 202, 203, 204,
    301, 302, 303, 304,
    401, 402, 403, 404
  }
  local ElementCount = #TestData

  -- Set the data into SafeArray
  local Count = SafeArray:write(TestData)
  Reporter:expect("EXCEL-API-059", (Count == ElementCount))

  local Value, Type, ErrorMessage = RangeGrid:set("Value", SafeArray)
  Reporter:expect("EXCEL-API-060", (Value == nil))
  Reporter:expect("EXCEL-API-061", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-062", (ErrorMessage == nil))

  RangeGrid:call("Select")

  local RangeData, Type, ErrorMessage = RangeGrid:get("Value")

  local SafeArray = RangeData
  local ReadTable = SafeArray:newtable()

  local Count = SafeArray:read(ReadTable)
  Reporter:expect("EXCEL-API-063", (Count == ElementCount))

  for Index = 1, #ReadTable do
    Reporter:expect(format("EXCEL-API-064-%d", Index), (ReadTable[Index] == TestData[Index]))
  end

  local Dimensions = SafeArray:getdimensions()
  Reporter:expect("EXCEL-API-065", (Dimensions ~= nil))
  Reporter:expect("EXCEL-API-066", (#Dimensions == 2))
  Reporter:expect("EXCEL-API-067", (Dimensions[1][1] == 1))
  Reporter:expect("EXCEL-API-068", (Dimensions[1][2] == 4))
  Reporter:expect("EXCEL-API-069", (Dimensions[1][3] == 4))
  Reporter:expect("EXCEL-API-070", (Dimensions[2][1] == 1))
  Reporter:expect("EXCEL-API-071", (Dimensions[2][2] == 4))
  Reporter:expect("EXCEL-API-072", (Dimensions[2][3] == 4))

  -- Create chart
  local Charts, Type, ErrorMessage = Excel:get("Charts")
  Reporter:expect("EXCEL-API-073", (Charts ~= nil))
  Reporter:expect("EXCEL-API-074", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-075", (ErrorMessage == nil))

  -- Select the data range for the chart
  local DataRange, Type, ErrorMessage = ActiveSheet:get("Range", "D1:H4")
  Reporter:expect("EXCEL-API-076", (DataRange ~= nil))
  Reporter:expect("EXCEL-API-077", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-078", (ErrorMessage == nil))

  -- Add chart
  local Chart, Type, ErrorMessage = Charts:call("Add")
  Reporter:expect("EXCEL-API-079", (Chart ~= nil))
  Reporter:expect("EXCEL-API-080", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-081", (ErrorMessage == nil))

  -- Set chart type to column (bar chart)
  local xlColumnClustered = 51
  local Value, Type, ErrorMessage = Chart:set("ChartType", xlColumnClustered)
  Reporter:expect("EXCEL-API-082", (Value == nil))
  Reporter:expect("EXCEL-API-083", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-084", (ErrorMessage == nil))

  -- Set chart source data - using the proper method call
  local Value, Type, ErrorMessage = Chart:call("SetSourceData", DataRange)
  Reporter:expect("EXCEL-API-085", ((Value == nil)))
  Reporter:expect("EXCEL-API-086", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-087", (ErrorMessage == nil))

  -- Move the chart to the worksheet as an embedded object
  -- First get the Charts collection of the worksheet
  local WorksheetCharts, Type, ErrorMessage = ActiveSheet:call("ChartObjects")
  Reporter:expect("EXCEL-API-088", (WorksheetCharts ~= nil))
  Reporter:expect("EXCEL-API-089", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-090", (ErrorMessage == nil))

  -- Add a new chart object at position (200, 200, 450, 400)
  local ChartObject, Type, ErrorMessage = WorksheetCharts:call("Add", 200, 200, 450, 400)
  Reporter:expect("EXCEL-API-091", (ChartObject ~= nil))
  Reporter:expect("EXCEL-API-092", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-093", (ErrorMessage == nil))

  local Range, Type, ErrorMessage = ActiveSheet:get("Range", "D7")
  Reporter:expect("EXCEL-API-094", (Range ~= nil))
  Reporter:expect("EXCEL-API-095", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-096", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = ChartObject:set("TopLeftCell", Range)
  Reporter:expect("EXCEL-API-097", (Value == nil))
  Reporter:expect("EXCEL-API-098", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-099", (ErrorMessage == nil))

  -- Get the chart from the chart object
  local EmbeddedChart, Type, ErrorMessage = ChartObject:get("Chart")
  Reporter:expect("EXCEL-API-100", (EmbeddedChart ~= nil))
  Reporter:expect("EXCEL-API-101", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-102", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = EmbeddedChart:call("SetSourceData", DataRange)
  Reporter:expect("EXCEL-API-103", ((Value == nil)))
  Reporter:expect("EXCEL-API-104", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-105", (ErrorMessage == nil))

  -- Set chart title
  local Value, Type, ErrorMessage = EmbeddedChart:set("HasTitle", true)
  Reporter:expect("EXCEL-API-106", (Value == nil))
  Reporter:expect("EXCEL-API-107", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-108", (ErrorMessage == nil))

  local ChartTitle, Type, ErrorMessage = EmbeddedChart:get("ChartTitle")
  Reporter:expect("EXCEL-API-109", (ChartTitle ~= nil))
  Reporter:expect("EXCEL-API-110", (Type == "VT_DISPATCH"))
  Reporter:expect("EXCEL-API-111", (ErrorMessage == nil))
  
  if ChartTitle then
  local Value, Type, ErrorMessage = ChartTitle:set("Text", "Com API")
    Reporter:expect("EXCEL-API-112", (Value == nil))
    Reporter:expect("EXCEL-API-113", (Type == "VT_EMPTY"))
    Reporter:expect("EXCEL-API-114", (ErrorMessage == nil))
  end

  -- Delete the original chart sheet since we've moved it to the worksheet
  local Value, Type, ErrorMessage = Chart:call("Delete")
  Reporter:expect("EXCEL-API-115", Value)
  Reporter:expect("EXCEL-API-116", (Type == "VT_BOOL"))
  Reporter:expect("EXCEL-API-117", (ErrorMessage == nil))

  -- Save file and quit
  local Success, Type, ErrorMessage = Workbook:call("SaveAs", Filename)
  Reporter:expect("EXCEL-API-118", Success)
  Reporter:expect("EXCEL-API-119", (Type == "VT_BOOL"))
  Reporter:expect("EXCEL-API-120", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = Excel:call("Quit")
  Reporter:expect("EXCEL-API-121", (Value == nil))
  Reporter:expect("EXCEL-API-122", (Type == "VT_EMPTY"))
  Reporter:expect("EXCEL-API-123", (ErrorMessage == nil))

  return nil, nil
end

--[[

int ExcelSample1(void)
{
	DISPATCH_OBJ(xlApp);
	DISPATCH_OBJ(xlRange);
	DISPATCH_OBJ(xlChart);
	UINT i;
	const WCHAR * szHeadings[] = { L"Mammals", L"Birds", L"Reptiles", L"Fishes", L"Plants" };

	dhInitialize(TRUE);
	dhToggleExceptions(TRUE);

	HR_TRY( dhnewobject(L"Excel.Application", NULL, &xlApp) );

	dhPutValue(xlApp, L".DisplayFullScreen = %b", TRUE);
	dhPutValue(xlApp, L".Visible = %b", TRUE);

	/* xlApp.Workbooks.Add */
	HR_TRY( dhCallMethod(xlApp, L".Workbooks.Add") );

	/* Set the worksheet name */
	dhPutValue(xlApp, L".ActiveSheet.Name = %T", TEXT("Critically Endangered"));

	/* Add the column headings */
	for (i=0;i < 5;i++)
	{
		dhPutValue(xlApp, L".ActiveSheet.Cells(%d, %d) = %S", 1, i + 1, szHeadings[i]);
	}

	/* Format the headings */
	WITH1(xlCells, xlApp, L".ActiveSheet.Range(%S)", L"A1:E1")
	{
		dhPutValue(xlCells, L".Interior.Color = %d", RGB(0xee,0xdd,0x82));
		dhPutValue(xlCells, L".Interior.Pattern = %d", 1);  /* xlSolid */
		dhPutValue(xlCells, L".Font.Size = %d", 13);
		dhPutValue(xlCells, L".Borders.Color = %d", RGB(0,0,0));
		dhPutValue(xlCells, L".Borders.LineStyle = %d", 1); /* xlContinuous */
		dhPutValue(xlCells, L".Borders.Weight = %d", 2);    /* xlThin */

	} END_WITH(xlCells);

	WITH(xlSheet, xlApp, L".ActiveSheet")
	{
		/* Set some values */
		dhPutValue(xlSheet, L".Range(%S).Value = %d", L"A2", 184);
		dhPutValue(xlSheet, L".Range(%S).Value = %d", L"B2", 182);
		dhPutValue(xlSheet, L".Range(%S).Value = %d", L"C2", 57);
		dhPutValue(xlSheet, L".Range(%S).Value = %d", L"D2", 162);
		dhPutValue(xlSheet, L".Range(%S).Value = %d", L"E2", 1276);

		/* Output data source */
		dhCallMethod(xlSheet, L".Range(%S).Merge", L"A4:E4");
		dhPutValue(xlSheet, L".Range(%S).Value = %S", L"A4", L"Source: IUCN Red List 2003 (http://www.redlist.org/info/tables/table2.html)");

		/* Apply a border around everything. Note '%m' means missing. */
		dhCallMethod(xlSheet, L".Range(%S).BorderAround(%d, %d, %m, %d)", L"A1:E2", 1, 2, RGB(0,0,0));

		/* Set column widths */
		dhPutValue(xlSheet, L".Columns(%S).ColumnWidth = %e", L"A:E", 12.5);

	} END_WITH(xlSheet);

	/* Set xlRange = xlApp.ActiveSheet.Range("A1:E2") */
	HR_TRY( dhGetValue(L"%o", &xlRange, xlApp, L".ActiveSheet.Range(%S)", L"A1:E2") );

	/* Set xlChart = xlApp.ActiveWorkbook.Charts.Add */
	HR_TRY( dhGetValue(L"%o", &xlChart, xlApp, L".ActiveWorkbook.Charts.Add") );

	/* Set up the chart */
	dhCallMethod(xlChart, L".ChartWizard(%o, %d, %d, %d, %d, %d, %b, %S)",
	                                        xlRange, -4100, 7, 1, 1, 0, FALSE, L"Critically Endangered Plants and Animals");

	dhPutValue(xlChart, L".HasAxis(%d) = %b", 3, FALSE); /* xlSeries */

	/* Put the chart on our worksheet */
	dhCallMethod(xlChart, L".Location(%d,%S)", 2, L"Critically Endangered");

cleanup:
	dhToggleExceptions(FALSE);

	dhPutValue(xlApp, L".ActiveWorkbook.Saved = %b", TRUE);

	SAFE_RELEASE(xlRange);
	SAFE_RELEASE(xlChart);
	SAFE_RELEASE(xlApp);

	dhUninitialize(TRUE);
	return 0;
}


/* **************************************************************************
 * Excel Sample 2:
 *   Demonstrates a much faster way of inserting multiple values into excel
 * using an array.
 *
 ============================================================================ */
int ExcelSample2(void)
{
	DISPATCH_OBJ(xlApp);
	int i, j;
	VARIANT arr;

	dhInitialize(TRUE);
	dhToggleExceptions(TRUE);

	HR_TRY( dhnewobject(L"Excel.Application", NULL, &xlApp) );

	dhPutValue(xlApp, L".Visible = %b", TRUE);

	HR_TRY( dhCallMethod(xlApp, L".Workbooks.Add") );

	MessageBoxA(NULL, "First the slow method...", NULL, MB_SETFOREGROUND);

	WITH(xlSheet, xlApp, L"ActiveSheet")
	{
		/* Fill cells with values one by one */
		for (i = 1; i <= 15; i++)
		{
			for (j = 1; j <= 15; j++)
			{
				dhPutValue(xlSheet, L".Cells(%d,%d) = %d", i, j, i * j);
			}
		}

	} END_WITH(xlSheet);

	MessageBoxA(NULL, "Now the fast way...", NULL, MB_SETFOREGROUND);

	/* xlApp.ActiveSheet.Range("A1:O15").Clear */
	dhCallMethod(xlApp, L".ActiveSheet.Range(%S).Clear", L"A1:O15");

	/* Create a safe array of VARIANT[15][15] */
	{
	   SAFEARRAYBOUND sab[2];

	   arr.vt = VT_ARRAY | VT_VARIANT;              /* An array of VARIANTs. */
	   sab[0].lLbound = 1; sab[0].cElements = 15;   /* First dimension.  [1 to 15] */
	   sab[1].lLbound = 1; sab[1].cElements = 15;   /* Second dimension. [1 to 15] */
	   arr.parray = SafeArrayCreate(VT_VARIANT, 2, sab);
	}
	
	/* Now fill in the array */
	for(i=1; i <= 15; i++)
	{
		for(j=1; j <= 15; j++)
		{
			VARIANT tmp = {0};
			long indices[2];

			indices[0] = i;  /* Index of first dimension */
			indices[1] = j;  /* Index of second dimension */

			tmp.vt = VT_I4;
			tmp.lVal = i * j + 10;

			SafeArrayPutElement(arr.parray, indices, (void*)&tmp);
		}
	}

	/* Set all values in one shot! */
	/* xlApp.ActiveSheet.Range("A1:O15") = arr */
	dhPutValue(xlApp, L".ActiveSheet.Range(%S) = %v", L"A1:O15", &arr);

	VariantClear(&arr);

cleanup:
	dhToggleExceptions(FALSE);

	dhPutValue(xlApp, L".ActiveWorkbook.Saved = %b", TRUE);

	SAFE_RELEASE(xlApp);

	dhUninitialize(TRUE);
	return 0;
}


/* ============================================================================ */
int main(void)
{
	printf("Running Excel Sample One...\n");
	ExcelSample1();

	printf("\nPress ENTER to run Excel Sample Two...\n");
	getchar();
	ExcelSample2();

	return 0;
}

--]]

-- Port of ExcelSample1 from C to Lua based on TestCom_002_ExcelApi
function TestCom_003_DispHelpExcel1 (Filename)
  -- Create object
  local Excel = newobject("Excel.Application")
  Reporter:expect("DISP_EXCEL_1_001", (Excel ~= nil))
  
  if (not Excel) then
    Reporter:expect("DISP_EXCEL_1_002_EXIT", false)
    return nil, nil
  end

  local Value, Type, ErrorMessage = Excel:set("DisplayAlerts", false)
  Reporter:expect("DISP_EXCEL_1_002", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_003", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_004", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = Excel:set("DisplayFullScreen", true)
  Reporter:expect("DISP_EXCEL_1_005", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_006", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_007", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = Excel:set("Visible", true)
  Reporter:expect("DISP_EXCEL_1_008", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_009", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_010", (ErrorMessage == nil))

  local Workbooks, Type, ErrorMessage = Excel:get("Workbooks")
  Reporter:expect("DISP_EXCEL_1_011", (Workbooks ~= nil))
  Reporter:expect("DISP_EXCEL_1_012", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_013", (ErrorMessage == nil))

  if (not Workbooks) then
    Reporter:expect("DISP_EXCEL_1_014_EXIT", false)
    return nil, nil
  end

  local Workbook, Type, ErrorMessage = Workbooks:call("Add")
  Reporter:expect("DISP_EXCEL_1_014", (Workbook ~= nil))
  Reporter:expect("DISP_EXCEL_1_015",  (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_016", (ErrorMessage == nil))

  if (not Workbook) then
    Reporter:expect("DISP_EXCEL_1_017_EXIT", false)
    return nil, nil
  end

  local ActiveSheet, Type, ErrorMessage = Excel:get("ActiveSheet")
  Reporter:expect("DISP_EXCEL_1_017", (ActiveSheet ~= nil))
  Reporter:expect("DISP_EXCEL_1_018", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_019", (ErrorMessage == nil))

  if (not ActiveSheet) then
    Reporter:expect("DISP_EXCEL_1_020_EXIT", false)
    return nil, nil
  end

  -- Set the worksheet name
  local Value, Type, ErrorMessage = ActiveSheet:set("Name", "Critically Endangered")
  Reporter:expect("DISP_EXCEL_1_020", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_020", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_021", (ErrorMessage == nil))

  -- headings
  local Headings = {"Mammals", "Birds", "Reptiles", "Fishes", "Plants"} -- szHeadings
  for Index = 1, #Headings do
  local Range, Type, ErrorMessage = ActiveSheet:get("Cells", 1, Index)
    local Prefix = format("DISP_EXCEL_1_022_%3.3d", Index)
    Reporter:expect(format("%s_001", Prefix), (Range ~= nil))
    Reporter:expect(format("%s_002", Prefix), (Type == "VT_DISPATCH"))
    Reporter:expect(format("%s_003", Prefix), (ErrorMessage == nil))
    if (not Range) then
      Reporter:expect("DISP_EXCEL_1_EARLY-RETURN-005", false)
      return nil, nil
    end
  local Value2, Type, ErrorMessage = Range:set("Value", Headings[Index])
    Reporter:expect(format("%s_004", Prefix), (Value2 == nil))
    Reporter:expect(format("%s_005", Prefix), (Type == "VT_EMPTY"))
    Reporter:expect(format("%s_006", Prefix), (ErrorMessage == nil))
  end

  -- Format the headings range A1:E1
  local HeadingsRange, Type, ErrorMessage = ActiveSheet:get("Range", "A1:E1")
  Reporter:expect("DISP_EXCEL_1_023", (HeadingsRange ~= nil))
  Reporter:expect("DISP_EXCEL_1_024", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_025", (ErrorMessage == nil))

  -- Set interior color (RGB(0xee,0xdd,0x82))
  local Interior, Type, ErrorMessage = HeadingsRange:get("Interior")
  Reporter:expect("DISP_EXCEL_1_026", (Interior ~= nil))
  Reporter:expect("DISP_EXCEL_1_027", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_028", (ErrorMessage == nil))
  
  if (not Interior) then
    Reporter:expect("DISP_EXCEL_1_029_EXIT", false)
    return nil, nil
  end

  local Value, Type, ErrorMessage = Interior:set("Color", 0x82ddee)  -- RGB values are reversed in COM
  Reporter:expect("DISP_EXCEL_1_029", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_030", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_031", (ErrorMessage == nil))

  local xlSolid = 1
  local Value, Type, ErrorMessage = Interior:set("Pattern", xlSolid)
  Reporter:expect("DISP_EXCEL_1_032", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_033", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_034", (ErrorMessage == nil))

  -- Set font size
  local Font, Type, ErrorMessage = HeadingsRange:get("Font")
  Reporter:expect("DISP_EXCEL_1_065", (Font ~= nil))
  Reporter:expect("DISP_EXCEL_1_066", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_067", (ErrorMessage == nil))

  if (not Font) then 
    Reporter:expect("DISP_EXCEL_1_068_EXIT", false)
    return nil, nil
  end

  local Value, Type, ErrorMessage = Font:set("Size", 13)
  Reporter:expect("DISP_EXCEL_1_068", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_069", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_070", (ErrorMessage == nil))

  -- Set borders
  local Borders, Type, ErrorMessage = HeadingsRange:get("Borders")
  Reporter:expect("DISP_EXCEL_1_071", (Borders ~= nil))
  Reporter:expect("DISP_EXCEL_1_072", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_073", (ErrorMessage == nil))

  if (not Borders) then
    Reporter:expect("DISP_EXCEL_1_074_EXIT", false)
    return nil, nil
  end

  local Value, Type, ErrorMessage = Borders:set("Color", 0x000000)  -- RGB(0,0,0)
  Reporter:expect("DISP_EXCEL_1_074", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_075", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_076", (ErrorMessage == nil))

  local xlContinuous = 1
  local Value, Type, ErrorMessage = Borders:set("LineStyle", xlContinuous)
  Reporter:expect("DISP_EXCEL_1_077", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_078", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_079", (ErrorMessage == nil))

  local xlThin = 2
  local Value, Type, ErrorMessage = Borders:set("Weight", xlThin)
  Reporter:expect("DISP_EXCEL_1_080", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_081", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_082", (ErrorMessage == nil))

  -- Set values in row 2
  local Values = {184, 182, 57, 162, 1276}
  local Columns = {"A", "B", "C", "D", "E"}
  for Index = 1, #Values do
  local Range, Type, ErrorMessage = ActiveSheet:get("Range", format("%s2", Columns[Index]))
    local Prefix = format("DISP_EXCEL_1_083_%3.3d", Index)
    Reporter:expect(format("%s_001", Prefix), (Range ~= nil))
    Reporter:expect(format("%s_002", Prefix), (Type == "VT_DISPATCH"))
    Reporter:expect(format("%s_003", Prefix), (ErrorMessage == nil))
    if (not Range) then
      Reporter:expect(format("%s_004_EXIT", Prefix), false)
      return nil, nil
    end
  local Value2, Type, ErrorMessage = Range:set("Value", Values[Index])
    Reporter:expect(format("%s_004", Prefix), (Value2 == nil))
    Reporter:expect(format("%s_005", Prefix), (Type == "VT_EMPTY"))
    Reporter:expect(format("%s_006", Prefix), (ErrorMessage == nil))
  end

  -- Merge cells A4:E4 and set source text
  local SourceRange, Type, ErrorMessage = ActiveSheet:get("Range", "A4:E4")
  Reporter:expect("DISP_EXCEL_1_113", (SourceRange ~= nil))
  Reporter:expect("DISP_EXCEL_1_114", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_115", (ErrorMessage == nil))
  
  if (not SourceRange) then
    Reporter:expect("DISP_EXCEL_1_116_EXIT", false)
    return nil, nil
  end

  local Value, Type, ErrorMessage = SourceRange:call("Merge")
  Reporter:expect("DISP_EXCEL_1_116", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = SourceRange:set("Value", "Source: IUCN Red List 2003 (http://www.redlist.org/info/tables/table2.html)")
  Reporter:expect("DISP_EXCEL_1_117", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_118", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_119", (ErrorMessage == nil))

  -- Apply border around A1:E2
  local DataRange, Type, ErrorMessage = ActiveSheet:get("Range", "A1:E2")
  Reporter:expect("DISP_EXCEL_1_120", (DataRange ~= nil))
  Reporter:expect("DISP_EXCEL_1_121", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_122", (ErrorMessage == nil))

  if (not DataRange) then
    Reporter:expect("DISP_EXCEL_1_123_EXIT", false)
    return nil, nil
  end

  local Borders, Type, ErrorMessage = DataRange:get("Borders")
  Reporter:expect("DISP_EXCEL_1_123", (Borders ~= nil))
  Reporter:expect("DISP_EXCEL_1_124", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_125", (ErrorMessage == nil))

  if (not Borders) then return nil, nil end

  local Value, Type, ErrorMessage = Borders:set("Color", 0x000000)  -- RGB(0,0,0)
  Reporter:expect("DISP_EXCEL_1_126", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_127", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_128", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = Borders:set("LineStyle", xlContinuous)
  Reporter:expect("DISP_EXCEL_1_129", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_130", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_131", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = Borders:set("Weight", xlThin)
  Reporter:expect("DISP_EXCEL_1_132", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_133", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_134", (ErrorMessage == nil))

  -- Set column widths for A:E
  local ColumnsRange, Type, ErrorMessage = ActiveSheet:get("Range", "A:E")
  Reporter:expect("DISP_EXCEL_1_135", (ColumnsRange ~= nil))
  Reporter:expect("DISP_EXCEL_1_136", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_137", (ErrorMessage == nil))

  if (not ColumnsRange) then
    Reporter:expect("DISP_EXCEL_1_138_EXIT", false)
    return nil, nil
  end

  local Value, Type, ErrorMessage = ColumnsRange:set("ColumnWidth", 12.5)
  Reporter:expect("DISP_EXCEL_1_138", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_139", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_140", (ErrorMessage == nil))

  -- Create chart
  local Charts, Type, ErrorMessage = Excel:get("Charts")
  Reporter:expect("DISP_EXCEL_1_141", (Charts ~= nil))
  Reporter:expect("DISP_EXCEL_1_142", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_143", (ErrorMessage == nil))

  if (not Charts) then
    Reporter:expect("DISP_EXCEL_1_144_EXIT", false)
    return nil, nil
  end

  local Chart, Type, ErrorMessage = Charts:call("Add")
  Reporter:expect("DISP_EXCEL_1_144", (Chart ~= nil))
  Reporter:expect("DISP_EXCEL_1_145", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_146", (ErrorMessage == nil))

  if (not Chart) then
    Reporter:expect("DISP_EXCEL_1_147_EXIT", false)
    return nil, nil
  end

  -- ChartWizard parameters: Source, Gallery, Format, PlotBy, CategoryLabels, SeriesLabels, HasLegend, Title
  local Value, Type, ErrorMessage = Chart:call("ChartWizard", DataRange, -4100, 7, 1, 1, 0, false, "Critically Endangered Plants and Animals")
  Reporter:expect("DISP_EXCEL_1_147", (((Value == nil) or (Type == "VT_BOOL") or (Type == "VT_EMPTY"))))
  Reporter:expect("DISP_EXCEL_1_148", (ErrorMessage == nil))

  -- Move chart to worksheet as an embedded object
  local WorksheetCharts, Type, ErrorMessage = ActiveSheet:call("ChartObjects")
  Reporter:expect("DISP_EXCEL_1_149", (WorksheetCharts ~= nil))
  Reporter:expect("DISP_EXCEL_1_150", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_151", (ErrorMessage == nil))

  if (not WorksheetCharts) then
    Reporter:expect("DISP_EXCEL_1_152_EXIT", false)
    return nil, nil
  end

  -- Add a new chart object at position (200, 200, 450, 400)
  local ChartObject, Type, ErrorMessage = WorksheetCharts:call("Add", 200, 200, 450, 400)
  Reporter:expect("DISP_EXCEL_1_152", (ChartObject ~= nil))
  Reporter:expect("DISP_EXCEL_1_153", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_154", (ErrorMessage == nil))

  if (not ChartObject) then
    Reporter:expect("DISP_EXCEL_1_155_EXIT", false)
    return nil, nil
  end

  -- Get the chart from the chart object
  local EmbeddedChart, Type, ErrorMessage = ChartObject:get("Chart")
  Reporter:expect("DISP_EXCEL_1_155", (EmbeddedChart ~= nil))
  Reporter:expect("DISP_EXCEL_1_156", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_157", (ErrorMessage == nil))

  if (not EmbeddedChart) then
    Reporter:expect("DISP_EXCEL_1_147_EXIT", false)
    return nil, nil
  end

  -- Copy the properties from our existing chart to the embedded one
  local Value, Type, ErrorMessage = EmbeddedChart:set("ChartType", -4100)  -- Match the gallery type from ChartWizard
  Reporter:expect("DISP_EXCEL_1_147", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_148", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_149", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = EmbeddedChart:call("SetSourceData", DataRange)
  Reporter:expect("DISP_EXCEL_1_150", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_151", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_152", (ErrorMessage == nil))

  -- Set chart title
  local Value, Type, ErrorMessage = EmbeddedChart:set("HasTitle", true)
  Reporter:expect("DISP_EXCEL_1_158", (Value == nil))
  Reporter:expect("DISP_EXCEL_1_159", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_1_160", (ErrorMessage == nil))

  local ChartTitle, Type, ErrorMessage = EmbeddedChart:get("ChartTitle")
  Reporter:expect("DISP_EXCEL_1_161", (ChartTitle ~= nil))
  Reporter:expect("DISP_EXCEL_1_162", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_163", (ErrorMessage == nil))

  if (ChartTitle) then
  local Value, Type, ErrorMessage = ChartTitle:set("Text", "Critically Endangered Plants and Animals")
    Reporter:expect("DISP_EXCEL_1_164", (Value == nil))
    Reporter:expect("DISP_EXCEL_1_165", (Type == "VT_EMPTY"))
    Reporter:expect("DISP_EXCEL_1_166", (ErrorMessage == nil))
  end

  -- Delete the original chart sheet since we've moved it to the worksheet
  local Value, Type, ErrorMessage = Chart:call("Delete")
  Reporter:expect("DISP_EXCEL_1_167", (ErrorMessage == nil))

  -- Save and quit
  local ActiveWorkbook, Type, ErrorMessage = Excel:get("ActiveWorkbook")
  Reporter:expect("DISP_EXCEL_1_168", (ActiveWorkbook ~= nil))
  Reporter:expect("DISP_EXCEL_1_169", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_1_170", (ErrorMessage == nil))

  if (ActiveWorkbook) then
  local Value, Type, ErrorMessage = ActiveWorkbook:set("Saved", true)
    Reporter:expect("DISP_EXCEL_1_171", (Value == nil))
    Reporter:expect("DISP_EXCEL_1_172", (Type == "VT_EMPTY"))
    Reporter:expect("DISP_EXCEL_1_173", (ErrorMessage == nil))
  end

  if Filename and Workbook then
  local Value, Type, ErrorMessage = Workbook:call("SaveAs", Filename)
    Reporter:expect("DISP_EXCEL_1_174", (ErrorMessage == nil))
  end

  local Value, Type, ErrorMessage = Excel:call("Quit")
  Reporter:expect("DISP_EXCEL_1_175", (ErrorMessage == nil))

  return nil, Filename
end

function TestCom_004_DispHelpExcel2 (Filename)
  -- Create Excel application
  local Excel = newobject("Excel.Application")
  Reporter:expect("DISP_EXCEL_2_001", (Excel ~= nil))

  if (not Excel) then
    Reporter:expect("DISP_EXCEL_2_002_EXIT", false)
    return nil, nil
  end

  local Value, Type, ErrorMessage = Excel:set("DisplayAlerts", false)
  Reporter:expect("DISP_EXCEL_2_002", (Value == nil))
  Reporter:expect("DISP_EXCEL_2_003", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_2_004", (ErrorMessage == nil))

  local Value, Type, ErrorMessage = Excel:set("Visible", true)
  Reporter:expect("DISP_EXCEL_2_005", (Value == nil))
  Reporter:expect("DISP_EXCEL_2_006", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_2_007", (ErrorMessage == nil))

  -- Create new workbook
  local Workbooks, Type, ErrorMessage = Excel:get("Workbooks")
  Reporter:expect("DISP_EXCEL_2_008", (Workbooks ~= nil))
  Reporter:expect("DISP_EXCEL_2_009", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_2_010", (ErrorMessage == nil))
  if (not Workbooks) then
    Reporter:expect("DISP_EXCEL_2_011_EXIT", false)
    return nil, nil
  end
  local Workbook, Type, ErrorMessage = Workbooks:call("Add")
  Reporter:expect("DISP_EXCEL_2_011", (Workbook ~= nil))
  Reporter:expect("DISP_EXCEL_2_012", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_2_013", (ErrorMessage == nil))
  if (not Workbook) then
    Reporter:expect("DISP_EXCEL_2_014_EXIT", false)
    return nil, nil
  end

  -- Get active sheet
  local ActiveSheet, Type, ErrorMessage = Excel:get("ActiveSheet")
  Reporter:expect("DISP_EXCEL_2_014", (ActiveSheet ~= nil))
  Reporter:expect("DISP_EXCEL_2_015", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_2_016", (ErrorMessage == nil))
  if (not ActiveSheet) then
    Reporter:expect("DISP_EXCEL_2_017_EXIT", false)
    return nil, nil
  end

  -- Fill cells with values one by one (slow method)
  local CellPrefix = "DISP_EXCEL_2_002"
  local CellCounter = 0
  for RowIndex = 1, 15 do
    for ColIndex = 1, 15 do
      CellCounter = CellCounter + 1
  local Range, Type, ErrorMessage = ActiveSheet:get("Cells", RowIndex, ColIndex)
      Reporter:expect(format("%s_%03d_01", CellPrefix, CellCounter), (Range ~= nil))
      Reporter:expect(format("%s_%03d_02", CellPrefix, CellCounter), (Type == "VT_DISPATCH"))
      Reporter:expect(format("%s_%03d_03", CellPrefix, CellCounter), (ErrorMessage == nil))
      if (not Range) then
        Reporter:expect(format("%s_%03d_04_EXIT", CellPrefix, CellCounter), false)
        return nil, nil
      end
  local Value2, Type, ErrorMessage = Range:set("Value", RowIndex * ColIndex)
      Reporter:expect(format("%s_%03d_04", CellPrefix, CellCounter), (Value2 == nil))
      Reporter:expect(format("%s_%03d_05", CellPrefix, CellCounter), (Type == "VT_EMPTY"))
      Reporter:expect(format("%s_%03d_06", CellPrefix, CellCounter), (ErrorMessage == nil))
    end
  end

  -- Clear the range A1:O15
  local Range, Type, ErrorMessage = ActiveSheet:get("Range", "A1:O15")
  Reporter:expect("DISP_EXCEL_2_010", (Range ~= nil))
  Reporter:expect("DISP_EXCEL_2_011", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_EXCEL_2_012", (ErrorMessage == nil))

  if (not Range) then
    Reporter:expect("DISP_EXCEL_2_013_EXIT", false)
    return nil, nil
  end

  local Value, Type, ErrorMessage = Range:call("Clear")
  Reporter:expect("DISP_EXCEL_2_013", (Value ~= nil))
  Reporter:expect("DISP_EXCEL_2_014", (Type == "VT_BOOL"))
  Reporter:expect("DISP_EXCEL_2_015", (ErrorMessage == nil))

  -- Create a SafeArray with variant type for 15x15 grid
  local SafeArray = newsafearray("VT_VARIANT", 1, 15, 1, 15)
  Reporter:expect("DISP_EXCEL_2_016", (SafeArray ~= nil))

  if (not SafeArray) then
    Reporter:expect("DISP_EXCEL_2_017_EXIT", false)
    return nil, nil
  end

  -- Create flattened test data table for 15x15 array (row-major)
  local Values = {}
  for RowIndex = 1, 15 do
    for ColIndex = 1, 15 do
      insert(Values, RowIndex * ColIndex + 10)  -- Adding 10 like in the C example
    end
  end

  -- Set the data into SafeArray
  local Count = SafeArray:write(Values)
  Reporter:expect("DISP_EXCEL_2_017", (Count == #Values))

  -- Set all values in one shot!
  local Value, Type, ErrorMessage = Range:set("Value", SafeArray)
  Reporter:expect("DISP_EXCEL_2_018", (Value == nil))
  Reporter:expect("DISP_EXCEL_2_019", (Type == "VT_EMPTY"))
  Reporter:expect("DISP_EXCEL_2_020", (ErrorMessage == nil))

  -- Save and quit
  if Filename then
  local Value, Type, ErrorMessage = Workbook:call("SaveAs", Filename)
    Reporter:expect("DISP_EXCEL_2_021", (ErrorMessage == nil))
  end

  local Value, Type, ErrorMessage = Excel:call("Quit")
  Reporter:expect("DISP_EXCEL_2_022", (ErrorMessage == nil))

  return nil, Filename
end

function TestCom_005_PropApi (Filename)
  local FSO_ID = "Scripting.FileSystemObject"
  local Fso    = newobject(FSO_ID)
  Reporter:expect("DISP_PROP_1_001", (Fso ~= nil))
  if (not Fso) then
    Reporter:expect("DISP_PROP_1_002_EXIT", false)
    return nil, nil
  end

  local Members = Fso:members()
  for Key, Value in pairs(Members) do
    -- minimal output to avoid changing test behavior
     print(format("LOG MEMBER %8.8X %s", Key, Value))
  end

  local Value, Type, ErrorMessage = Fso:call("GetTempName")
  if Value then
    Reporter:expect("DISP_PROP_1_002", (Type == "VT_BSTR"))
  else
    Reporter:expect("DISP_PROP_1_003", (ErrorMessage == nil))
  end

  local Value, Type, ErrorMessage = Fso:get("Drives")
  local Drive = Value
  Reporter:expect("DISP_PROP_1_004", (Drive ~= nil))
  Reporter:expect("DISP_PROP_1_005", (Type == "VT_DISPATCH"))
  Reporter:expect("DISP_PROP_1_006", (ErrorMessage == nil))
  if (not Drive) then
    Reporter:expect("DISP_PROP_1_007_EXIT", false)
    return nil, nil
  end

  local EnumObject, EnumType, ErrorMessage = Drive:get("_NewEnum")
  Reporter:expect("DISP_PROP_1_007", (EnumObject ~= nil))
  Reporter:expect("DISP_PROP_1_008", (ErrorMessage == nil))
  if (not EnumObject) then
    Reporter:expect("DISP_PROP_1_009_EXIT", false)
    return nil, nil
  end

  Reporter:expect("DISP_PROP_1_009", (type(EnumObject) == "table"))

  if (EnumType == "VT_UNKNOWN") then
    local NewEnum = com.castunknown(EnumObject, "IEnumVARIANT")
    Reporter:expect("DISP_PROP_1_010", (NewEnum ~= nil))
    if NewEnum then
  local FirstObject, Type, ErrorMessage = NewEnum:next()
      Reporter:expect("DISP_PROP_1_011", (ErrorMessage == nil))
      Reporter:expect("DISP_PROP_1_012", (FirstObject ~= nil))
      if FirstObject then
        local TypeName = FirstObject:gettype()
        local Members = FirstObject:members()
        for Key, Value in pairs(Members) do
           print(format("LOG MEMBER %8.8X %s", Key, Value))
        end
      end
      NewEnum:reset()
      local Clone = NewEnum:clone()
      Reporter:expect("DISP_PROP_1_013", (Clone ~= nil))
      if Clone then
        local ShouldContinue = true
        while ShouldContinue do
          local Value, Type, ErrorMessage = Clone:next()
          if (ErrorMessage == nil) and Value then
            local DriveExists = Fso:call("DriveExists", Value)
            local DriveLetter = Value:get("DriveLetter")
            local FileSystem  = Value:get("FileSystem")
            local VolumeName  = Value:get("VolumeName")
            local ShareName   = Value:get("ShareName")
             print("LOG ", DriveExists, Type, DriveLetter, FileSystem, VolumeName, ShareName)
          else
            ShouldContinue = false
          end
        end
      end
      Clone:release()
      NewEnum:release()
      EnumObject = nil
      NewEnum    = nil
      Clone      = nil
    end
  end

  -- Force garbage collection similar to original
  Drive = nil
  Value = nil
  Fso   = nil
  collectgarbage()

  return nil, Filename
end

-- The purpose is to ensure there is no crash due to object releases
function TestCom_006_GarbageCollector ()
  for Index = 1, 10 do
    local Name = format("GARBAGE-%02d", Index)
    collectgarbage("collect")
    Reporter:expect(Name, true)
  end
  -- No file created
  return nil, nil
end

--------------------------------------------------------------------------------
-- TEST CASE MANAGEMENT                                                       --
--------------------------------------------------------------------------------

local function RunTest (FunctionName, Suffix, ...)
  Suffix = (Suffix or "")
  local Filename = format("%s%s.xlsx", FunctionName, Suffix)
  local NameWide = format("%-24s", FunctionName)
  local Function = _ENV[FunctionName]
  if Function then
    Reporter:block(FunctionName)
    local Result, ErrorString, Filename = pcall(Function, Filename, ...)
    if ErrorString then
      Reporter:printf("%s FAILED", NameWide)
      Reporter:printf("  %s", ErrorString)
    elseif Filename then
      Reporter:printf("%s OK %s", NameWide, tostring(Filename))
    else
      Reporter:printf("%s OK", NameWide)
    end
  else
    Reporter:printf(format("ERROR: function [%s] could not be found", FunctionName))
  end
end

--------------------------------------------------------------------------------
-- MAIN TEST                                                                  --
--------------------------------------------------------------------------------

RunTest("TestCom_001_WrongName")
RunTest("TestCom_002_ExcelApi")
RunTest("TestCom_003_DispHelpExcel1")
RunTest("TestCom_004_DispHelpExcel2")
RunTest("TestCom_005_PropApi")
RunTest("TestCom_006_GarbageCollector")

Reporter:printf("== SUMMARY ==")
Reporter:summary("os.exit")
