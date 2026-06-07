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
-- LOAD WIN32 DLLs AND BINDINGS                                               --
--------------------------------------------------------------------------------

local win32 = ffi.loadlib("kernel32.dll")
win32:addlibrary("user32.dll")
win32:addlibrary("gdi32.dll")

win32:load("tiny-win32-ffi")

local GetMessageA             = win32.GetMessageA
local TranslateMessage        = win32.TranslateMessage
local DispatchMessageA        = win32.DispatchMessageA
local PostQuitMessage         = win32.PostQuitMessage
local KillTimer               = win32.KillTimer
local InvalidateRect          = win32.InvalidateRect
local MoveWindow              = win32.MoveWindow
local BeginPaint              = win32.BeginPaint
local EndPaint                = win32.EndPaint
local SelectObject            = win32.SelectObject
local DeleteObject            = win32.DeleteObject
local SetBkMode               = win32.SetBkMode
local GetClientRect           = win32.GetClientRect
local GetDC                   = win32.GetDC
local ReleaseDC               = win32.ReleaseDC
local DrawTextW               = win32.DrawTextW
local DefWindowProcA          = win32.DefWindowProcA
local MultiByteToWideChar     = win32.MultiByteToWideChar
local WM_DESTROY              = win32.WM_DESTROY
local WM_TIMER                = win32.WM_TIMER
local WM_SIZE                 = win32.WM_SIZE
local WM_PAINT                = win32.WM_PAINT
local WM_COMMAND              = win32.WM_COMMAND
local WS_CHILD                = win32.WS_CHILD
local WS_VISIBLE              = win32.WS_VISIBLE
local WS_CLIPCHILDREN         = win32.WS_CLIPCHILDREN
local TRANSPARENT             = win32.TRANSPARENT
local DT_SINGLELINE           = win32.DT_SINGLELINE
local DT_CENTER               = win32.DT_CENTER
local DT_VCENTER              = win32.DT_VCENTER
local DT_CALCRECT             = win32.DT_CALCRECT
local LOGFONTA                = win32.LOGFONTA
local NONCLIENTMETRICSA       = win32.NONCLIENTMETRICSA
local SystemParametersInfoA   = win32.SystemParametersInfoA
local CreateFontIndirectA     = win32.CreateFontIndirectA
local SPI_GETNONCLIENTMETRICS = win32.SPI_GETNONCLIENTMETRICS

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

local IconResourceId     = newpointer(0, win32.IDI_APPLICATION)
local CursorResourceId   = newpointer(0, win32.IDC_ARROW)
local WindowColorBrushId = newpointer(0, (win32.COLOR_WINDOW + 1))

local HIcon     = win32.LoadIconA(NULL, IconResourceId)
local HCursor   = win32.LoadCursorA(NULL, CursorResourceId)
local HInstance = win32.GetModuleHandleA(NULL)

local GlobalFont = win32.CreateFontA(
  64,                        -- Height
  0,                         -- Width (auto)
  0,                         -- Escapement
  0,                         -- Orientation
  win32.FW_NORMAL,           -- Weight
  0,                         -- Italic
  0,                         -- Underline
  0,                         -- StrikeOut
  win32.DEFAULT_CHARSET,     -- CharSet
  0,                         -- OutPrecision (OUT_DEFAULT_PRECIS)
  0,                         -- ClipPrecision (CLIP_DEFAULT_PRECIS)
  win32.ANTIALIASED_QUALITY, -- Quality
  (win32.DEFAULT_PITCH | win32.FF_SWISS),
  "Arial"
)

local WndClass     = newinstance(win32.WNDCLASSEX)
local Rect         = newinstance(win32.RECT)
local Msg          = newinstance(win32.MSG)
local Paint        = newinstance(win32.PAINTSTRUCT)
local PaintPointer = Paint:getpointer()
local RectPointer  = Rect:getpointer()

local TEXT_BUFFER_SIZE_IN_BYTES = 256
local TEXT_BUFFER_SIZE_IN_WCHAR = (TEXT_BUFFER_SIZE_IN_BYTES / 2)
local TextBuffer                = ffi.malloc(TEXT_BUFFER_SIZE_IN_BYTES)
local MeasureBuffer             = ffi.malloc(TEXT_BUFFER_SIZE_IN_BYTES)

local CONTROL_RESET_ID = 1 -- Win32 ID for button "Reset"
local CONTROL_PAUSE_ID = 2 -- Win32 ID for button "Pause"
local CONTROL_EXIT_ID  = 3 -- Win32 ID for button "Exit"

local ButtonResetWindow
local ButtonPauseWindow
local ButtonExitWindow

local UI_ButtonWidth  = 0
local UI_ButtonHeight = 0
local UI_ButtonGap    = 15
local UI_BlockGap     = 15
local UI_TextHeight   = 0

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

local function SM_Reset ()
  APP_StateTextIndex = 1
  APP_StateCounter   = 0
  APP_Paused         = false
end

SM_Reset()

local function FindLongestString (Strings)
  local MaxLen = 0
  local Result = ""
  for Index, String in ipairs(Strings) do
    local Length = #String
    if (Length > MaxLen) then
      MaxLen = Length
      Result = String
    end
  end
  return Result
end

local MaxString = format("%s...", FindLongestString(STRINGS))

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
  local Spaces          = string.rep(" ", (3 - APP_StateCounter))
  local FormattedString = format("%s%s%s", CurrentString, Dots, Spaces)
  return FormattedString
end

--------------------------------------------------------------------------------
-- UI LAYOUT                                                                  --
--------------------------------------------------------------------------------

local UI_TempRectangle = newinstance(win32.RECT)
local UI_TempPointer   = UI_TempRectangle:getpointer()

local function InitButtonSizes (Window)
  -- Create a pain context
  local Hdc = GetDC(Window)
  -- Evaluate "Pause" string size
  SelectObject(Hdc, SystemFont)
  DrawTextW(Hdc, "Pause", -1, UI_TempPointer, (DT_CALCRECT | DT_SINGLELINE))
  UI_ButtonWidth  = (UI_TempRectangle:get("right")  * 2)
  UI_ButtonHeight = (UI_TempRectangle:get("bottom") * 2)
  -- Text height (measured once with GlobalFont, stable across all strings)
  SelectObject(Hdc, GlobalFont)
  DrawTextW(Hdc, "World!", -1, UI_TempPointer, (DT_CALCRECT | DT_SINGLELINE))
  UI_TextHeight = UI_TempRectangle:get("bottom")
  -- Release
  ReleaseDC(Window, Hdc)
end

local function ApplyLayout (Window, Hdc)
  -- Measure base text width (without dots) via UTF-16
  MultiByteToWideChar(win32.CP_UTF8, 0, MaxString, -1, MeasureBuffer, TEXT_BUFFER_SIZE_IN_WCHAR)
  UI_TempRectangle:set("left", 0)
  DrawTextW(Hdc, MeasureBuffer, -1, UI_TempPointer, (DT_CALCRECT | DT_SINGLELINE))
  local BaseWidth = UI_TempRectangle:get("right")
  local TextWidth = BaseWidth
  -- Button row
  local TotalButtonWidth  = (3 * UI_ButtonWidth + 2 * UI_ButtonGap)
  local BlockWidth        = math.max(TextWidth, TotalButtonWidth)
  local BlockHeight       = (UI_TextHeight + UI_BlockGap + UI_ButtonHeight)
  -- Center block in client
  GetClientRect(Window, RectPointer)
  local ClientWidth  = Rect:get("right")
  local ClientHeight = Rect:get("bottom")
  local BlockX = ((ClientWidth - BlockWidth) // 2)
  local BlockY = ((ClientHeight - BlockHeight) // 2)
  -- Store text rect (full block width, DT_CENTER keeps text visually centered)
  UI_TempRectangle:set("left",   BlockX)
  UI_TempRectangle:set("top",    BlockY)
  UI_TempRectangle:set("right",  (BlockX + BlockWidth))
  UI_TempRectangle:set("bottom", (BlockY + UI_TextHeight))
  -- Position buttons centered below text (fixed X based on TotalButtonWidth, not BlockWidth)
  local ButtonsX = ((ClientWidth - TotalButtonWidth) // 2)
  local ButtonsY = (BlockY + UI_TextHeight + UI_BlockGap)
  print(string.format("CNT=%d Base=%d TextW=%d BlkW=%d BlkX=%d BtnX=%d",
    APP_StateCounter, BaseWidth, TextWidth, BlockWidth, BlockX, ButtonsX))
  -- Move the buttons
  MoveWindow(ButtonResetWindow, ButtonsX,                                        ButtonsY, UI_ButtonWidth, UI_ButtonHeight, 1)
  MoveWindow(ButtonPauseWindow, (ButtonsX + UI_ButtonWidth + UI_ButtonGap),      ButtonsY, UI_ButtonWidth, UI_ButtonHeight, 1)
  MoveWindow(ButtonExitWindow,  (ButtonsX + 2 * (UI_ButtonWidth + UI_ButtonGap)), ButtonsY, UI_ButtonWidth, UI_ButtonHeight, 1)
end

--------------------------------------------------------------------------------
-- WINDOW PROCEDURE                                                           --
--------------------------------------------------------------------------------

local function WriteUTF16String ()
  local Utf8String = SM_GetString()
  MultiByteToWideChar(win32.CP_UTF8, 0, Utf8String, -1, TextBuffer, TEXT_BUFFER_SIZE_IN_WCHAR)
end

local function WindowProcedure (Window, Message, WParam, LParam)
  local Result
  if (Message == WM_DESTROY) then
    PostQuitMessage(EXIT_SUCCESS)
    Result = 0
  elseif (Message == WM_TIMER) then
    local Action = SM_Tick()
    if (Action == "UPDATE") then
      WriteUTF16String()
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
        SM_Reset()
        WriteUTF16String()
        InvalidateRect(Window, NULL, 1)
      elseif (ControlId == CONTROL_PAUSE_ID) then
        SM_TogglePause()
      end
    end
    Result = 0
  elseif (Message == WM_SIZE) then
    local LayoutDc = GetDC(Window)
    ApplyLayout(Window, LayoutDc)
    ReleaseDC(Window, LayoutDc)
    InvalidateRect(Window, NULL, 1)
    Result = 0
  elseif (Message == WM_PAINT) then
    local DeviceContext = BeginPaint(Window, PaintPointer)
    local OldFont       = SelectObject(DeviceContext, GlobalFont)
    SetBkMode(DeviceContext, TRANSPARENT)
    DrawTextW(
      DeviceContext,
      TextBuffer,
      -1,
      UI_TempPointer,
      (DT_SINGLELINE | DT_CENTER | DT_VCENTER)
    )
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
  WndClass:set("cbSize",        win32.WNDCLASSEX:getsizeinbytes())
  WndClass:set("style",         (win32.CS_HREDRAW | win32.CS_VREDRAW | win32.CS_OWNDC))
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
  local ClassAtom = win32.RegisterClassExA(WndClass:getpointer())
  assert((ClassAtom ~= 0), "RegisterClassExA failed")
  -- Create window
  local Window = win32.CreateWindowExA(
    0,
    "MAIN_WindowClass",
    "Hello World",
    (win32.WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN),
    win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, 800, 320,
    NULL, NULL, HInstance, NULL
  )
  assert((Window ~= NULL), "CreateWindowExA failed")
  -- Compute button sizes from font metrics
  InitButtonSizes(Window)
  -- Create control buttons (positioned later by ApplyLayout)
  local ButtonResetPointer = newpointer(0, CONTROL_RESET_ID)
  local ButtonPausePointer = newpointer(0, CONTROL_PAUSE_ID)
  local ButtonExitPointer  = newpointer(0, CONTROL_EXIT_ID)
  ButtonResetWindow = win32.CreateWindowExA(0, "BUTTON", "Reset", (WS_CHILD | WS_VISIBLE), 0, 0, UI_ButtonWidth, UI_ButtonHeight, Window, ButtonResetPointer, HInstance, NULL)
  ButtonPauseWindow = win32.CreateWindowExA(0, "BUTTON", "Pause", (WS_CHILD | WS_VISIBLE), 0, 0, UI_ButtonWidth, UI_ButtonHeight, Window, ButtonPausePointer, HInstance, NULL)
  ButtonExitWindow  = win32.CreateWindowExA(0, "BUTTON", "Exit",  (WS_CHILD | WS_VISIBLE), 0, 0, UI_ButtonWidth, UI_ButtonHeight, Window, ButtonExitPointer,  HInstance, NULL)
  -- Apply initial layout (measures text, positions buttons)
  local InitDc = GetDC(Window)
  ApplyLayout(Window, InitDc)
  ReleaseDC(Window, InitDc)
  -- Update window state (counter=0 for initial display without dots)
  APP_StateCounter = 0
  WriteUTF16String()
  win32.ShowWindow(Window, win32.SW_SHOWDEFAULT)
  win32.UpdateWindow(Window)
  GlobalTimerId = win32.SetTimer(Window, 0, 750, NULL)
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
  DeleteObject(GlobalFont)
  DeleteObject(SystemFont)
  KillTimer(NULL, GlobalTimerId)
  ffi.free(TextBuffer)
  ffi.free(MeasureBuffer)
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

Init()
Loop()
Clean()
