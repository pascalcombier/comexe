--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local libffi  = require("com.ffi")
local win32   = require("com.win32")
local easycom = require("com.win32.easycom")
local runtime = require("com.runtime")
local event   = require("com.event")
local Json    = require("dkjson")

-- For base64 screenshot decoding
local Mbedtls = require("mbedtls")
local Base64  = require("mbedtls.base64")

local append = table.insert
local remove = table.remove
local format = string.format
local match  = string.match

local JsonEncode = Json.encode
local JsonDecode = Json.decode

local utf8to16        = win32.utf8to16
local pointertostring = win32.pointertostring

local NULL          = libffi.NULL
local uint32        = libffi.uint32
local uint64        = libffi.uint64
local sint32        = libffi.sint32
local sint64        = libffi.sint64
local pointer       = libffi.pointer
local newinstance   = libffi.newinstance
local newpointer    = libffi.newpointer
local readvalue     = libffi.readvalue
local derefpointer  = libffi.derefpointer
local sizeof        = libffi.sizeof
local newcallback   = libffi.newcallback
local stringpointer = libffi.stringpointer
local luaref        = runtime.ref
local newinterface  = easycom.newinterface
local runonce       = event.runonce

--------------------------------------------------------------------------------
-- JSON performances                                                          --
--------------------------------------------------------------------------------

-- Request Json to use lpeg library
Json.use_lpeg()

--------------------------------------------------------------------------------
-- FFI IMPORTS                                                                --
--------------------------------------------------------------------------------

-- @BEGIN FfiHeader("BindWin32Base", "libffi", "win32-base.h")
-- @OUTPUT
-- Constants
local COLOR_WINDOW = 5
local CS_HREDRAW = 2
local CS_VREDRAW = 1
local CW_USEDEFAULT = 2147483648
local DT_CENTER = 1
local DT_SINGLELINE = 32
local DT_VCENTER = 4
local EXIT_SUCCESS = 0
local IDC_ARROW = 32512
local IDI_APPLICATION = 32512
local SW_SHOWDEFAULT = 10
local WM_CLOSE = 16
local WM_DESTROY = 2
local WM_PAINT = 15
local WM_SIZE = 5
local WM_TIMER = 275
local WS_CLIPCHILDREN = 33554432
local WS_CLIPSIBLINGS = 67108864
local WS_OVERLAPPEDWINDOW = 13565952
-- Structures
local RECT
local WNDCLASSEX
local MSG
local PAINTSTRUCT
-- Functions
local BeginPaint
local CoTaskMemFree
local CreateWindowExW
local DefWindowProcW
local DestroyWindow
local DispatchMessageW
local DrawTextW
local EndPaint
local GetClientRect
local GetMessageW
local GetModuleHandleA
local KillTimer
local LoadCursorA
local LoadIconA
local PostMessageW
local PostQuitMessage
local RegisterClassExW
local SetTimer
local ShowWindow
local TranslateMessage
local UnregisterClassW
local UpdateWindow
-- Binding function
local function BindWin32Base (Library)
  RECT = libffi.newstructure("RECT",
    libffi.sint32, "left",
    libffi.sint32, "top",
    libffi.sint32, "right",
    libffi.sint32, "bottom"
  )
  WNDCLASSEX = libffi.newstructure("WNDCLASSEX",
    libffi.uint32, "cbSize",
    libffi.uint32, "style",
    libffi.pointer, "lpfnWndProc",
    libffi.sint32, "cbClsExtra",
    libffi.sint32, "cbWndExtra",
    libffi.pointer, "hInstance",
    libffi.pointer, "hIcon",
    libffi.pointer, "hCursor",
    libffi.pointer, "hbrBackground",
    libffi.cstring, "lpszMenuName",
    libffi.cstring, "lpszClassName",
    libffi.pointer, "hIconSm"
  )
  MSG = libffi.newstructure("MSG",
    libffi.pointer, "hwnd",
    libffi.uint32, "message",
    libffi.uint64, "wParam",
    libffi.sint64, "lParam",
    libffi.uint32, "time",
    libffi.sint32, "pt_x",
    libffi.sint32, "pt_y",
    libffi.uint32, "lPrivate"
  )
  PAINTSTRUCT = libffi.newstructure("PAINTSTRUCT",
    libffi.pointer, "hdc",
    libffi.sint32, "fErase",
    RECT, "rcPaint",
    libffi.sint32, "fRestore",
    libffi.sint32, "fIncUpdate",
    libffi.sint64, "reserved01",
    libffi.sint64, "reserved02",
    libffi.sint64, "reserved03",
    libffi.sint64, "reserved04"
  )
  BeginPaint = Library:bind(libffi.pointer, "BeginPaint", libffi.pointer, libffi.pointer)
  CoTaskMemFree = Library:bind(libffi.void, "CoTaskMemFree", libffi.pointer)
  CreateWindowExW = Library:bind(libffi.pointer, "CreateWindowExW", libffi.uint32, libffi.pointer, libffi.pointer, libffi.uint32, libffi.sint32, libffi.sint32, libffi.sint32, libffi.sint32, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer)
  DefWindowProcW = Library:bind(libffi.sint64, "DefWindowProcW", libffi.pointer, libffi.uint32, libffi.uint64, libffi.sint64)
  DestroyWindow = Library:bind(libffi.sint32, "DestroyWindow", libffi.pointer)
  DispatchMessageW = Library:bind(libffi.sint64, "DispatchMessageW", libffi.pointer)
  DrawTextW = Library:bind(libffi.sint32, "DrawTextW", libffi.pointer, libffi.pointer, libffi.sint32, libffi.pointer, libffi.uint32)
  EndPaint = Library:bind(libffi.sint32, "EndPaint", libffi.pointer, libffi.pointer)
  GetClientRect = Library:bind(libffi.sint32, "GetClientRect", libffi.pointer, libffi.pointer)
  GetMessageW = Library:bind(libffi.sint32, "GetMessageW", libffi.pointer, libffi.pointer, libffi.uint32, libffi.uint32)
  GetModuleHandleA = Library:bind(libffi.pointer, "GetModuleHandleA", libffi.pointer)
  KillTimer = Library:bind(libffi.sint32, "KillTimer", libffi.pointer, libffi.uint64)
  LoadCursorA = Library:bind(libffi.pointer, "LoadCursorA", libffi.pointer, libffi.pointer)
  LoadIconA = Library:bind(libffi.pointer, "LoadIconA", libffi.pointer, libffi.pointer)
  PostMessageW = Library:bind(libffi.sint32, "PostMessageW", libffi.pointer, libffi.uint32, libffi.uint64, libffi.sint64)
  PostQuitMessage = Library:bind(libffi.void, "PostQuitMessage", libffi.sint32)
  RegisterClassExW = Library:bind(libffi.uint16, "RegisterClassExW", libffi.pointer)
  SetTimer = Library:bind(libffi.uint64, "SetTimer", libffi.pointer, libffi.uint64, libffi.uint32, libffi.pointer)
  ShowWindow = Library:bind(libffi.sint32, "ShowWindow", libffi.pointer, libffi.sint32)
  TranslateMessage = Library:bind(libffi.sint32, "TranslateMessage", libffi.pointer)
  UnregisterClassW = Library:bind(libffi.sint32, "UnregisterClassW", libffi.pointer, libffi.pointer)
  UpdateWindow = Library:bind(libffi.sint32, "UpdateWindow", libffi.pointer)
end
-- @END

-- @BEGIN FfiHeader("BindWebview", "libffi", "webview2.h")
-- @OUTPUT
-- Constants
local COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC = 0
local E_FAIL = 2147500037
local E_NOINTERFACE = 2147500034
local S_OK = 0
-- Structures
local RECT
local COREWEBVIEW2_COLOR
local POINT
local ICoreWebView2EnvironmentVtbl
local ICoreWebView2ControllerVtbl
local ICoreWebView2Vtbl
local ICoreWebView2SettingsVtbl
local ICoreWebView2WebMessageReceivedEventArgsVtbl
-- Functions
local CreateCoreWebView2EnvironmentWithOptions
local GetAvailableCoreWebView2BrowserVersionString
-- Binding function
local function BindWebview (Library)
  RECT = libffi.newstructure("RECT",
    libffi.sint32, "left",
    libffi.sint32, "top",
    libffi.sint32, "right",
    libffi.sint32, "bottom"
  )
  COREWEBVIEW2_COLOR = libffi.newstructure("COREWEBVIEW2_COLOR",
    libffi.uint8, "A",
    libffi.uint8, "R",
    libffi.uint8, "G",
    libffi.uint8, "B"
  )
  POINT = libffi.newstructure("POINT",
    libffi.sint32, "x",
    libffi.sint32, "y"
  )
  ICoreWebView2EnvironmentVtbl = {
    { libffi.uint32, "QueryInterface", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "AddRef", libffi.pointer },
    { libffi.uint32, "Release", libffi.pointer },
    { libffi.uint32, "CreateCoreWebView2Controller", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateWebResourceResponse", libffi.pointer, libffi.pointer, libffi.sint32, libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_BrowserVersionString", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_NewBrowserVersionAvailable", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_NewBrowserVersionAvailable", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "CreateWebResourceRequest", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateCoreWebView2CompositionController", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateCoreWebView2PointerInfo", libffi.pointer, libffi.pointer },
    { libffi.uint32, "GetAutomationProviderForWindow", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_BrowserProcessExited", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_BrowserProcessExited", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "CreatePrintSettings", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_UserDataFolder", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_ProcessInfosChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ProcessInfosChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "GetProcessInfos", libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateContextMenuItem", libffi.pointer, libffi.pointer, libffi.pointer, libffi.sint32, libffi.pointer },
    { libffi.uint32, "CreateCoreWebView2ControllerOptions", libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateCoreWebView2ControllerWithOptions", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateCoreWebView2CompositionControllerWithOptions", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_FailureReportFolderPath", libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateSharedBuffer", libffi.pointer, libffi.uint64, libffi.pointer },
    { libffi.uint32, "GetProcessExtendedInfos", libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateWebFileSystemFileHandle", libffi.pointer, libffi.pointer, libffi.sint32, libffi.pointer },
    { libffi.uint32, "CreateWebFileSystemDirectoryHandle", libffi.pointer, libffi.pointer, libffi.sint32, libffi.pointer },
    { libffi.uint32, "CreateObjectCollection", libffi.pointer, libffi.sint32, libffi.pointer, libffi.pointer },
    { libffi.uint32, "CreateFindOptions", libffi.pointer, libffi.pointer },
  }
  ICoreWebView2ControllerVtbl = {
    { libffi.uint32, "QueryInterface", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "AddRef", libffi.pointer },
    { libffi.uint32, "Release", libffi.pointer },
    { libffi.uint32, "get_IsVisible", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsVisible", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_Bounds", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_Bounds", libffi.pointer, RECT },
    { libffi.uint32, "get_ZoomFactor", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_ZoomFactor", libffi.pointer, libffi.double },
    { libffi.uint32, "add_ZoomFactorChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ZoomFactorChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "SetBoundsAndZoomFactor", libffi.pointer, RECT, libffi.double },
    { libffi.uint32, "MoveFocus", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "add_MoveFocusRequested", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_MoveFocusRequested", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_GotFocus", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_GotFocus", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_LostFocus", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_LostFocus", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_AcceleratorKeyPressed", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_AcceleratorKeyPressed", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_ParentWindow", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_ParentWindow", libffi.pointer, libffi.pointer },
    { libffi.uint32, "NotifyParentWindowPositionChanged", libffi.pointer },
    { libffi.uint32, "Close", libffi.pointer },
    { libffi.uint32, "get_CoreWebView2", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_DefaultBackgroundColor", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_DefaultBackgroundColor", libffi.pointer, COREWEBVIEW2_COLOR },
    { libffi.uint32, "get_RasterizationScale", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_RasterizationScale", libffi.pointer, libffi.double },
    { libffi.uint32, "get_ShouldDetectMonitorScaleChanges", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_ShouldDetectMonitorScaleChanges", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "add_RasterizationScaleChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_RasterizationScaleChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_BoundsMode", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_BoundsMode", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_AllowExternalDrop", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_AllowExternalDrop", libffi.pointer, libffi.sint32 },
  }
  ICoreWebView2Vtbl = {
    { libffi.uint32, "QueryInterface", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "AddRef", libffi.pointer },
    { libffi.uint32, "Release", libffi.pointer },
    { libffi.uint32, "get_Settings", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_Source", libffi.pointer, libffi.pointer },
    { libffi.uint32, "Navigate", libffi.pointer, libffi.pointer },
    { libffi.uint32, "NavigateToString", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_NavigationStarting", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_NavigationStarting", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_ContentLoading", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ContentLoading", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_SourceChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_SourceChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_HistoryChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_HistoryChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_NavigationCompleted", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_NavigationCompleted", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_FrameNavigationStarting", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_FrameNavigationStarting", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_FrameNavigationCompleted", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_FrameNavigationCompleted", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_ScriptDialogOpening", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ScriptDialogOpening", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_PermissionRequested", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_PermissionRequested", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_ProcessFailed", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ProcessFailed", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "AddScriptToExecuteOnDocumentCreated", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "RemoveScriptToExecuteOnDocumentCreated", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "ExecuteScript", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "CapturePreview", libffi.pointer, libffi.sint32, libffi.pointer, libffi.pointer },
    { libffi.uint32, "Reload", libffi.pointer },
    { libffi.uint32, "PostWebMessageAsJson", libffi.pointer, libffi.pointer },
    { libffi.uint32, "PostWebMessageAsString", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_WebMessageReceived", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_WebMessageReceived", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "CallDevToolsProtocolMethod", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_BrowserProcessId", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_CanGoBack", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_CanGoForward", libffi.pointer, libffi.pointer },
    { libffi.uint32, "GoBack", libffi.pointer },
    { libffi.uint32, "GoForward", libffi.pointer },
    { libffi.uint32, "GetDevToolsProtocolEventReceiver", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "Stop", libffi.pointer },
    { libffi.uint32, "add_NewWindowRequested", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_NewWindowRequested", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_DocumentTitleChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_DocumentTitleChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_DocumentTitle", libffi.pointer, libffi.pointer },
    { libffi.uint32, "AddHostObjectToScript", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "RemoveHostObjectFromScript", libffi.pointer, libffi.pointer },
    { libffi.uint32, "OpenDevToolsWindow", libffi.pointer },
    { libffi.uint32, "add_ContainsFullScreenElementChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ContainsFullScreenElementChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_ContainsFullScreenElement", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_WebResourceRequested", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_WebResourceRequested", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "AddWebResourceRequestedFilter", libffi.pointer, libffi.pointer, libffi.sint32 },
    { libffi.uint32, "RemoveWebResourceRequestedFilter", libffi.pointer, libffi.pointer, libffi.sint32 },
    { libffi.uint32, "add_WindowCloseRequested", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_WindowCloseRequested", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_WebResourceResponseReceived", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_WebResourceResponseReceived", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "NavigateWithWebResourceRequest", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_DOMContentLoaded", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_DOMContentLoaded", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_CookieManager", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_Environment", libffi.pointer, libffi.pointer },
    { libffi.uint32, "TrySuspend", libffi.pointer, libffi.pointer },
    { libffi.uint32, "Resume", libffi.pointer },
    { libffi.uint32, "get_IsSuspended", libffi.pointer, libffi.pointer },
    { libffi.uint32, "SetVirtualHostNameToFolderMapping", libffi.pointer, libffi.pointer, libffi.pointer, libffi.sint32 },
    { libffi.uint32, "ClearVirtualHostNameToFolderMapping", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_FrameCreated", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_FrameCreated", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_DownloadStarting", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_DownloadStarting", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_ClientCertificateRequested", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ClientCertificateRequested", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "OpenTaskManagerWindow", libffi.pointer },
    { libffi.uint32, "PrintToPdf", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_IsMutedChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_IsMutedChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_IsMuted", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsMuted", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "add_IsDocumentPlayingAudioChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_IsDocumentPlayingAudioChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_IsDocumentPlayingAudio", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_IsDefaultDownloadDialogOpenChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_IsDefaultDownloadDialogOpenChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_IsDefaultDownloadDialogOpen", libffi.pointer, libffi.pointer },
    { libffi.uint32, "OpenDefaultDownloadDialog", libffi.pointer },
    { libffi.uint32, "CloseDefaultDownloadDialog", libffi.pointer },
    { libffi.uint32, "get_DefaultDownloadDialogCornerAlignment", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_DefaultDownloadDialogCornerAlignment", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_DefaultDownloadDialogMargin", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_DefaultDownloadDialogMargin", libffi.pointer, POINT },
    { libffi.uint32, "add_BasicAuthenticationRequested", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_BasicAuthenticationRequested", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "CallDevToolsProtocolMethodForSession", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_ContextMenuRequested", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ContextMenuRequested", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_StatusBarTextChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_StatusBarTextChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_StatusBarText", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_Profile", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_ServerCertificateErrorDetected", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ServerCertificateErrorDetected", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "ClearServerCertificateErrorActions", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_FaviconChanged", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_FaviconChanged", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_FaviconUri", libffi.pointer, libffi.pointer },
    { libffi.uint32, "GetFavicon", libffi.pointer, libffi.sint32, libffi.pointer },
    { libffi.uint32, "Print", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "ShowPrintUI", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "PrintToPdfStream", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "PostSharedBufferToScript", libffi.pointer, libffi.pointer, libffi.sint32, libffi.pointer },
    { libffi.uint32, "add_LaunchingExternalUriScheme", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_LaunchingExternalUriScheme", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_MemoryUsageTargetLevel", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_MemoryUsageTargetLevel", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_FrameId", libffi.pointer, libffi.pointer },
    { libffi.uint32, "ExecuteScriptWithResult", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "AddWebResourceRequestedFilterWithRequestSourceKinds", libffi.pointer, libffi.pointer, libffi.sint32, libffi.sint32 },
    { libffi.uint32, "RemoveWebResourceRequestedFilterWithRequestSourceKinds", libffi.pointer, libffi.pointer, libffi.sint32, libffi.sint32 },
    { libffi.uint32, "PostWebMessageAsJsonWithAdditionalObjects", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_NotificationReceived", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_NotificationReceived", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_SaveAsUIShowing", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_SaveAsUIShowing", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "ShowSaveAsUI", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_SaveFileSecurityCheckStarting", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_SaveFileSecurityCheckStarting", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "add_ScreenCaptureStarting", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_ScreenCaptureStarting", libffi.pointer, libffi.uint64 },
    { libffi.uint32, "get_Find", libffi.pointer, libffi.pointer },
    { libffi.uint32, "add_DedicatedWorkerCreated", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "remove_DedicatedWorkerCreated", libffi.pointer, libffi.uint64 },
  }
  ICoreWebView2SettingsVtbl = {
    { libffi.uint32, "QueryInterface", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "AddRef", libffi.pointer },
    { libffi.uint32, "Release", libffi.pointer },
    { libffi.uint32, "get_IsScriptEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsScriptEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_IsWebMessageEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsWebMessageEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_AreDefaultScriptDialogsEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_AreDefaultScriptDialogsEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_IsStatusBarEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsStatusBarEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_AreDevToolsEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_AreDevToolsEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_AreDefaultContextMenusEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_AreDefaultContextMenusEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_AreHostObjectsAllowed", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_AreHostObjectsAllowed", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_IsZoomControlEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsZoomControlEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_IsBuiltInErrorPageEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsBuiltInErrorPageEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_UserAgent", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_UserAgent", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_AreBrowserAcceleratorKeysEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_AreBrowserAcceleratorKeysEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_IsPasswordAutosaveEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsPasswordAutosaveEnabled", libffi.pointer, libffi.sint32 },
    { libffi.uint32, "get_IsGeneralAutofillEnabled", libffi.pointer, libffi.pointer },
    { libffi.uint32, "put_IsGeneralAutofillEnabled", libffi.pointer, libffi.sint32 },
  }
  ICoreWebView2WebMessageReceivedEventArgsVtbl = {
    { libffi.uint32, "QueryInterface", libffi.pointer, libffi.pointer, libffi.pointer },
    { libffi.uint32, "AddRef", libffi.pointer },
    { libffi.uint32, "Release", libffi.pointer },
    { libffi.uint32, "get_Source", libffi.pointer, libffi.pointer },
    { libffi.uint32, "get_WebMessageAsJson", libffi.pointer, libffi.pointer },
    { libffi.uint32, "TryGetWebMessageAsString", libffi.pointer, libffi.pointer },
  }
  CreateCoreWebView2EnvironmentWithOptions = Library:bind(libffi.uint32, "CreateCoreWebView2EnvironmentWithOptions", libffi.pointer, libffi.pointer, libffi.pointer, libffi.pointer)
  GetAvailableCoreWebView2BrowserVersionString = Library:bind(libffi.uint32, "GetAvailableCoreWebView2BrowserVersionString", libffi.pointer, libffi.pointer)
end
-- @END

--------------------------------------------------------------------------------
-- SOFTWARE DESIGN                                                            --
--------------------------------------------------------------------------------

-- IWEBVIEW DOC
--
-- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/threading-model
--
-- > After you run an event handler and begin a message loop, an event handler
-- > or completion callback cannot be run in a re-entrant manner. If a WebView2
-- > app tries to create a nested message loop or modal UI synchronously within
-- > a WebView2 event handler, this approach leads to attempted reentrancy.
-- > Such reentrancy isn't supported in WebView2 and would leave the event
-- > handler in the stack indefinitely
--
-- STA: Single-Threaded Apartment
--
-- Webview2 is a COM STA object: it must be created and called on the UI
-- thread. WebView methods calls from WebView callbacks are allowed, but a
-- callback must never start a nested message loop or modal UI (like win32
-- dialogs).
--
-- We use WM_APP_FLUSH_EVENTS mecanism to ensure PostWebMessageAsJson runs from
-- the main message loop. To keep it simple, we use the same mecanism for
-- WEBVIEW_MethodSend. So, we have a unified mecanism for event/callbacks.
--
--
-- EVENTS FROM LLM (agent-worker)
--
-- They are fetched by polling: WM_TIMER. We could immediatly call WebView with
-- WebView:PostWebMessageAsJson. But to keep the design simple, we use the same
-- event management for both IWebView callbacks and agent-worker: using event
-- queue and posting WM_APP_FLUSH_EVENTS.
--
--
-- WEBVIEW ExecuteScript
--
-- We did NOT implement ExecuteScript, because it does not bring much value
-- compared to PostWebMessageAsJson.
--
-- PostWebMessageAsJson (send) vs ExecuteScript (not implemented):
--
--   WebView:send(table) uses PostWebMessageAsJson internally.
--     Lua table -> JSON -> enqueue -> PostWebMessageAsJson -> JS receives
--     via addEventListener('message'). Bidirectional: JS replies via
--     postMessage() -> WebMessageReceived -> onmessage callback.
--
--   ExecuteScript would run JS code directly in the page context without a
--     listener. Not implemented because it does not add much benefit over
--     PostWebMessageAsJson. (ExecuteScript does not return complex Javascript
--     values, so one also need the script to send back values with same
--     postMessage mecanism).
--

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES                                                           --
--------------------------------------------------------------------------------

-- WebView2 API use need pointer to pointers...
local SharedPointerArray = libffi.newarray(pointer, 1)
local SharedPointer      = SharedPointerArray:getpointer()

-- Webview and window management
local WebViewByHwnd = {}
local WindowCount   = 0
local HInstance

-- Custom win32 loop message
local WM_POLL_TIMER_ID    = 1
local WM_APP_FLUSH_EVENTS = (0x8000 + 1)

-- At that moment, RECT and PAINTSTRUCT are not defined yet, so we can't
-- allocate global RECT and PAINTSTRUCT. They will be allocated later by
-- AllocateGlobalObjects and reused all the time
local ClientRect
local ClientRectPointer
local PaintStructInstance
local PaintStructPointer

-- The user data directory is provided by the user via
-- InitializeWebView(UserDataDir). When not provided, the default WebView2
-- folder is used: "program.exe.WebView2" in the same directory, which can be an
-- issue for write-protected folders such as "Program Files"
local WebViewUserDataDirPointer = NULL

--------------------------------------------------------------------------------
-- STATIC STRINGS                                                             --
--------------------------------------------------------------------------------

local LoadingUtf16       = utf8to16("Loading...")
local LoadingTextPointer = stringpointer(LoadingUtf16)
local ClassNameUtf16     = utf8to16("ComExeAgentWebViewClass")
local ClassNamePointer   = stringpointer(ClassNameUtf16)

-- prevent runtime from releasing, so that the pointers are always valid
luaref(LoadingUtf16)
luaref(ClassNameUtf16)

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

-- Example of UiEvent:
--
-- { type = "host.append_block", kind = Kind, text = Text, conversationId = ConvId }
--
-- The pending events will be enqueued until WebView change to non-NULL
local function FlushEventQueue (WebView)
  local ComWebView = WebView.ComWebView
  if (ComWebView ~= NULL) then
    local Queue = WebView.EventQueue
    local Count = #Queue
    for Index = 1, Count do
      local UiEvent = Queue[Index]
      if UiEvent then
        local UiEventJsonString = JsonEncode(UiEvent)
        if UiEventJsonString then
          local JsonUtf16 = utf8to16(UiEventJsonString)
          if JsonUtf16 then
            local JsonUtf16Pointer = stringpointer(JsonUtf16)
            ComWebView:PostWebMessageAsJson(JsonUtf16Pointer)
          end
        end
      end
      -- Cleanup
      Queue[Index] = nil
    end
  end
end

local function ApplyControllerBounds (WebView)
  local Controller = WebView.Controller
  if (Controller ~= NULL) then
    GetClientRect(WebView.Window, ClientRectPointer)
    Controller:put_Bounds(ClientRect)
  end
end

--------------------------------------------------------------------------------
-- WEBVIEW CALLBACKS                                                          --
--------------------------------------------------------------------------------

-- API ensure that ArgsPointer is non-NULL
local function CoreMessageReceived (WebView, Sender, ArgsPointer)
  -- local data
  local UiEvent
  local Position
  local DecodeErrorString
  -- Fast way to build a Lua wrapper from COM interface pointer
  local ArgsInterface = newinterface(ArgsPointer, ICoreWebView2WebMessageReceivedEventArgsVtbl, "[in]")
  -- Retrieve WebView2 message, WebView will allocate memory to SharedPointer
  local Result = ArgsInterface:TryGetWebMessageAsString(SharedPointer)
  if (Result == S_OK) then
    -- Dereference pointer
    local WideStringPointer = derefpointer(SharedPointer)
    -- Copy string to Lua side
    local JsonStringUtf8 = pointertostring(WideStringPointer, "utf16", "utf8")
    if JsonStringUtf8 then
      UiEvent, Position, DecodeErrorString = JsonDecode(JsonStringUtf8)
    end
    CoTaskMemFree(WideStringPointer)
  end
  -- Transfer to user event handler
  if UiEvent then
    WebView.OnMessage(WebView, UiEvent)
  end
  return S_OK
end

local function WebviewSetSettings (WebView)
  -- Retrieve data
  local ComWebView = WebView.ComWebView
  -- Retrieve settings pointer
  local Hresult = ComWebView:get_Settings(SharedPointer)
  if (Hresult == S_OK) then
    -- Deference pointer
    local SettingsPointer = derefpointer(SharedPointer)
    -- Configure the settings
    if (SettingsPointer ~= NULL) then
      -- Fast way to build a Lua wrapper from COM interface pointer
      local Settings = newinterface(SettingsPointer, ICoreWebView2SettingsVtbl, "[out]")
      -- Enable window.chrome.webview.postMessage and addEventListener('message')
      Settings:put_IsWebMessageEnabled(1)
      -- Disable the WebView2 default right-click context menu
      Settings:put_AreDefaultContextMenusEnabled(0)
      -- Disable the DevTools (F12, context menu entry, ...)
      Settings:put_AreDevToolsEnabled(0)
      -- Disable the browser accelerator keys (F12, Ctrl+F, Ctrl+P, ...)
      Settings:put_AreBrowserAcceleratorKeysEnabled(0)
    end
  end
end

-- Heuristic: detect URI scheme like "http://", "https://", "file://" (or other)
-- to choose between ComWebView:Navigate and ComWebView:NavigateToString at
-- runtime
local function ContentSeemsUri (Content)
  return match(Content, "^[A-Za-z][A-Za-z0-9+.-]*://")
end

local function WebviewStartUi (WebView)
  -- local callback implementation transfer to CoreMessageReceived
  local function OnWebMessageReceived (Sender, ArgsPointer)
    return CoreMessageReceived(WebView, Sender, ArgsPointer)
  end
  -- Create the COM handler
  local NewMessageHandler = easycom.newhandler(OnWebMessageReceived, { pointer, pointer })
  -- Save the reference
  WebView.MessageHandler = NewMessageHandler
  -- Configure the COM event handler
  local ComWebView = WebView.ComWebView
  local Hresult    = ComWebView:add_WebMessageReceived(NewMessageHandler:getpointer(), SharedPointer)
  if (Hresult == S_OK) then
    -- To unsubscribe later: call remove_WebMessageReceived(EventRegistrationToken)
    -- Not implemented yet, unclear why we would do that.
    local EventRegistrationToken = readvalue(SharedPointer, 0, uint64)
  else
    print(format("[WebView2] add_WebMessageReceived failed: 0x%08X", Hresult))
  end
  -- Load the UI
  local ContentUtf8  = WebView.Content
  local ContentUtf16 = utf8to16(ContentUtf8)
  if ContentUtf16 then
    local ContentPointer = stringpointer(ContentUtf16)
    if ContentSeemsUri(ContentUtf8) then
      Hresult = ComWebView:Navigate(ContentPointer)
      if (Hresult == S_OK) then
        WebView.Controller:MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC)
      else
        print(format("[WebView2] Navigate failed: 0x%08X", Hresult))
      end
    else
      Hresult = ComWebView:NavigateToString(ContentPointer)
      if (Hresult == S_OK) then
        WebView.Controller:MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC)
      else
        print(format("[WebView2] NavigateToString failed: 0x%08X", Hresult))
      end
    end
  end
end

-- API ensure that ControllerPointer is non-NULL
local function ControllerCompleted (WebView, ErrorCode, ControllerPointer)
  local Result
  if (ErrorCode == S_OK) then
    -- Fast way to build a Lua wrapper from COM interface pointer
    local NewController = newinterface(ControllerPointer, ICoreWebView2ControllerVtbl, "[in]")
    -- Save the reference (needed by ApplyControllerBounds)
    WebView.Controller = NewController
    -- At this stage, the widget size is 0, not visible
    ApplyControllerBounds(WebView)
    -- Retrieve the webview
    local Hresult = NewController:get_CoreWebView2(SharedPointer)
    if (Hresult == S_OK) then
      local WebViewPointer = derefpointer(SharedPointer)
      if (WebViewPointer ~= NULL) then
        local NewWebView = newinterface(WebViewPointer, ICoreWebView2Vtbl, "[out]")
        -- Save the reference
        WebView.ComWebView = NewWebView
        -- Configure the settings & start UI
        WebviewSetSettings(WebView)
        WebviewStartUi(WebView)
        -- Set result
        Result = S_OK
      else
        print("[WebView2] get_CoreWebView2 returned NULL pointer")
        Result = E_NOINTERFACE
      end
    else
      print(format("[WebView2] get_CoreWebView2 failed: 0x%08X", Hresult))
      Result = Hresult
    end
  else
    print(format("[WebView2] Controller creation failed: HRESULT 0x%08X", ErrorCode))
    Result = E_NOINTERFACE
  end
  return Result
end

-- API ensure that EnvironmentPointer is non-NULL
local function CoreEnvCompleted (WebView, ErrorCode, EnvironmentPointer)
  -- local callback, transfer to ControllerCompleted
  local function OnControllerCompleted (ErrorCode2, ControllerPointer)
    return ControllerCompleted(WebView, ErrorCode2, ControllerPointer)
  end
  local Result
  if (ErrorCode == S_OK) then
    -- Fast way to build a Lua wrapper from COM interface pointer
    local NewEnvironment = newinterface(EnvironmentPointer, ICoreWebView2EnvironmentVtbl, "[in]")
    local NewHandler     = easycom.newhandler(OnControllerCompleted, { sint32, pointer })
    local Hresult        = NewEnvironment:CreateCoreWebView2Controller(WebView.Window, NewHandler:getpointer())
    if (Hresult == S_OK) then
      WebView.Environment       = NewEnvironment
      WebView.ControllerHandler = NewHandler
      Result = S_OK
    else
      print(format("[WebView2] CreateCoreWebView2Controller failed: 0x%08X", Hresult))
      Result = E_FAIL
    end
  else
    print(format("[WebView2] Environment creation failed: HRESULT 0x%08X", ErrorCode))
    Result = E_NOINTERFACE
  end
  return Result
end

--------------------------------------------------------------------------------
-- MAIN WINDOW PROCEDURE                                                      --
--------------------------------------------------------------------------------

-- WindowProcedure(hwnd, uMsg, wParam, lParam)
local function WindowProcedure (Window, Message, WParam, LParam)
  local WebView = WebViewByHwnd[Window]
  local Result
  if (not WebView) then
    Result = DefWindowProcW(Window, Message, WParam, LParam)
  elseif (Message == WM_SIZE) then
    ApplyControllerBounds(WebView)
    Result = 0
  elseif (Message == WM_PAINT) then
    if (WebView.ComWebView == NULL) then
      local Hdc = BeginPaint(Window, PaintStructPointer)
      GetClientRect(Window, ClientRectPointer)
      DrawTextW(Hdc, LoadingTextPointer, -1, ClientRectPointer, (DT_CENTER | DT_VCENTER | DT_SINGLELINE))
      EndPaint(Window, PaintStructPointer)
      Result = 0
    else
      Result = DefWindowProcW(Window, Message, WParam, LParam)
    end
  elseif (Message == WM_TIMER) then
    runonce()
    Result = 0
  elseif (Message == WM_APP_FLUSH_EVENTS) then
    FlushEventQueue(WebView)
    Result = 0
  elseif (Message == WM_CLOSE) then
    KillTimer(Window, WM_POLL_TIMER_ID)
    local Controller = WebView.Controller
    if (Controller ~= NULL) then
      Controller:Close()
      WebView.Controller = NULL
    end
    WebView.ComWebView = NULL
    DestroyWindow(Window)
    WebView.Window = NULL
    WebViewByHwnd[Window] = nil
    Result = 0
  elseif (Message == WM_DESTROY) then
    WindowCount = (WindowCount - 1)
    if (WindowCount == 0) then
      PostQuitMessage(EXIT_SUCCESS)
    end
    Result = 0
  else
    Result = DefWindowProcW(Window, Message, WParam, LParam)
  end
  return Result
end

-- Window procedure closure (created once, prevent GC)
local WindowProcClosure = newcallback(WindowProcedure, sint64, pointer, uint32, uint64, sint64)
local WindowProcPointer = WindowProcClosure:getpointer()

luaref(WindowProcClosure) -- prevent runtime from releasing

--------------------------------------------------------------------------------
-- WINDOW CLASS (registered once)                                             --
--------------------------------------------------------------------------------

local function RegisterWindowClass ()
  -- Retrieve HInstance
  HInstance = GetModuleHandleA(NULL)
  -- Create the cursor
  local IconResId          = newpointer(0, 2)
  local CursorResourceId   = newpointer(0, IDC_ARROW)
  local WindowColorBrushId = newpointer(0, (COLOR_WINDOW + 1))
  local HIcon              = LoadIconA(HInstance, IconResId)
  if (HIcon == NULL) then
    local DefaultIconId = newpointer(0, IDI_APPLICATION)
    HIcon = LoadIconA(NULL, DefaultIconId)
  end
  local HCursor = LoadCursorA(NULL, CursorResourceId)
  -- Create the window class
  local WndClassSize = sizeof(WNDCLASSEX)
  local WndClass     = newinstance(WNDCLASSEX)
  WndClass:set("cbSize",        WndClassSize)
  WndClass:set("style",         (CS_HREDRAW | CS_VREDRAW))
  WndClass:set("lpfnWndProc",   WindowProcPointer)
  WndClass:set("cbClsExtra",    0)
  WndClass:set("cbWndExtra",    0)
  WndClass:set("hInstance",     HInstance)
  WndClass:set("hIcon",         HIcon)
  WndClass:set("hCursor",       HCursor)
  WndClass:set("hbrBackground", WindowColorBrushId)
  WndClass:set("lpszMenuName",  nil)
  WndClass:set("lpszClassName", ClassNameUtf16)
  WndClass:set("hIconSm",       HIcon)
  -- Register the class
  local Success
  local ErrorString
  local ClassAtom = RegisterClassExW(WndClass:getpointer())
  if (ClassAtom ~= 0) then
    Success = true
  else
    Success     = false
    ErrorString = "Failed to register window class"
  end
  -- Return value
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- WEBVIEW2 INITIALIZATION                                                    --
--------------------------------------------------------------------------------

local function InitializeDlls ()
  -- local data
  local Success
  local ErrorString
  -- Try to load the main DLL
  local NewLib = libffi.loadlib("WebView2Loader.dll")
  -- Load additionnal DLLs, assume no problem with those DLLs
  if NewLib then
    NewLib:addlibrary("user32.dll")
    NewLib:addlibrary("kernel32.dll")
    NewLib:addlibrary("ole32.dll")
    BindWin32Base(NewLib)
    BindWebview(NewLib)
    Success = true
  else
    Success     = false
    ErrorString = "The code execution cannot proceed because WebView2Loader.dll was not found. Reinstalling the program may fix this problem."
  end
  -- Return value
  return Success, ErrorString
end

local function AllocateGlobalObjects ()
  -- Make sure the function is called after BindWin32Base and BindWebview
  assert(RECT)
  assert(PAINTSTRUCT)
  -- Allocate globals
  ClientRect          = newinstance(RECT)
  ClientRectPointer   = ClientRect:getpointer()
  PaintStructInstance = newinstance(PAINTSTRUCT)
  PaintStructPointer  = PaintStructInstance:getpointer()
  -- Prevent runtime from releasing (the pointer is used by WM_PAINT)
  luaref(PaintStructInstance)
  -- Return value
  return true
end

local function DetectWebView2Runtime ()
  -- local data
  local VersionUtf8
  local ErrorString
  -- Request version string
  local Hresult = GetAvailableCoreWebView2BrowserVersionString(NULL, SharedPointer)
  if (Hresult == S_OK) then
    -- Dereference pointer
    local VersionUtf16Pointer = derefpointer(SharedPointer)
    -- Convert to UTF-8
    VersionUtf8 = pointertostring(VersionUtf16Pointer, "utf16", "utf8")
    -- Release the allocated string
    CoTaskMemFree(VersionUtf16Pointer)
    if (not VersionUtf8) then
      ErrorString = "Failed to read WebView2 runtime version"
    end
  else
    ErrorString = "Evergreen WebView2 Runtime could not be found"
  end
  -- Return value
  return VersionUtf8, ErrorString
end

local function SetUserDataDirectory (UserDataDirUtf8)
  if UserDataDirUtf8 then
    local UserDataDirUtf16 = utf8to16(UserDataDirUtf8)
    if UserDataDirUtf16 then
      -- Set the global pointer (shared between the instances of WebView)
      WebViewUserDataDirPointer = stringpointer(UserDataDirUtf16)
      -- Make sure the string is never released by the garbage collector
      luaref(UserDataDirUtf16)
    end
  end
end

local function InitializeWebView (UserDataDirUtf8)
  local Success, ErrorString = InitializeDlls()
  if Success then
    SetUserDataDirectory(UserDataDirUtf8)
  end
  if Success then
    Success, ErrorString = RegisterWindowClass()
  end
  if Success then
    local VersionUtf8
    VersionUtf8, ErrorString = DetectWebView2Runtime()
    Success = (VersionUtf8 ~= nil)
  end
  if Success then
    Success, ErrorString = AllocateGlobalObjects()
  end
  -- Return value
  return Success, ErrorString
end

--------------------------------------------------------------------------------
-- WIN32 INIT                                                                 --
--------------------------------------------------------------------------------

local function CreateWindow (WebView, UserTitle)
  -- Handle defaults
  local Title = (UserTitle or "WebView2")
  -- Convert to UTF-16
  local TitleUtf16 = utf8to16(Title)
  local TitlePtr   = stringpointer(TitleUtf16)
  -- Compute style
  local Style = (WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS)
  -- Create the window (we provide UTF-16 ClassNamePointer directly to avoid
  -- issues)
  local HWND = CreateWindowExW(
    0,                -- dwExStyle
    ClassNamePointer, -- lpClassName
    TitlePtr,         -- lpWindowName
    Style,            -- dwStyle
    CW_USEDEFAULT,    -- X
    CW_USEDEFAULT,    -- Y
    900,              -- nWidth
    640,              -- nHeight
    nil,              -- hWndParent
    nil,              -- hMenu
    HInstance,        -- hInstance
    nil)              -- lpParam
  -- Show window
  if (HWND ~= NULL) then
    -- Register the webview, this is needed before the first WM_PAINT
    WebView.Window = HWND
    WebViewByHwnd[HWND] = WebView
    -- Show window
    ShowWindow(HWND, SW_SHOWDEFAULT)
    UpdateWindow(HWND)
    SetTimer(HWND, WM_POLL_TIMER_ID, 20, NULL)
  end
  -- Return value
  return HWND
end

local function CreateWebView (WebView)
  -- local closure for WebView handler
  local function OnEnvironmentCompleted (ErrorCode, EnvironmentPointer)
    return CoreEnvCompleted(WebView, ErrorCode, EnvironmentPointer)
  end
  -- Create the COM handler
  local NewHandler        = easycom.newhandler(OnEnvironmentCompleted, { sint32, pointer })
  local NewHandlerPointer = NewHandler:getpointer()
  -- Create the WebView
  local Hresult = CreateCoreWebView2EnvironmentWithOptions(NULL, WebViewUserDataDirPointer, NULL, NewHandlerPointer)
  if (Hresult == S_OK) then
    -- Save the handler reference
    WebView.EnvironmentHandler = NewHandler
  else
    print(format("[WebView2] CreateCoreWebView2EnvironmentWithOptions failed: 0x%08X", Hresult))
  end
end

local function Cleanup ()
  if (ClassNamePointer ~= NULL) then
    UnregisterClassW(ClassNamePointer, HInstance)
    ClassNamePointer = NULL
  end
end

--------------------------------------------------------------------------------
-- WEBVIEW API                                                                --
--------------------------------------------------------------------------------

local function WEBVIEW_MethodShow (WebView, Title)
  local HWND = CreateWindow(WebView, Title)
  if (HWND ~= NULL) then
    WindowCount = (WindowCount + 1)
    CreateWebView(WebView)
  end
end

local function WEBVIEW_MethodSend (WebView, Message)
  -- Retrieve data
  local Window     = WebView.Window
  local EventQueue = WebView.EventQueue
  -- Enqueue event
  append(EventQueue, Message)
  -- Request queue flush
  if (Window ~= NULL) then
    PostMessageW(Window, WM_APP_FLUSH_EVENTS, 0, 0)
  end
end

local function WEBVIEW_MethodClose (WebView)
  -- Retrieve data
  local Window = WebView.Window
  -- Post CLOSE message
  if (Window ~= NULL) then
    PostMessageW(Window, WM_CLOSE, 0, 0)
  end
end

local function WEBVIEW_GetUserdata (WebView)
  return WebView.UserData
end

local function WEBVIEW_GetHwnd (WebView)
  return WebView.Window
end

-- Screenshot parameters (full page, PNG)
local ScreenshotParamsJson = JsonEncode({ format = "png", captureBeyondViewport = true })

local function ProcessNextJob (WebView)
  -- Retrieve data
  local Job        = WebView.JobQueue[1]
  local CanProcess = (Job and (not WebView.Busy))
  if CanProcess then
    -- Start the job
    local ComWebView = WebView.ComWebView
    assert((ComWebView ~= NULL), "WebView is not initialized")
    local HandlerPointer = WebView.Handler:getpointer()
    local Hresult
    -- Mark as busy
    WebView.Busy = true
    if (Job.Type == "javascript") then
      local JavaScriptUtf16   = utf8to16(Job.Javascript)
      local JavaScriptPointer = stringpointer(JavaScriptUtf16)
      Hresult = ComWebView:ExecuteScript(JavaScriptPointer, HandlerPointer)
    elseif (Job.Type == "devtools") then
      local MethodUtf16   = utf8to16(Job.Method)
      local ParamsUtf16   = utf8to16(Job.Params)
      local MethodPointer = stringpointer(MethodUtf16)
      local ParamsPointer = stringpointer(ParamsUtf16)
      Hresult = ComWebView:CallDevToolsProtocolMethod(MethodPointer, ParamsPointer, HandlerPointer)
    elseif (Job.Type == "screenshot") then
      local ParametersUtf16   = utf8to16(ScreenshotParamsJson)
      local MethodNameUtf16   = utf8to16("Page.captureScreenshot")
      local ParametersPointer = stringpointer(ParametersUtf16)
      local MethodNamePointer = stringpointer(MethodNameUtf16)
      Hresult = ComWebView:CallDevToolsProtocolMethod(MethodNamePointer, ParametersPointer, HandlerPointer)
    end
    -- Handle failure
    if (Hresult ~= S_OK) then
      local ErrorString = format("[WebView2] %s failed: 0x%08X", Job.Type, Hresult)
      WebView.Busy = false
      remove(WebView.JobQueue, 1)
      Job.Callback(WebView, nil, ErrorString)
      ProcessNextJob(WebView)
    end
  end
end

-- Optional feature
local function WEBVIEW_MethodExecute (WebView, JavaScript, Callback)
  -- Retrieve data
  local ComWebView = WebView.ComWebView
  assert((ComWebView ~= NULL), "WebView is not initialized")
  assert((type(Callback) == "function"), "callback is required")
  -- Enqueue the job
  local NewJob = {
    Type       = "javascript",
    Javascript = JavaScript,
    Callback   = Callback
  }
  append(WebView.JobQueue, NewJob)
  -- Start ASAP
  ProcessNextJob(WebView)
end

-- Optional feature
local function WEBVIEW_MethodDevtools (WebView, Method, OptionalParams, Callback)
  -- Handle defaults
  local Params = (OptionalParams or {})
  -- Retrieve data
  local ComWebView = WebView.ComWebView
  assert((ComWebView ~= NULL), "WebView is not initialized")
  assert((type(Method) == "string"), "method is required")
  assert((type(Callback) == "function"), "callback is required")
  -- Enqueue the job
  local NewJob = {
    Type     = "devtools",
    Method   = Method,
    Params   = JsonEncode(Params),
    Callback = Callback
  }
  append(WebView.JobQueue, NewJob)
  -- Start ASAP
  ProcessNextJob(WebView)
end

-- Optional feature
-- NOTE: screenshot is a specialized devtools call
local function WEBVIEW_MethodScreenshot (WebView, Callback)
  -- Retrieve data
  local ComWebView = WebView.ComWebView
  assert((ComWebView ~= NULL), "WebView is not initialized")
  assert((type(Callback) == "function"), "callback is required")
  -- Enqueue the job
  local NewJob = {
    Type     = "screenshot",
    Callback = Callback
  }
  append(WebView.JobQueue, NewJob)
  -- Start ASAP
  ProcessNextJob(WebView)
end

local function OnJobCompleted (WebView, ErrorCode, ResultPointer)
  -- Retrieve the current job
  local Job = WebView.JobQueue[1]
  assert(Job)
  assert(Job.Type)
  -- Parse the result
  local ReturnValue
  local Position
  local ErrorString
  if (ErrorCode == S_OK) then
    -- Convert result string
    -- ResultPointer is owned by WebView2, do NOT need to call CoTaskMemFree
    local ReturnJson = pointertostring(ResultPointer, "utf16", "utf8")
    if ReturnJson then
      -- Handle JSON result
      if (Job.Type == "javascript") then
        ReturnValue, Position, ErrorString = JsonDecode(ReturnJson)
      elseif (Job.Type == "devtools") then
        ReturnValue, Position, ErrorString = JsonDecode(ReturnJson)
      elseif (Job.Type == "screenshot") then
        local DecodedValue
        DecodedValue, Position, ErrorString = JsonDecode(ReturnJson)
        local Data = (DecodedValue and DecodedValue.data)
        if ErrorString then
          ErrorString = format("Screenshot failed: %s", ErrorString)
        elseif (type(Data) == "string") then
          ReturnValue = Base64.decode(Data)
        else
          ErrorString = "Screenshot failed: no image data in the response"
        end
      end
    else
      ErrorString = "Failed to read the response"
    end
  else
    ErrorString = format("[WebView2] %s failed: 0x%08X", Job.Type, ErrorCode)
  end
  -- Give the result to the user
  Job.Callback(WebView, ReturnValue, ErrorString)
  -- Prepare next job
  remove(WebView.JobQueue, 1)
  WebView.Busy = false
  ProcessNextJob(WebView)
end

local WEBVIEW_Metatable = {
  -- METATABLE_UserDefinedMethods
  __index = {
    show        = WEBVIEW_MethodShow,
    send        = WEBVIEW_MethodSend,
    close       = WEBVIEW_MethodClose,
    getuserdata = WEBVIEW_GetUserdata,
    hwnd        = WEBVIEW_GetHwnd,
    execute     = WEBVIEW_MethodExecute,
    screenshot  = WEBVIEW_MethodScreenshot,
    devtools    = WEBVIEW_MethodDevtools,
  }
}

local function NewWebView (Content, OnMessage, UserData)
  -- Validate inputs
  assert((type(OnMessage) == "function"), "onmessage handler is required")
  -- Create new object
  local NewObject = {
    UserData           = UserData,
    OnMessage          = OnMessage,
    EventQueue         = {},
    Content            = Content,
    Window             = NULL,
    Controller         = NULL,
    ComWebView         = NULL,
    Environment        = NULL,
    EnvironmentHandler = NULL,
    ControllerHandler  = NULL,
    MessageHandler     = NULL,
    JobQueue           = {},
    Busy               = false,
  }
  -- Add a shared completion handler for execute JS and screenshot. Those 2
  -- features executeJS and screenshot are not essential and could be dropped.
  local function OnCompleted (ErrorCode, ResultPointer)
    OnJobCompleted(NewObject, ErrorCode, ResultPointer)
  end
  NewObject.Handler = easycom.newhandler(OnCompleted, { sint32, pointer })
  -- Attach metatable
  setmetatable(NewObject, WEBVIEW_Metatable)
  -- Return value
  return NewObject
end

--------------------------------------------------------------------------------
-- WIN32 MESSAGE LOOP                                                         --
--------------------------------------------------------------------------------

local function RunLoop ()
  -- Standard loop with GetMessageW (blocking in the kernel)
  local Continue    = true
  local ReturnValue = EXIT_SUCCESS
  local Msg         = newinstance(MSG)
  local MsgPointer  = Msg:getpointer()
  while Continue do
    local GetResult = GetMessageW(MsgPointer, NULL, 0, 0)
    if (GetResult == 0) then
      ReturnValue = Msg:get("wParam")
      Continue    = false
    elseif (GetResult == -1) then
      ReturnValue = 1 -- (not EXIT_SUCCESS)
      Continue    = false
    else
      TranslateMessage(MsgPointer)
      DispatchMessageW(MsgPointer)
    end
  end
  -- Return value
  return ReturnValue
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  init    = InitializeWebView,
  new     = NewWebView,
  runloop = RunLoop,
  cleanup = Cleanup,
}

return PUBLIC_API
