----------------------------------------------------------------------
-- This is a WORKING EXAMPLE in C of the creation of a window in Win32
----------------------------------------------------------------------
--
-- static LRESULT CALLBACK MAIN_WindowProcedure(HWND Window, UINT Message, WPARAM WParam, LPARAM LParam)
-- {
--   LRESULT Result = 0;
--   bool IsHandled = false;
-- 
--   switch (Message)
--   {
--     case WM_DESTROY:
--       PostQuitMessage(0);
--       IsHandled = true;
--       break;
-- 
--     case WM_PAINT:
--     {
--       PAINTSTRUCT PaintStruct;
--       HDC DeviceContext = BeginPaint(Window, &PaintStruct);
--       RECT Rectangle;
--       GetClientRect(Window, &Rectangle);
--       DrawText(DeviceContext, "Hello, World!", -1, &Rectangle, DT_SINGLELINE | DT_CENTER | DT_VCENTER);
--       EndPaint(Window, &PaintStruct);
--       IsHandled = true;
--       break;
--     }
-- 
--     default:
--       Result = DefWindowProc(Window, Message, WParam, LParam);
--       break;
--   }
-- 
--   if (IsHandled)
--   {
--     Result = 0;
--   }
-- 
--   return Result;
-- }
--
--
-- int main()
-- {
--   WNDCLASSEX WindowClass;
--   HWND Window;
--   MSG Message;
--   bool IsRunning = true;
-- 
--   /* Register the window class */
--   WindowClass.cbSize = sizeof(WNDCLASSEX);
--   WindowClass.style = 0;
--   WindowClass.lpfnWndProc = MAIN_WindowProcedure;
--   WindowClass.cbClsExtra = 0;
--   WindowClass.cbWndExtra = 0;
--   WindowClass.hInstance = GetModuleHandle(NULL);
--   WindowClass.hIcon = LoadIcon(NULL, IDI_APPLICATION);
--   WindowClass.hCursor = LoadCursor(NULL, IDC_ARROW);
--   WindowClass.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
--   WindowClass.lpszMenuName = NULL;
--   WindowClass.lpszClassName = "MAIN_WindowClass";
--   WindowClass.hIconSm = LoadIcon(NULL, IDI_APPLICATION);
-- 
--   if (!RegisterClassEx(&WindowClass))
--   {
--     return 1;
--   }
-- 
--   /* Create the window */
--   Window = CreateWindowEx(
--     WS_EX_CLIENTEDGE,
--     "MAIN_WindowClass",
--     "Hello World",
--     WS_OVERLAPPEDWINDOW,
--     CW_USEDEFAULT, CW_USEDEFAULT, 400, 300,
--     NULL, NULL, GetModuleHandle(NULL), NULL
--   );
-- 
--   if (!Window)
--   {
--     return 1;
--   }
-- 
--   ShowWindow(Window, SW_SHOWDEFAULT);
--   UpdateWindow(Window);
-- 
--   /* Message loop */
--   while (IsRunning)
--   {
--     if (PeekMessage(&Message, NULL, 0, 0, PM_REMOVE))
--     {
--       if (Message.message == WM_QUIT)
--       {
--         IsRunning = false;
--       }
--       else
--       {
--         TranslateMessage(&Message);
--         DispatchMessage(&Message);
--       }
--     }
--   }
-- 
--   return (int)Message.wParam;
-- }

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local uv = require("luv")

local format = string.format

--------------------------------------------------------------------------------
-- UTF things                                                                 --
--------------------------------------------------------------------------------

-- According to luv documentation, the resulting string does not contains NULL terminator
local function Utf8ToUtf16 (Utf8String)
  local Utf16String               = uv.wtf8_to_utf16(Utf8String)
  local NullTerminatedUtf16String = format("%s\x00\x00", Utf16String)
  return NullTerminatedUtf16String
end

--------------------------------------------------------------------------------
-- Working Win32 window example in Lua using libffi                           --
--------------------------------------------------------------------------------

local LibFFI  = require("com/ffi")

local NULL   = LibFFI.NULL
local format = string.format
local pack   = string.pack
local unpack = string.unpack

-- Retrieve DLLs
local libc     = LibFFI.loadlib("msvcrt.dll")
local user32   = LibFFI.loadlib("user32.dll")
local kernel32 = LibFFI.loadlib("kernel32.dll")
local gdi32    = LibFFI.loadlib("gdi32.dll")
local shlwapi  = LibFFI.loadlib("Shlwapi.dll")

assert(libc)
assert(user32)
assert(kernel32)
assert(gdi32)
assert(shlwapi)

-- Get all required functions from libc
local malloc = libc:GetFunction("pointer", "malloc", "uint64")
local free   = libc:GetFunction("void", "free", "pointer")
local memset = libc:GetFunction("pointer", "memset", "pointer", "sint32", "uint64")

-- Get all required functions from user32
local RegisterClassEx = user32:GetFunction("uint16", "RegisterClassExA", "pointer")
local PostQuitMessage = user32:GetFunction("void", "PostQuitMessage", "sint32")
local BeginPaint      = user32:GetFunction("pointer", "BeginPaint", "pointer", "pointer")
local GetClientRect   = user32:GetFunction("sint32", "GetClientRect", "pointer", "pointer")
local DrawText        = user32:GetFunction("sint32", "DrawTextW", "pointer", "pointer", "sint32", "pointer", "uint32")
local EndPaint        = user32:GetFunction("sint32", "EndPaint", "pointer", "pointer")
local DefWindowProc   = user32:GetFunction("sint64", "DefWindowProcA", "pointer", "uint32", "uint64", "sint64")
local CreateWindowEx  = user32:GetFunction("pointer", "CreateWindowExA", 
  "uint32", "string", "string", "uint32",
  "sint32", "sint32", "sint32", "sint32",
  "pointer", "pointer", "pointer", "pointer")
local GetMessage      = user32:GetFunction("sint32", "GetMessageA", "pointer", "pointer", "uint32", "uint32")
local ShowWindow      = user32:GetFunction("sint32", "ShowWindow", "pointer", "sint32")
local UpdateWindow    = user32:GetFunction("sint32", "UpdateWindow", "pointer")
local PeekMessage     = user32:GetFunction("sint32", "PeekMessageA", "pointer", "pointer", "uint32", "uint32", "uint32")
local TranslateMessage = user32:GetFunction("sint32", "TranslateMessage", "pointer")
local DispatchMessage = user32:GetFunction("sint64", "DispatchMessageA", "pointer")
local LoadIcon        = user32:GetFunction("pointer", "LoadIconA", "pointer", "pointer")
local LoadCursor      = user32:GetFunction("pointer", "LoadCursorA", "pointer", "pointer")
local InvalidateRect  = user32:GetFunction("sint32", "InvalidateRect", "pointer", "pointer", "sint32")
local FillRect        = user32:GetFunction("sint32", "FillRect", "pointer", "pointer", "pointer")
local GetStockObject  = gdi32:GetFunction("pointer", "GetStockObject", "sint32")
local SetTimer        = user32:GetFunction("uint64", "SetTimer", "pointer", "uint64", "uint32", "pointer")
local KillTimer       = user32:GetFunction("sint32", "KillTimer", "pointer", "uint64")

-- Get all required functions from kernel32
local GetModuleHandle = kernel32:GetFunction("pointer", "GetModuleHandleA", "string")

-- Get all required functions from gdi32
local CreateFont = gdi32:GetFunction("pointer", "CreateFontA", 
  "sint32", "sint32", "sint32", "sint32", "sint32", "uint32", "uint32", "uint32", 
  "uint32", "uint32", "uint32", "uint32", "string")
local SelectObject = gdi32:GetFunction("pointer", "SelectObject", "pointer", "pointer")
local DeleteObject = gdi32:GetFunction("sint32", "DeleteObject", "pointer")
local SetBkMode = gdi32:GetFunction("sint32", "SetBkMode", "pointer", "sint32")

-- shlwapi
local StrDupAFunction = shlwapi:GetFunction("pointer", "StrDupA", "string")

-- Assert all functions are available
assert(malloc)
assert(free)
assert(memset)
assert(RegisterClassEx)
assert(PostQuitMessage)
assert(BeginPaint)
assert(GetClientRect)
assert(DrawText)
assert(EndPaint)
assert(DefWindowProc)
assert(CreateWindowEx)
assert(ShowWindow)
assert(UpdateWindow)
assert(PeekMessage)
assert(TranslateMessage)
assert(DispatchMessage)
assert(LoadIcon)
assert(LoadCursor)
assert(GetModuleHandle)
assert(InvalidateRect)
assert(FillRect)
assert(GetStockObject)
assert(SetTimer)
assert(KillTimer)
assert(CreateFont)
assert(SelectObject)
assert(DeleteObject)
assert(SetBkMode)
assert(StrDupAFunction)

-- Those ID are coming from winuser.h
-- But in Lua we could not define all of them in this file
-- #define WM_NULL 0x0000
-- #define WM_CREATE 0x0001
-- #define WM_DESTROY 0x0002
-- #define WM_MOVE 0x0003
-- #define WM_SIZE 0x0005
-- #define WM_ACTIVATE 0x0006
-- #define WM_SETFOCUS 0x0007
-- #define WM_KILLFOCUS 0x0008
-- #define WM_ENABLE 0x000A
-- #define WM_SETREDRAW 0x000B
-- #define WM_SETTEXT 0x000C
-- #define WM_GETTEXT 0x000D
-- #define WM_GETTEXTLENGTH 0x000E
-- #define WM_PAINT 0x000F
-- #define WM_CLOSE 0x0010
-- #define WM_QUERYENDSESSION 0x0011
-- #define WM_QUERYOPEN 0x0013
-- #define WM_ENDSESSION 0x0016
-- #define WM_QUIT 0x0012
-- #define WM_ERASEBKGND 0x0014
-- #define WM_SYSCOLORCHANGE 0x0015
-- #define WM_SHOWWINDOW 0x0018
-- #define WM_WININICHANGE 0x001A
-- #define WM_SETTINGCHANGE WM_WININICHANGE
-- #define WM_DEVMODECHANGE 0x001B
-- #define WM_ACTIVATEAPP 0x001C
-- #define WM_FONTCHANGE 0x001D
-- #define WM_TIMECHANGE 0x001E
-- #define WM_CANCELMODE 0x001F
-- #define WM_SETCURSOR 0x0020
-- #define WM_MOUSEACTIVATE 0x0021
-- #define WM_CHILDACTIVATE 0x0022
-- #define WM_QUEUESYNC 0x0023
-- #define WM_GETMINMAXINFO 0x0024
-- #define WM_PAINTICON 0x0026
-- #define WM_ICONERASEBKGND 0x0027
-- #define WM_NEXTDLGCTL 0x0028
-- #define WM_SPOOLERSTATUS 0x002A
-- #define WM_DRAWITEM 0x002B
-- #define WM_MEASUREITEM 0x002C
-- #define WM_DELETEITEM 0x002D
-- #define WM_VKEYTOITEM 0x002E
-- #define WM_CHARTOITEM 0x002F
-- #define WM_SETFONT 0x0030
-- #define WM_GETFONT 0x0031
-- #define WM_SETHOTKEY 0x0032
-- #define WM_GETHOTKEY 0x0033
-- #define WM_QUERYDRAGICON 0x0037
-- #define WM_COMPAREITEM 0x0039
-- #define WM_GETOBJECT 0x003D
-- #define WM_COMPACTING 0x0041
-- #define WM_COMMNOTIFY 0x0044
-- #define WM_WINDOWPOSCHANGING 0x0046
-- #define WM_WINDOWPOSCHANGED 0x0047
-- #define WM_POWER 0x0048
-- #define WM_COPYDATA 0x004A
-- #define WM_CANCELJOURNAL 0x004B
-- #define WM_NOTIFY 0x004E
-- #define WM_INPUTLANGCHANGEREQUEST 0x0050
-- #define WM_INPUTLANGCHANGE 0x0051
-- #define WM_TCARD 0x0052
-- #define WM_HELP 0x0053
-- #define WM_USERCHANGED 0x0054
-- #define WM_NOTIFYFORMAT 0x0055
-- #define WM_CONTEXTMENU 0x007B
-- #define WM_STYLECHANGING 0x007C
-- #define WM_STYLECHANGED 0x007D
-- #define WM_DISPLAYCHANGE 0x007E
-- #define WM_GETICON 0x007F
-- #define WM_SETICON 0x0080
-- #define WM_NCCREATE 0x0081
-- #define WM_NCDESTROY 0x0082
-- #define WM_NCCALCSIZE 0x0083
-- #define WM_NCHITTEST 0x0084
-- #define WM_NCPAINT 0x0085
-- #define WM_NCACTIVATE 0x0086
-- #define WM_GETDLGCODE 0x0087
-- #define WM_SYNCPAINT 0x0088
-- #define WM_NCMOUSEMOVE 0x00A0
-- #define WM_NCLBUTTONDOWN 0x00A1
-- #define WM_NCLBUTTONUP 0x00A2
-- #define WM_NCLBUTTONDBLCLK 0x00A3
-- #define WM_NCRBUTTONDOWN 0x00A4
-- #define WM_NCRBUTTONUP 0x00A5
-- #define WM_NCRBUTTONDBLCLK 0x00A6
-- #define WM_NCMBUTTONDOWN 0x00A7
-- #define WM_NCMBUTTONUP 0x00A8
-- #define WM_NCMBUTTONDBLCLK 0x00A9
-- #define WM_NCXBUTTONDOWN 0x00AB
-- #define WM_NCXBUTTONUP 0x00AC
-- #define WM_NCXBUTTONDBLCLK 0x00AD
-- #define WM_INPUT_DEVICE_CHANGE 0x00fe
-- #define WM_INPUT 0x00FF
-- #define WM_KEYFIRST 0x0100
-- #define WM_KEYDOWN 0x0100
-- #define WM_KEYUP 0x0101
-- #define WM_CHAR 0x0102
-- #define WM_DEADCHAR 0x0103
-- #define WM_SYSKEYDOWN 0x0104
-- #define WM_SYSKEYUP 0x0105
-- #define WM_SYSCHAR 0x0106
-- #define WM_SYSDEADCHAR 0x0107
-- #define WM_UNICHAR 0x0109
-- #define WM_KEYLAST 0x0109
-- #define WM_KEYLAST 0x0108
-- #define WM_IME_STARTCOMPOSITION 0x010D
-- #define WM_IME_ENDCOMPOSITION 0x010E
-- #define WM_IME_COMPOSITION 0x010F
-- #define WM_IME_KEYLAST 0x010F
-- #define WM_INITDIALOG 0x0110
-- #define WM_COMMAND 0x0111
-- #define WM_SYSCOMMAND 0x0112
-- #define WM_TIMER 0x0113
-- #define WM_HSCROLL 0x0114
-- #define WM_VSCROLL 0x0115
-- #define WM_INITMENU 0x0116
-- #define WM_INITMENUPOPUP 0x0117
-- #define WM_MENUSELECT 0x011F
-- #define WM_GESTURE 0x0119
-- #define WM_GESTURENOTIFY 0x011A
-- #define WM_MENUCHAR 0x0120
-- #define WM_ENTERIDLE 0x0121
-- #define WM_MENURBUTTONUP 0x0122
-- #define WM_MENUDRAG 0x0123
-- #define WM_MENUGETOBJECT 0x0124
-- #define WM_UNINITMENUPOPUP 0x0125
-- #define WM_MENUCOMMAND 0x0126
-- #define WM_CHANGEUISTATE 0x0127
-- #define WM_UPDATEUISTATE 0x0128
-- #define WM_QUERYUISTATE 0x0129
-- #define WM_CTLCOLORMSGBOX 0x0132
-- #define WM_CTLCOLOREDIT 0x0133
-- #define WM_CTLCOLORLISTBOX 0x0134
-- #define WM_CTLCOLORBTN 0x0135
-- #define WM_CTLCOLORDLG 0x0136
-- #define WM_CTLCOLORSCROLLBAR 0x0137
-- #define WM_CTLCOLORSTATIC 0x0138
-- #define WM_MOUSEFIRST 0x0200
-- #define WM_MOUSEMOVE 0x0200
-- #define WM_LBUTTONDOWN 0x0201
-- #define WM_LBUTTONUP 0x0202
-- #define WM_LBUTTONDBLCLK 0x0203
-- #define WM_RBUTTONDOWN 0x0204
-- #define WM_RBUTTONUP 0x0205
-- #define WM_RBUTTONDBLCLK 0x0206
-- #define WM_MBUTTONDOWN 0x0207
-- #define WM_MBUTTONUP 0x0208
-- #define WM_MBUTTONDBLCLK 0x0209
-- #define WM_MOUSEWHEEL 0x020A
-- #define WM_XBUTTONDOWN 0x020B
-- #define WM_XBUTTONUP 0x020C
-- #define WM_XBUTTONDBLCLK 0x020D
-- #define WM_MOUSEHWHEEL 0x020e
-- #define WM_MOUSELAST 0x020e
-- #define WM_MOUSELAST 0x020d
-- #define WM_MOUSELAST 0x020a
-- #define WM_MOUSELAST 0x0209
-- #define WM_PARENTNOTIFY 0x0210
-- #define WM_ENTERMENULOOP 0x0211
-- #define WM_EXITMENULOOP 0x0212
-- #define WM_NEXTMENU 0x0213
-- #define WM_SIZING 0x0214
-- #define WM_CAPTURECHANGED 0x0215
-- #define WM_MOVING 0x0216
-- #define WM_POWERBROADCAST 0x0218
-- #define WM_DEVICECHANGE 0x0219
-- #define WM_MDICREATE 0x0220
-- #define WM_MDIDESTROY 0x0221
-- #define WM_MDIACTIVATE 0x0222
-- #define WM_MDIRESTORE 0x0223
-- #define WM_MDINEXT 0x0224
-- #define WM_MDIMAXIMIZE 0x0225
-- #define WM_MDITILE 0x0226
-- #define WM_MDICASCADE 0x0227
-- #define WM_MDIICONARRANGE 0x0228
-- #define WM_MDIGETACTIVE 0x0229
-- #define WM_MDISETMENU 0x0230
-- #define WM_ENTERSIZEMOVE 0x0231
-- #define WM_EXITSIZEMOVE 0x0232
-- #define WM_DROPFILES 0x0233
-- #define WM_MDIREFRESHMENU 0x0234
-- #define WM_POINTERDEVICECHANGE 0x238
-- #define WM_POINTERDEVICEINRANGE 0x239
-- #define WM_POINTERDEVICEOUTOFRANGE 0x23a
-- #define WM_TOUCH 0x0240
-- #define WM_NCPOINTERUPDATE 0x0241
-- #define WM_NCPOINTERDOWN 0x0242
-- #define WM_NCPOINTERUP 0x0243
-- #define WM_POINTERUPDATE 0x0245
-- #define WM_POINTERDOWN 0x0246
-- #define WM_POINTERUP 0x0247
-- #define WM_POINTERENTER 0x0249
-- #define WM_POINTERLEAVE 0x024a
-- #define WM_POINTERACTIVATE 0x024b
-- #define WM_POINTERCAPTURECHANGED 0x024c
-- #define WM_TOUCHHITTESTING 0x024d
-- #define WM_POINTERWHEEL 0x024e
-- #define WM_POINTERHWHEEL 0x024f
-- #define WM_POINTERROUTEDTO 0x0251
-- #define WM_POINTERROUTEDAWAY 0x0252
-- #define WM_POINTERROUTEDRELEASED 0x0253
-- #define WM_IME_SETCONTEXT 0x0281
-- #define WM_IME_NOTIFY 0x0282
-- #define WM_IME_CONTROL 0x0283
-- #define WM_IME_COMPOSITIONFULL 0x0284
-- #define WM_IME_SELECT 0x0285
-- #define WM_IME_CHAR 0x0286
-- #define WM_IME_REQUEST 0x0288
-- #define WM_IME_KEYDOWN 0x0290
-- #define WM_IME_KEYUP 0x0291
-- #define WM_MOUSEHOVER 0x02A1
-- #define WM_MOUSELEAVE 0x02A3
-- #define WM_NCMOUSEHOVER 0x02A0
-- #define WM_NCMOUSELEAVE 0x02A2
-- #define WM_WTSSESSION_CHANGE 0x02B1
-- #define WM_TABLET_FIRST 0x02c0
-- #define WM_TABLET_LAST 0x02df
-- #define WM_DPICHANGED 0x02e0
-- #define WM_DPICHANGED_BEFOREPARENT 0x02e2
-- #define WM_DPICHANGED_AFTERPARENT 0x02e3
-- #define WM_GETDPISCALEDSIZE 0x02e4
-- #define WM_CUT 0x0300
-- #define WM_COPY 0x0301
-- #define WM_PASTE 0x0302
-- #define WM_CLEAR 0x0303
-- #define WM_UNDO 0x0304
-- #define WM_RENDERFORMAT 0x0305
-- #define WM_RENDERALLFORMATS 0x0306
-- #define WM_DESTROYCLIPBOARD 0x0307
-- #define WM_DRAWCLIPBOARD 0x0308
-- #define WM_PAINTCLIPBOARD 0x0309
-- #define WM_VSCROLLCLIPBOARD 0x030A
-- #define WM_SIZECLIPBOARD 0x030B
-- #define WM_ASKCBFORMATNAME 0x030C
-- #define WM_CHANGECBCHAIN 0x030D
-- #define WM_HSCROLLCLIPBOARD 0x030E
-- #define WM_QUERYNEWPALETTE 0x030F
-- #define WM_PALETTEISCHANGING 0x0310
-- #define WM_PALETTECHANGED 0x0311
-- #define WM_HOTKEY 0x0312
-- #define WM_PRINT 0x0317
-- #define WM_PRINTCLIENT 0x0318
-- #define WM_APPCOMMAND 0x0319
-- #define WM_THEMECHANGED 0x031A
-- #define WM_CLIPBOARDUPDATE 0x031d
-- #define WM_DWMCOMPOSITIONCHANGED 0x031e
-- #define WM_DWMNCRENDERINGCHANGED 0x031f
-- #define WM_DWMCOLORIZATIONCOLORCHANGED 0x0320
-- #define WM_DWMWINDOWMAXIMIZEDCHANGE 0x0321
-- #define WM_DWMSENDICONICTHUMBNAIL 0x0323
-- #define WM_DWMSENDICONICLIVEPREVIEWBITMAP 0x0326
-- #define WM_GETTITLEBARINFOEX 0x033f
-- #define WM_HANDHELDFIRST 0x0358
-- #define WM_HANDHELDLAST 0x035F
-- #define WM_AFXFIRST 0x0360
-- #define WM_AFXLAST 0x037F
-- #define WM_PENWINFIRST 0x0380
-- #define WM_PENWINLAST 0x038F
-- #define WM_APP 0x8000
-- #define WM_USER 0x0400

-- Constants for Windows messages
local WM_NULL                   = 0x0000
local WM_CREATE                 = 0x0001
local WM_DESTROY                = 0x0002
local WM_MOVE                   = 0x0003
local WM_SIZE                   = 0x0005
local WM_ACTIVATE               = 0x0006
local WM_SETFOCUS               = 0x0007
local WM_KILLFOCUS              = 0x0008
local WM_PAINT                  = 0x000F
local WM_CLOSE                  = 0x0010
local WM_QUIT                   = 0x0012
local WM_ERASEBKGND             = 0x0014
local WM_SHOWWINDOW             = 0x0018
local WM_ACTIVATEAPP            = 0x001C
local WM_SETCURSOR              = 0x0020
local WM_GETMINMAXINFO          = 0x0024
local WM_WINDOWPOSCHANGING      = 0x0046
local WM_WINDOWPOSCHANGED       = 0x0047
local WM_INPUTLANGCHANGE        = 0x0051
local WM_NOTIFY                 = 0x004E
local WM_GETICON                = 0x007F
local WM_NCCREATE               = 0x0081
local WM_NCDESTROY              = 0x0082
local WM_NCCALCSIZE             = 0x0083
local WM_NCHITTEST              = 0x0084
local WM_NCPAINT                = 0x0085
local WM_NCACTIVATE             = 0x0086
local WM_NCUAHDRAWCAPTION       = 0x0090
local WM_NCMOUSEMOVE            = 0x00A0
local WM_NCLBUTTONDOWN          = 0x00A1
local WM_NCLBUTTONDBLCLK        = 0x00A3
local WM_NCRBUTTONDBLCLK        = 0x00A6
local WM_KEYDOWN                = 0x0100
local WM_KEYUP                  = 0x0101
local WM_CHAR                   = 0x0102
local WM_SYSCOMMAND             = 0x0112
local WM_TIMER                  = 0x0113
local WM_MOUSEMOVE              = 0x0200
local WM_LBUTTONDOWN            = 0x0201
local WM_LBUTTONUP              = 0x0202
local WM_RBUTTONDOWN            = 0x0204
local WM_RBUTTONUP              = 0x0205
local WM_ENTERSIZEMOVE          = 0x0231
local WM_SIZING                 = 0x0214
local WM_IME_SETCONTEXT         = 0x0281
local WM_IME_NOTIFY             = 0x0282
local WM_NCMOUSELEAVE           = 0x02A2
local WM_DWMNCRENDERINGCHANGED  = 0x031F
local WM_DWMCOMPOSITIONCHANGED  = 0x031E
local WM_DWMCOLORIZATIONCOLORCHANGED = 0x0320

-- DrawText format constants
local DT_SINGLELINE = 0x00000020
local DT_CENTER     = 0x00000001
local DT_VCENTER    = 0x00000004

-- Constants
local WS_EX_CLIENTEDGE = 0x00000200
local WS_OVERLAPPEDWINDOW = 0x00CF0000
local CW_USEDEFAULT = 0x80000000
local SW_SHOWDEFAULT = 10
local PM_REMOVE = 0x0001
local IDI_APPLICATION = 32512
local IDC_ARROW = 32512
local COLOR_WINDOW = 5
local CS_HREDRAW = 0x0002
local CS_VREDRAW = 0x0001
local CS_OWNDC = 0x0020
local LTGRAY_BRUSH = 1
local TRANSPARENT = 1

-- Constants for font creation
local FW_NORMAL = 400
local DEFAULT_CHARSET = 1
local OUT_DEFAULT_PRECIS = 0
local CLIP_DEFAULT_PRECIS = 0
local PROOF_QUALITY = 2
local DEFAULT_PITCH = 0
local FF_SWISS = 32
local ANTIALIASED_QUALITY = 4

-- Structure sizes
local PAINTSTRUCT_SIZE = 72 -- Size of PAINTSTRUCT on 64-bit Windows
local RECT_SIZE        = 16 -- Size of RECT structure
local WNDCLASS_SIZE    = 80 -- Size of WNDCLASSEX structure
local MESSAGE_SIZE     = 48 -- Size of MSG structure on 64-bit systems

-- Others
local EXIT_SUCCESS = 0

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function SafeAlloc (Size, InitialData)
  local Pointer = malloc(Size)
  if (Pointer == NULL) then
    print(debug.traceback())
    error("malloc returned NULL")
  else
    memset(Pointer, 0, Size)
    if (InitialData) then
      LibFFI.writepointer(Pointer, 0, InitialData)
    end
  end
  -- return value
  return Pointer
end

--------------------------------------------------------------------------------
-- GLOBALS                                                                    --
--------------------------------------------------------------------------------

local GlobalPaintStruct = SafeAlloc(PAINTSTRUCT_SIZE)
local GlobalRectangle   = SafeAlloc(RECT_SIZE)
local WndClassPtr       = SafeAlloc(WNDCLASS_SIZE)
local MessagePtr        = SafeAlloc(MESSAGE_SIZE)

-- Active Win32 timer id (created later with SetTimer)
local GlobalTimerId = 0 -- 0 is invalid timer ID
-- Count of WM_TIMER triggers for our timer
local GlobalTimerCount = 0
-- After this many triggers we'll exit the message loop
local MAX_TIMER_COUNT = 6

-- Class name allocation
local ClassName    = "MAIN_WindowClass\0"
local ClassNamePtr = SafeAlloc(#ClassName, ClassName)

local IconResourceId   = LibFFI.newpointer(0, IDI_APPLICATION)
local CursorResourceId = LibFFI.newpointer(0, IDC_ARROW)
local HIcon            = LoadIcon(NULL,   IconResourceId)
local HCursor          = LoadCursor(NULL, CursorResourceId)
local HInstance        = GetModuleHandle(nil)

assert(HIcon     ~= NULL)
assert(HCursor   ~= NULL)
assert(HInstance ~= NULL)

local BACKGROUND_BRUSH = GetStockObject(LTGRAY_BRUSH)

local function StrDup (LuaString)
  local CopiedPointer = StrDupAFunction(LuaString)
  if (CopiedPointer == NULL) then
    error(format("StrDupA failed for string: %s", LuaString))
  end
  return CopiedPointer
end

-- We need to make sure the font name is not garbage collected
-- Because the C side will keep point to it
local FONT_NAME = StrDup("Microsoft YaHei\x00")

-- Create a larger font (64 points)
local GlobalFont = CreateFont(
  64,                        -- Height
  0,                         -- Width (0 = auto)
  0,                         -- Escapement
  0,                         -- Orientation
  FW_NORMAL,                 -- Weight
  0,                         -- Italic
  0,                         -- Underline
  0,                         -- StrikeOut
  DEFAULT_CHARSET,          -- CharSet
  OUT_DEFAULT_PRECIS,       -- OutPrecision
  CLIP_DEFAULT_PRECIS,      -- ClipPrecision
  ANTIALIASED_QUALITY,      -- Quality
  DEFAULT_PITCH | FF_SWISS, -- PitchAndFamily
  FONT_NAME                 -- FontName (supports Chinese characters)
)

-- This UTF-16 string include an ending 0 character
local GLOBAL_Text        = Utf8ToUtf16("Hello, World! 你好世界！")
local GLOBAL_TextPointer = malloc(#GLOBAL_Text)
LibFFI.writepointer(GLOBAL_TextPointer, 0, GLOBAL_Text)
-- Release initial Lua memory
GLOBAL_Text = nil

--------------------------------------------------------------------------------
-- TESTS                                                                      --
--------------------------------------------------------------------------------

assert(HIcon   ~= NULL)
assert(HCursor ~= NULL)
assert(BACKGROUND_BRUSH ~= NULL)
assert(GlobalFont ~= NULL)

--------------------------------------------------------------------------------
-- WINDOW PROCEDURE                                                           --
--------------------------------------------------------------------------------

local Win32Messages = {
  [WM_DESTROY] = "WM_DESTROY",
  [WM_SIZE] = "WM_SIZE",
  [WM_PAINT] = "WM_PAINT",
  [WM_ERASEBKGND] = "WM_ERASEBKGND",
  [WM_CREATE] = "WM_CREATE",
  [WM_MOVE] = "WM_MOVE",
  [WM_ACTIVATE] = "WM_ACTIVATE",
  [WM_SETFOCUS] = "WM_SETFOCUS",
  [WM_KILLFOCUS] = "WM_KILLFOCUS",
  [WM_CLOSE] = "WM_CLOSE",
  [WM_SHOWWINDOW] = "WM_SHOWWINDOW",
  [WM_ACTIVATEAPP] = "WM_ACTIVATEAPP",
  [WM_SETCURSOR] = "WM_SETCURSOR",
  [WM_GETMINMAXINFO] = "WM_GETMINMAXINFO",
  [WM_WINDOWPOSCHANGING] = "WM_WINDOWPOSCHANGING",
  [WM_WINDOWPOSCHANGED] = "WM_WINDOWPOSCHANGED",
  [WM_INPUTLANGCHANGE] = "WM_INPUTLANGCHANGE",
  [WM_NOTIFY] = "WM_NOTIFY",
  [WM_GETICON] = "WM_GETICON",
  [WM_NCCREATE] = "WM_NCCREATE",
  [WM_NCDESTROY] = "WM_NCDESTROY",
  [WM_NCCALCSIZE] = "WM_NCCALCSIZE",
  [WM_NCHITTEST] = "WM_NCHITTEST",
  [WM_NCPAINT] = "WM_NCPAINT",
  [WM_NCACTIVATE] = "WM_NCACTIVATE",
  [WM_NCUAHDRAWCAPTION] = "WM_NCUAHDRAWCAPTION",
  [WM_NCMOUSEMOVE] = "WM_NCMOUSEMOVE",
  [WM_NCLBUTTONDOWN] = "WM_NCLBUTTONDOWN",
  [WM_NCLBUTTONDBLCLK] = "WM_NCLBUTTONDBLCLK",
  [WM_NCRBUTTONDBLCLK] = "WM_NCRBUTTONDBLCLK",
  [WM_KEYDOWN] = "WM_KEYDOWN",
  [WM_KEYUP] = "WM_KEYUP",
  [WM_CHAR] = "WM_CHAR",
  [WM_SYSCOMMAND] = "WM_SYSCOMMAND",
  [WM_TIMER] = "WM_TIMER",
  [WM_MOUSEMOVE] = "WM_MOUSEMOVE",
  [WM_LBUTTONDOWN] = "WM_LBUTTONDOWN",
  [WM_LBUTTONUP] = "WM_LBUTTONUP",
  [WM_RBUTTONDOWN] = "WM_RBUTTONDOWN",
  [WM_RBUTTONUP] = "WM_RBUTTONUP",
  [WM_ENTERSIZEMOVE] = "WM_ENTERSIZEMOVE",
  [WM_SIZING] = "WM_SIZING",
  [WM_IME_SETCONTEXT] = "WM_IME_SETCONTEXT",
  [WM_IME_NOTIFY] = "WM_IME_NOTIFY",
  [WM_NCMOUSELEAVE] = "WM_NCMOUSELEAVE",
  [WM_DWMNCRENDERINGCHANGED] = "WM_DWMNCRENDERINGCHANGED",
  [WM_DWMCOMPOSITIONCHANGED] = "WM_DWMCOMPOSITIONCHANGED",
  [WM_QUIT] = "WM_QUIT",
  [WM_DWMCOLORIZATIONCOLORCHANGED] = "WM_DWMCOLORIZATIONCOLORCHANGED",
  [0xC0B1] = "WM_APP+0xB1",  -- Custom application message
  [0x0060] = "WM_USER+0x20", -- Custom user message
  [0xC053] = "WM_APP+0x53",  -- Custom application message
  [0x0215] = "WM_CAPTURECHANGED",
  [0x0232] = "WM_EXITSIZEMOVE"
}

local function WindowProcedure (Window, Message, WParam, LParam)
  print(format(" WIN received 0x%04X %s", Message, Win32Messages[Message] or "Unknown"))
  if (Message == WM_DESTROY) then
    -- Stop the timer if it's active
    if (GlobalTimerId ~= 0) then
      KillTimer(Window, GlobalTimerId)
      GlobalTimerId = 0
    end
    PostQuitMessage(EXIT_SUCCESS)
    return 0
  elseif (Message == WM_ERASEBKGND) then
    local DeviceContext = WParam
    if BACKGROUND_BRUSH then
      -- Get client rectangle first
      local GetClientRectResult = GetClientRect(Window, GlobalRectangle)
      if (GetClientRectResult ~= 0) then
        FillRect(DeviceContext, GlobalRectangle, BACKGROUND_BRUSH)
      end
    end
    return 1
  elseif (Message == WM_TIMER) then
    local TimerId = WParam
    if ((TimerId == GlobalTimerId) and (TimerId ~= 0)) then
      GlobalTimerCount = (GlobalTimerCount + 1)
      print(format(" WIN TIMER fired id=%s count=%d", tostring(TimerId), GlobalTimerCount))
      -- If we've reached the max count, stop the loop
      if (GlobalTimerCount >= MAX_TIMER_COUNT) then
        KillTimer(Window, GlobalTimerId)
        GlobalTimerId = 0
        PostQuitMessage(EXIT_SUCCESS)
      end
    end
    return 0
  elseif (Message == WM_SIZE) then
    -- Invalidate the window to force a redraw when resized
    -- Pass 0 as the rectangle pointer (NULL) and 1 as erase parameter
    InvalidateRect(Window, 0, 1)
    return 0
  elseif (Message == WM_PAINT) then
    local DeviceContext = BeginPaint(Window, GlobalPaintStruct)
    if (DeviceContext == NULL) then
      print("ERROR: BeginPaint failed")
      return DefWindowProc(Window, Message, WParam, LParam)
    end
    local GetClientRectResult = GetClientRect(Window, GlobalRectangle)
    if (GetClientRectResult == 0) then
      print("ERROR: GetClientRect failed")
      EndPaint(Window, GlobalPaintStruct)
      return DefWindowProc(Window, Message, WParam, LParam)
    end
    -- Fill background with white
    FillRect(DeviceContext, GlobalRectangle, BACKGROUND_BRUSH)
    -- Select the font into the device context
    local OldFont = SelectObject(DeviceContext, GlobalFont)
    -- Set transparent background mode
    SetBkMode(DeviceContext, TRANSPARENT)
    -- Draw UTF-16 string
    local DrawTextResult = DrawText(
      DeviceContext,
      GLOBAL_TextPointer,
      -1, -- -1 means null-terminated string
      GlobalRectangle,
      (DT_SINGLELINE | DT_CENTER | DT_VCENTER)
    )
    -- Restore the old font
    SelectObject(DeviceContext, OldFont)
    EndPaint(Window, GlobalPaintStruct)
    return 0
  end
  -- Default behaviour
  return DefWindowProc(Window, Message, WParam, LParam)
end

local function WriteStructField (Pointer, Offset, Value, Format)
  if (Value == nil) then
    print("ERROR: WriteStructField with nil value")
    print(debug.traceback())
    os.exit(1)
  -- Handle pointer values
  elseif (type(Value) == "userdata") then
    -- For pointer values, we need to handle them differently now
    -- We'll need to get the actual pointer value and write it directly
    local PointerValue = LibFFI.convertpointer(Value, "string")
    LibFFI.writepointer(Pointer, Offset, PointerValue)
  else
    assert(Format, "Format parameter required for non-pointer values")
    local BinaryString = pack(Format, Value)
    assert(BinaryString, format("Failed to pack Value at Offset %d", Offset))
    LibFFI.writepointer(Pointer, Offset, BinaryString)
  end
end

local function CreateWindow ()
  -- Create window procedure closure
  local WindowProcClosure, WindowProcPtr = LibFFI.newcfunction(WindowProcedure, "sint64", "pointer", "uint32", "uint64", "sint64")
  assert(WindowProcPtr)  
  -- Write WNDCLASSPTR structure
  -- cbSize (4 bytes)
  WriteStructField(WndClassPtr, 0, WNDCLASS_SIZE, "<I4")
  -- style (4 bytes) - Add CS_HREDRAW and CS_VREDRAW
  WriteStructField(WndClassPtr, 4, CS_HREDRAW | CS_VREDRAW | CS_OWNDC, "<I4")
  -- lpfnWndProc (8 bytes pointer)
  WriteStructField(WndClassPtr, 8, WindowProcPtr)
  -- cbClsExtra (4 bytes)
  WriteStructField(WndClassPtr, 16, 0, "<I4")
  -- cbWndExtra (4 bytes)
  WriteStructField(WndClassPtr, 20, 0, "<I4")
  -- hInstance (8 bytes pointer)
  WriteStructField(WndClassPtr, 24, HInstance)  
  -- hIcon (8 bytes pointer)
  WriteStructField(WndClassPtr, 32, HIcon)
  -- hCursor (8 bytes pointer)
  WriteStructField(WndClassPtr, 40, HCursor)
  -- hbrBackground (8 bytes pointer)
  WriteStructField(WndClassPtr, 48, COLOR_WINDOW + 1, "i8")
  -- lpszMenuName (8 bytes pointer) - NULL pointer
  WriteStructField(WndClassPtr, 56, NULL)
  -- lpszClassName (8 bytes pointer)
  WriteStructField(WndClassPtr, 64, ClassNamePtr)
  -- hIconSm (8 bytes pointer)
  WriteStructField(WndClassPtr, 72, HIcon)

  -- Register the window class
  local ClassAtom = RegisterClassEx(WndClassPtr)
  assert((ClassAtom ~= 0), "RegisterClassEx failed")
  
  -- Create the window
  local Window = CreateWindowEx(
    0, -- No extended styles
    "MAIN_WindowClass",
    "Hello World",
    WS_OVERLAPPEDWINDOW,
    CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
    nil, nil, HInstance, nil
  )
  assert((Window ~= NULL), "CreateWindowEx returned NULL")
  ShowWindow(Window, SW_SHOWDEFAULT)
  UpdateWindow(Window)

  -- Start a 1-second timer (id = 1)
  local TIMER_ID = 1
  GlobalTimerId = SetTimer(Window, TIMER_ID, 1000, nil)
  assert((GlobalTimerId ~= 0), "SetTimer failed")

  local ReadToLua = LibFFI.readpointer
  -- Message loop
  local Continue = true
  while Continue do
    local Result = GetMessage(MessagePtr, nil, 0, 0) -- GetMessage is blocking
    if (Result == 0) then -- WM_QUIT received
      print("WM_QUIT received, exiting message loop")
      Continue = false
    elseif (Result == -1) then
      print("ERROR: GetMessage failed")
      Continue = false
    else
      -- Get message type
      local MessageData = ReadToLua(MessagePtr, 0, MESSAGE_SIZE)
      local MessageType = unpack("I4", MessageData, 9) -- Offset 8 + 1 for Lua indexing
      print(format("LOOP received 0x%04X %s", MessageType, Win32Messages[MessageType] or "Unknown"))
      TranslateMessage(MessagePtr)
      DispatchMessage(MessagePtr)
    end
  end
  
  -- Return the wParam from the WM_QUIT message
  local MessageData = ReadToLua(MessagePtr, 0, MESSAGE_SIZE)
  local WParam      = unpack("I8", MessageData, 17)  -- Offset 16 + 1 for Lua indexing
  return WParam
end

-- Clean up global structures at the end of the program
local function CleanupGlobalStructures ()
  free(GlobalPaintStruct)
  free(GlobalRectangle)
  free(WndClassPtr)
  DeleteObject(GlobalFont)
  -- Ensure timer is killed if still active
  if (GlobalTimerId and GlobalTimerId ~= 0) then
    KillTimer(nil, GlobalTimerId)
    GlobalTimerId = 0
  end
  free(MessagePtr)
  free(ClassNamePtr)
end

-- Added for testing but with debug output
print("Starting CreateWindow function...")
local Success, Result = pcall(CreateWindow)
if not Success then
  print("ERROR: Exception in CreateWindow: " .. tostring(Result))
else
  print("CreateWindow function returned: " .. tostring(Result))
end

-- Clean up global structures
CleanupGlobalStructures()

--------------------------------------------------------------------------------
-- TEST FINALIZERS                                                            --
--------------------------------------------------------------------------------

-- Release
print("=== GARBAGE COLLECTION ===")
collectgarbage()
-- Fake it
malloc=nil
free=nil
memset=nil
RegisterClassEx=nil
PostQuitMessage=nil
BeginPaint=nil
GetClientRect=nil
DrawText=nil
EndPaint=nil
DefWindowProc=nil
CreateWindowEx=nil
ShowWindow=nil
UpdateWindow=nil
PeekMessage=nil
TranslateMessage=nil
DispatchMessage=nil
LoadIcon=nil
LoadCursor=nil
InvalidateRect=nil
FillRect=nil
GetStockObject=nil
-- Try harder
print("=== GARBAGE COLLECTION 2 ===")
collectgarbage()
