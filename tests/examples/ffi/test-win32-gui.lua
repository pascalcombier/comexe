--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- This example show how to use ComEXE's libffi to use the native Win32 API for:
-- Creating a window
-- Creating buttons (displayed using the proper styling)
-- Positioning the widgets in the main window
-- Convert and draw unicode strings
-- Use timers
--
-- For more serious work, we would need to build a middleware in Lua that would
-- simplify the API. The main thing would be a proper generic layout hbox/vbox
-- and the wrapping of native controls (window, buttons, checkbox, etc).
--
-- We could have a deeper look at the projects clay or layout.h
--

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local ffi = require("com.ffi")

local format = string.format

local NULL        = ffi.NULL
local newinstance = ffi.newinstance
local newcallback = ffi.newcallback
local newpointer  = ffi.newpointer
local sint64      = ffi.sint64
local pointer     = ffi.pointer
local uint32      = ffi.uint32
local uint64      = ffi.uint64

--------------------------------------------------------------------------------
-- FFI IMPORTS                                                                --
--------------------------------------------------------------------------------

-- @BEGIN import-c-header
-- @PARAM file tiny-win32.h
-- @PARAM function BindLibrary
-- @PARAM lib ffi
-- @OUTPUT
-- Constants
local ANTIALIASED_QUALITY = 4
local COLOR_WINDOW = 5
local CP_UTF8 = 65001
local CS_HREDRAW = 2
local CS_OWNDC = 32
local CS_VREDRAW = 1
local CW_USEDEFAULT = 2147483648
local DEFAULT_CHARSET = 1
local DEFAULT_PITCH = 0
local DT_CALCRECT = 1024
local DT_SINGLELINE = 32
local DT_VCENTER = 4
local FF_SWISS = 32
local FW_NORMAL = 400
local IDC_ARROW = 32512
local IDI_APPLICATION = 32512
local LTGRAY_BRUSH = 1
local SPI_GETNONCLIENTMETRICS = 41
local SW_SHOWDEFAULT = 10
local TRANSPARENT = 1
local WM_COMMAND = 273
local WM_DESTROY = 2
local WM_PAINT = 15
local WM_QUIT = 18
local WM_SIZE = 5
local WM_TIMER = 275
local WS_CHILD = 1073741824
local WS_CLIPCHILDREN = 33554432
local WS_EX_CLIENTEDGE = 512
local WS_OVERLAPPEDWINDOW = 13565952
local WS_VISIBLE = 268435456
-- Structures
local LOGFONTA
local NONCLIENTMETRICSA
local POINT
local RECT
local WNDCLASSEX
local MSG
local PAINTSTRUCT
-- Functions
local BeginPaint
local CreateFontA
local CreateFontIndirectA
local CreateWindowExA
local DefWindowProcA
local DeleteObject
local DispatchMessageA
local DrawTextW
local EndPaint
local FillRect
local GetClientRect
local GetDC
local GetMessageA
local GetModuleHandleA
local GetStockObject
local InvalidateRect
local KillTimer
local LoadCursorA
local LoadIconA
local MoveWindow
local MultiByteToWideChar
local PostQuitMessage
local RegisterClassExA
local ReleaseDC
local SelectObject
local SetBkMode
local SetTimer
local ShowWindow
local SystemParametersInfoA
local TranslateMessage
local UpdateWindow
-- Binding function
local function BindLibrary (Library)
  LOGFONTA = ffi.newstructure("LOGFONTA",
    ffi.sint32, "lfHeight",
    ffi.sint32, "lfWidth",
    ffi.sint32, "lfEscapement",
    ffi.sint32, "lfOrientation",
    ffi.sint32, "lfWeight",
    ffi.uint8, "lfItalic",
    ffi.uint8, "lfUnderline",
    ffi.uint8, "lfStrikeOut",
    ffi.uint8, "lfCharSet",
    ffi.uint8, "lfOutPrecision",
    ffi.uint8, "lfClipPrecision",
    ffi.uint8, "lfQuality",
    ffi.uint8, "lfPitchAndFamily",
    ffi.pointer, "lfFaceName"
  )
  NONCLIENTMETRICSA = ffi.newstructure("NONCLIENTMETRICSA",
    ffi.uint32, "cbSize",
    ffi.sint32, "iBorderWidth",
    ffi.sint32, "iScrollWidth",
    ffi.sint32, "iScrollHeight",
    ffi.sint32, "iCaptionWidth",
    ffi.sint32, "iCaptionHeight",
    LOGFONTA, "lfCaptionFont",
    ffi.sint32, "iSmCaptionWidth",
    ffi.sint32, "iSmCaptionHeight",
    LOGFONTA, "lfSmCaptionFont",
    ffi.sint32, "iMenuWidth",
    ffi.sint32, "iMenuHeight",
    LOGFONTA, "lfMenuFont",
    LOGFONTA, "lfStatusFont",
    LOGFONTA, "lfMessageFont"
  )
  POINT = ffi.newstructure("POINT",
    ffi.sint32, "x",
    ffi.sint32, "y"
  )
  RECT = ffi.newstructure("RECT",
    ffi.sint32, "left",
    ffi.sint32, "top",
    ffi.sint32, "right",
    ffi.sint32, "bottom"
  )
  WNDCLASSEX = ffi.newstructure("WNDCLASSEX",
    ffi.uint32, "cbSize",
    ffi.uint32, "style",
    ffi.pointer, "lpfnWndProc",
    ffi.sint32, "cbClsExtra",
    ffi.sint32, "cbWndExtra",
    ffi.pointer, "hInstance",
    ffi.pointer, "hIcon",
    ffi.pointer, "hCursor",
    ffi.pointer, "hbrBackground",
    ffi.cstring, "lpszMenuName",
    ffi.cstring, "lpszClassName",
    ffi.pointer, "hIconSm"
  )
  MSG = ffi.newstructure("MSG",
    ffi.pointer, "hwnd",
    ffi.uint32, "message",
    ffi.uint64, "wParam",
    ffi.sint64, "lParam",
    ffi.uint32, "time",
    POINT, "pt",
    ffi.uint32, "lPrivate"
  )
  PAINTSTRUCT = ffi.newstructure("PAINTSTRUCT",
    ffi.pointer, "hdc",
    ffi.sint32, "fErase",
    RECT, "rcPaint",
    ffi.sint32, "fRestore",
    ffi.sint32, "fIncUpdate",
    ffi.uint64, "reservedA",
    ffi.uint64, "reservedB",
    ffi.uint64, "reservedC",
    ffi.uint64, "reservedD"
  )
  BeginPaint = Library:bind(ffi.pointer, "BeginPaint", ffi.pointer, ffi.pointer)
  CreateFontA = Library:bind(ffi.pointer, "CreateFontA", ffi.sint32, ffi.sint32, ffi.sint32, ffi.sint32, ffi.sint32, ffi.uint32, ffi.uint32, ffi.uint32, ffi.uint32, ffi.uint32, ffi.uint32, ffi.uint32, ffi.uint32, ffi.pointer)
  CreateFontIndirectA = Library:bind(ffi.pointer, "CreateFontIndirectA", ffi.pointer)
  CreateWindowExA = Library:bind(ffi.pointer, "CreateWindowExA", ffi.uint32, ffi.pointer, ffi.pointer, ffi.uint32, ffi.sint32, ffi.sint32, ffi.sint32, ffi.sint32, ffi.pointer, ffi.pointer, ffi.pointer, ffi.pointer)
  DefWindowProcA = Library:bind(ffi.sint64, "DefWindowProcA", ffi.pointer, ffi.uint32, ffi.uint64, ffi.sint64)
  DeleteObject = Library:bind(ffi.sint32, "DeleteObject", ffi.pointer)
  DispatchMessageA = Library:bind(ffi.sint64, "DispatchMessageA", ffi.pointer)
  DrawTextW = Library:bind(ffi.sint32, "DrawTextW", ffi.pointer, ffi.pointer, ffi.sint32, ffi.pointer, ffi.uint32)
  EndPaint = Library:bind(ffi.sint32, "EndPaint", ffi.pointer, ffi.pointer)
  FillRect = Library:bind(ffi.sint32, "FillRect", ffi.pointer, ffi.pointer, ffi.pointer)
  GetClientRect = Library:bind(ffi.sint32, "GetClientRect", ffi.pointer, ffi.pointer)
  GetDC = Library:bind(ffi.pointer, "GetDC", ffi.pointer)
  GetMessageA = Library:bind(ffi.sint32, "GetMessageA", ffi.pointer, ffi.pointer, ffi.uint32, ffi.uint32)
  GetModuleHandleA = Library:bind(ffi.pointer, "GetModuleHandleA", ffi.pointer)
  GetStockObject = Library:bind(ffi.pointer, "GetStockObject", ffi.sint32)
  InvalidateRect = Library:bind(ffi.sint32, "InvalidateRect", ffi.pointer, ffi.pointer, ffi.sint32)
  KillTimer = Library:bind(ffi.sint32, "KillTimer", ffi.pointer, ffi.uint64)
  LoadCursorA = Library:bind(ffi.pointer, "LoadCursorA", ffi.pointer, ffi.pointer)
  LoadIconA = Library:bind(ffi.pointer, "LoadIconA", ffi.pointer, ffi.pointer)
  MoveWindow = Library:bind(ffi.sint32, "MoveWindow", ffi.pointer, ffi.sint32, ffi.sint32, ffi.sint32, ffi.sint32, ffi.sint32)
  MultiByteToWideChar = Library:bind(ffi.sint32, "MultiByteToWideChar", ffi.uint32, ffi.uint32, ffi.pointer, ffi.sint32, ffi.pointer, ffi.sint32)
  PostQuitMessage = Library:bind(ffi.void, "PostQuitMessage", ffi.sint32)
  RegisterClassExA = Library:bind(ffi.uint16, "RegisterClassExA", ffi.pointer)
  ReleaseDC = Library:bind(ffi.sint32, "ReleaseDC", ffi.pointer, ffi.pointer)
  SelectObject = Library:bind(ffi.pointer, "SelectObject", ffi.pointer, ffi.pointer)
  SetBkMode = Library:bind(ffi.sint32, "SetBkMode", ffi.pointer, ffi.sint32)
  SetTimer = Library:bind(ffi.uint64, "SetTimer", ffi.pointer, ffi.uint64, ffi.uint32, ffi.pointer)
  ShowWindow = Library:bind(ffi.sint32, "ShowWindow", ffi.pointer, ffi.sint32)
  SystemParametersInfoA = Library:bind(ffi.sint32, "SystemParametersInfoA", ffi.uint32, ffi.uint32, ffi.pointer, ffi.uint32)
  TranslateMessage = Library:bind(ffi.sint32, "TranslateMessage", ffi.pointer)
  UpdateWindow = Library:bind(ffi.sint32, "UpdateWindow", ffi.pointer)
end
-- @END

--------------------------------------------------------------------------------
-- LOAD WIN32 DLLs AND BINDINGS                                               --
--------------------------------------------------------------------------------

local win32 = ffi.loadlib("kernel32.dll")
win32:addlibrary("user32.dll")
win32:addlibrary("gdi32.dll")

BindLibrary(win32)

--------------------------------------------------------------------------------
-- QUERY WIN32 SYSTEM FONT                                                    --
--------------------------------------------------------------------------------

local SystemNcm = newinstance(NONCLIENTMETRICSA)
SystemNcm:set("cbSize", NONCLIENTMETRICSA:getsizeinbytes())

-- Collect default font
SystemParametersInfoA(
  SPI_GETNONCLIENTMETRICS,
  NONCLIENTMETRICSA:getsizeinbytes(),
  SystemNcm:getpointer(),
  0)

local DefaultFont = SystemNcm:get("lfMessageFont")
local SystemFont  = CreateFontIndirectA(DefaultFont:getpointer())

--------------------------------------------------------------------------------
-- CONSTANTS AND GLOBAL VARIABLES                                             --
--------------------------------------------------------------------------------

local EXIT_SUCCESS = 0

local IconResourceId     = newpointer(0, IDI_APPLICATION)
local CursorResourceId   = newpointer(0, IDC_ARROW)
local WindowColorBrushId = newpointer(0, (COLOR_WINDOW + 1))

local HIcon     = LoadIconA(NULL, IconResourceId)
local HCursor   = LoadCursorA(NULL, CursorResourceId)
local HInstance = GetModuleHandleA(NULL)

local STRINGS_FONT = CreateFontA(
  64,                         -- Height
  0,                          -- Width (auto)
  0,                          -- Escapement
  0,                          -- Orientation
  FW_NORMAL,                  -- Weight
  0,                          -- Italic
  0,                          -- Underline
  0,                          -- StrikeOut
  DEFAULT_CHARSET,            -- CharSet
  0,                          -- OutPrecision (OUT_DEFAULT_PRECIS)
  0,                          -- ClipPrecision (CLIP_DEFAULT_PRECIS)
  ANTIALIASED_QUALITY,        -- Quality
  (DEFAULT_PITCH | FF_SWISS), -- PitchAndFamily
  "Arial"                     -- FaceName
)

local WndClass     = newinstance(WNDCLASSEX)
local Rect         = newinstance(RECT)
local Msg          = newinstance(MSG)
local Paint        = newinstance(PAINTSTRUCT)
local PaintPointer = Paint:getpointer()
local RectPointer  = Rect:getpointer()

local TEXT_BUFFER_SIZE_IN_BYTES = 256
local TEXT_BUFFER_SIZE_IN_WCHAR = (TEXT_BUFFER_SIZE_IN_BYTES / 2)
local CurrentTextBuffer         = ffi.malloc(TEXT_BUFFER_SIZE_IN_BYTES)

local CONTROL_RESET_ID = 1 -- Win32 ID for button "Reset"
local CONTROL_PAUSE_ID = 2 -- Win32 ID for button "Pause"
local CONTROL_EXIT_ID  = 3 -- Win32 ID for button "Exit"

local ButtonResetWindow
local ButtonPauseWindow
local ButtonExitWindow

-- Height of the strings STRINGS, calculated once with STRINGS_FONT
local UI_TextHeight

-- Width of the current STRINGS, calculated based on SM_GetWidestString (max dots)
local CurrentTextWidth = 0

local UI_ButtonGap = 16
local UI_BlockGap  = 16
local UI_ButtonWidth
local UI_ButtonHeight

--------------------------------------------------------------------------------
-- STATE MACHINE                                                              --
--------------------------------------------------------------------------------

local STRINGS = {
  "Hello World!",
  "greetings-привет",
  "hello-こんにちは",
  "hola-世界",
  "γεια-σας",
  "안녕하세요-world",
  "Closing"
}

local APP_StateTextIndex
local APP_StateCounter
local APP_Paused

local function SM_Init ()
  APP_StateTextIndex = 1
  APP_StateCounter   = 0
  APP_Paused         = false
end

local function SM_Tick ()
  local Result
  if (APP_Paused) then
    Result = "SKIP"
  else
  APP_StateCounter = (APP_StateCounter + 1)
  if (APP_StateCounter <= 3) then
    Result = "UPDATE"
  else
    APP_StateTextIndex = (APP_StateTextIndex + 1)
    if (APP_StateTextIndex > #STRINGS) then
      Result = "QUIT"
    else
      APP_StateCounter = 0
      Result = "UPDATE"
    end
  end
  end
  return Result
end

local function SM_TogglePause ()
  APP_Paused = (not APP_Paused)
end

local function SM_GetString ()
  local CurrentString   = STRINGS[APP_StateTextIndex]
  local Dots            = string.rep(".", APP_StateCounter)
  local FormattedString = format("%s%s", CurrentString, Dots)
  return FormattedString
end

local function SM_GetWidestString ()
  local CurrentString   = STRINGS[APP_StateTextIndex]
  local FormattedString = format("%s...", CurrentString)
  return FormattedString
end

--------------------------------------------------------------------------------
-- UI LAYOUT                                                                  --
--------------------------------------------------------------------------------

local UI_TempRectangle = newinstance(RECT)
local UI_TempPointer   = UI_TempRectangle:getpointer()

local function InitMainTextHeight (Hdc)
  SelectObject(Hdc, STRINGS_FONT)
  DrawTextW(Hdc, "Hello World!", -1, UI_TempPointer, (DT_CALCRECT | DT_SINGLELINE))
  UI_TextHeight = UI_TempRectangle:get("bottom")
end

local function InitButtonSizes (Hdc)
  SelectObject(Hdc, SystemFont)
  DrawTextW(Hdc, "Pause", -1, UI_TempPointer, (DT_CALCRECT | DT_SINGLELINE))
  UI_ButtonWidth  = (UI_TempRectangle:get("right")  * 2)
  UI_ButtonHeight = (UI_TempRectangle:get("bottom") * 2)
end

local function ApplyLayout (Window)
  local TextWidth = CurrentTextWidth
  -- Button row
  local TotalButtonWidth = (3 * UI_ButtonWidth + 2 * UI_ButtonGap)
  local BlockWidth       = math.max(TextWidth, TotalButtonWidth)
  local BlockHeight      = (UI_TextHeight + UI_BlockGap + UI_ButtonHeight)
  -- Center block in window
  GetClientRect(Window, RectPointer)
  local ClientWidth  = Rect:get("right")
  local ClientHeight = Rect:get("bottom")
  local BlockX = ((ClientWidth - BlockWidth) // 2)
  local BlockY = ((ClientHeight - BlockHeight) // 2)
  -- Position toolbar
  local ButtonsX = ((ClientWidth - TotalButtonWidth) // 2)
  local ButtonsY = (BlockY + UI_TextHeight + UI_BlockGap)
  -- Move the buttons
  MoveWindow(ButtonResetWindow, ButtonsX,                                         ButtonsY, UI_ButtonWidth, UI_ButtonHeight, 1)
  MoveWindow(ButtonPauseWindow, (ButtonsX + UI_ButtonWidth + UI_ButtonGap),       ButtonsY, UI_ButtonWidth, UI_ButtonHeight, 1)
  MoveWindow(ButtonExitWindow,  (ButtonsX + 2 * (UI_ButtonWidth + UI_ButtonGap)), ButtonsY, UI_ButtonWidth, UI_ButtonHeight, 1)
  -- Store text rect for WM_PAINT
  local TextX = (BlockX + ((BlockWidth - CurrentTextWidth) // 2))
  UI_TempRectangle:set("left",   TextX)
  UI_TempRectangle:set("top",    BlockY)
  UI_TempRectangle:set("right",  (TextX + CurrentTextWidth))
  UI_TempRectangle:set("bottom", (BlockY + UI_TextHeight))
end

--------------------------------------------------------------------------------
-- WINDOW PROCEDURE                                                           --
--------------------------------------------------------------------------------

local function MeasureLargestString (Window)
  local MaxDotsString = SM_GetWidestString()
  local Hdc           = GetDC(Window)
  SelectObject(Hdc, STRINGS_FONT)
  MultiByteToWideChar(CP_UTF8, 0, MaxDotsString, -1, CurrentTextBuffer, TEXT_BUFFER_SIZE_IN_WCHAR)
  UI_TempRectangle:set("left",   0)
  UI_TempRectangle:set("top",    0)
  UI_TempRectangle:set("right",  0)
  UI_TempRectangle:set("bottom", 0)
  DrawTextW(Hdc, CurrentTextBuffer, -1, UI_TempPointer, (DT_CALCRECT | DT_SINGLELINE))
  CurrentTextWidth = UI_TempRectangle:get("right")
  ReleaseDC(Window, Hdc)
end

local function WriteUTF16String ()
  local Utf8String = SM_GetString()
  MultiByteToWideChar(CP_UTF8, 0, Utf8String, -1, CurrentTextBuffer, TEXT_BUFFER_SIZE_IN_WCHAR)
end

local function WindowProcedure (Window, Message, WParam, LParam)
  local Result
  if (Message == WM_DESTROY) then
    PostQuitMessage(EXIT_SUCCESS)
    Result = 0
  elseif (Message == WM_TIMER) then
    local Action = SM_Tick()
    if (Action == "UPDATE") then
      MeasureLargestString(Window)
      WriteUTF16String()
      ApplyLayout(Window)
      InvalidateRect(Window, NULL, 1)
    elseif (Action == "QUIT") then
      PostQuitMessage(EXIT_SUCCESS)
    end
    Result = 0
  elseif (Message == WM_COMMAND) then
    local ControlId = (WParam & 0xFFFF)
    local Notify    = ((WParam >> 16) & 0xFFFF)
    if (Notify == 0) then
      if (ControlId == CONTROL_EXIT_ID) then
        PostQuitMessage(EXIT_SUCCESS)
      elseif (ControlId == CONTROL_RESET_ID) then
        SM_Init()
        MeasureLargestString(Window)
        WriteUTF16String()
        ApplyLayout(Window)
        InvalidateRect(Window, NULL, 1)
      elseif (ControlId == CONTROL_PAUSE_ID) then
        SM_TogglePause()
      end
    end
    Result = 0
  elseif (Message == WM_SIZE) then
    ApplyLayout(Window)
    InvalidateRect(Window, NULL, 1)
    Result = 0
  elseif (Message == WM_PAINT) then
    -- Assume UI_TempRectangle contains the right location and CurrentTextBuffer is ready
    local DeviceContext = BeginPaint(Window, PaintPointer)
    local OldFont       = SelectObject(DeviceContext, STRINGS_FONT)
    SetBkMode(DeviceContext, TRANSPARENT)
    DrawTextW(DeviceContext, CurrentTextBuffer, -1, UI_TempPointer, (DT_SINGLELINE | DT_VCENTER))
    SelectObject(DeviceContext, OldFont)
    EndPaint(Window, PaintPointer)
    Result = 0
  else
    Result = DefWindowProcA(Window, Message, WParam, LParam)
  end
  return Result
end

-- Create lua callback for WindowProcedure (top-level to prevent garbage collection)
local WindowProcClosure = newcallback(WindowProcedure, sint64, pointer, uint32, uint64, sint64)

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local function Init ()
  -- Set window class fields
  WndClass:set("cbSize",        WNDCLASSEX:getsizeinbytes())
  WndClass:set("style",         (CS_HREDRAW | CS_VREDRAW | CS_OWNDC))
  WndClass:set("lpfnWndProc",   WindowProcClosure:getpointer())
  WndClass:set("cbClsExtra",    0)
  WndClass:set("cbWndExtra",    0)
  WndClass:set("hInstance",     HInstance)
  WndClass:set("hIcon",         HIcon)
  WndClass:set("hCursor",       HCursor)
  WndClass:set("hbrBackground", WindowColorBrushId)
  WndClass:set("lpszMenuName",  nil)
  WndClass:set("lpszClassName", "MAIN_WindowClass")
  WndClass:set("hIconSm",       HIcon)
  -- Register class
  local ClassAtom = RegisterClassExA(WndClass:getpointer())
  assert((ClassAtom ~= 0), "RegisterClassExA failed")
  -- Create window
  local Window = CreateWindowExA(
    0,
    "MAIN_WindowClass",
    "Hello World",
    (WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN),
    CW_USEDEFAULT, CW_USEDEFAULT, 800, 320,
    NULL, NULL, HInstance, NULL
  )
  assert((Window ~= NULL), "CreateWindowExA failed")
  -- Compute button sizes and text height from font metrics
  local InitHdc = GetDC(Window)
  InitMainTextHeight(InitHdc)
  InitButtonSizes(InitHdc)
  ReleaseDC(Window, InitHdc)
  -- Create control buttons (positioned later by ApplyLayout)
  local ButtonResetPointer = newpointer(0, CONTROL_RESET_ID)
  local ButtonPausePointer = newpointer(0, CONTROL_PAUSE_ID)
  local ButtonExitPointer  = newpointer(0, CONTROL_EXIT_ID)
  ButtonResetWindow = CreateWindowExA(0, "BUTTON", "Reset", (WS_CHILD | WS_VISIBLE), 0, 0, UI_ButtonWidth, UI_ButtonHeight, Window, ButtonResetPointer, HInstance, NULL)
  ButtonPauseWindow = CreateWindowExA(0, "BUTTON", "Pause", (WS_CHILD | WS_VISIBLE), 0, 0, UI_ButtonWidth, UI_ButtonHeight, Window, ButtonPausePointer, HInstance, NULL)
  ButtonExitWindow  = CreateWindowExA(0, "BUTTON", "Exit",  (WS_CHILD | WS_VISIBLE), 0, 0, UI_ButtonWidth, UI_ButtonHeight, Window, ButtonExitPointer,  HInstance, NULL)
  -- Initial state
  SM_Init()
  MeasureLargestString(Window)
  WriteUTF16String()
  ApplyLayout(Window)
  ShowWindow(Window, SW_SHOWDEFAULT)
  UpdateWindow(Window)
  GlobalTimerId = SetTimer(Window, 0, 500, NULL)
  assert((GlobalTimerId ~= 0), "SetTimer failed")
end

local function Loop ()
  local Continue    = true
  local ReturnValue = EXIT_SUCCESS
  local MsgPointer  = Msg:getpointer()
  while Continue do
    local GetResult = GetMessageA(MsgPointer, NULL, 0, 0)
    if (GetResult == 0) then
      ReturnValue = Msg:get("wParam")
      Continue    = false
    elseif (GetResult == -1) then
      Continue = false
    else
      TranslateMessage(MsgPointer)
      DispatchMessageA(MsgPointer)
    end
  end
  return ReturnValue
end

local function Clean ()
  DeleteObject(STRINGS_FONT)
  DeleteObject(SystemFont)
  KillTimer(NULL, GlobalTimerId)
  ffi.free(CurrentTextBuffer)
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

Init()
Loop()
Clean()
