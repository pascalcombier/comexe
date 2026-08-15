/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME webview2.h                                                        *
 * CONTENT  Windows WebView2 declarations                                     *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

#ifndef WEBVIEW2_H
#define WEBVIEW2_H

/*============================================================================*/
/* TYPES                                                                      */
/*============================================================================*/

/* Aliases used in the function declarations */
#define STDMETHODCALLTYPE
#define HRESULT unsigned int
#define ULONG   unsigned int
#define BOOL    int
#define UINT64  unsigned long long
#define REFIID  const void *
#define LPCWSTR const wchar_t *
#define LPWSTR  wchar_t *

/* COM / HRESULT constants */
#define S_OK          0
#define E_FAIL        0x80004005
#define E_NOINTERFACE 0x80004002

/* WebView2 MoveFocus reasons */
#define COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC 0

/* NOTE: override win32-base.h RECT */
typedef struct {
  long left;
  long top;
  long right;
  long bottom;
} RECT;

typedef struct {
  unsigned char A;
  unsigned char R;
  unsigned char G;
  unsigned char B;
} COREWEBVIEW2_COLOR;

typedef struct {
  long x;
  long y;
} POINT;

/*============================================================================*/
/* PUBLIC API                                                                 */
/*============================================================================*/

HRESULT CreateCoreWebView2EnvironmentWithOptions(
  LPCWSTR browserExecutableFolder,
  LPCWSTR userDataFolder,
  void   *environmentOptions,
  void   *environmentCreatedHandler);

HRESULT GetAvailableCoreWebView2BrowserVersionString(
  LPCWSTR browserExecutableFolder,
  LPWSTR *versionInfo);

typedef struct COMEXE_WIN32COM_INTERFACE ICoreWebView2EnvironmentVtbl {
  HRESULT (STDMETHODCALLTYPE *QueryInterface)(void *This, REFIID riid, void **ppvObject);
  ULONG   (STDMETHODCALLTYPE *AddRef)(void *This);
  ULONG   (STDMETHODCALLTYPE *Release)(void *This);
  HRESULT (STDMETHODCALLTYPE *CreateCoreWebView2Controller)(void *This, void *parentWindow, void *handler);
  HRESULT (STDMETHODCALLTYPE *CreateWebResourceResponse)(void *This, void *content, int statusCode, LPCWSTR reasonPhrase, LPCWSTR headers, void **response);
  HRESULT (STDMETHODCALLTYPE *get_BrowserVersionString)(void *This, LPWSTR *versionInfo);
  HRESULT (STDMETHODCALLTYPE *add_NewBrowserVersionAvailable)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_NewBrowserVersionAvailable)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *CreateWebResourceRequest)(void *This, const wchar_t * uri, const wchar_t * Method, void * postData, const wchar_t * Headers, void ** value);
  HRESULT (STDMETHODCALLTYPE *CreateCoreWebView2CompositionController)(void *This, void * ParentWindow, void * handler);
  HRESULT (STDMETHODCALLTYPE *CreateCoreWebView2PointerInfo)(void *This, void ** value);
  HRESULT (STDMETHODCALLTYPE *GetAutomationProviderForWindow)(void *This, void * hwnd, void ** value);
  HRESULT (STDMETHODCALLTYPE *add_BrowserProcessExited)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_BrowserProcessExited)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *CreatePrintSettings)(void *This, void ** value);
  HRESULT (STDMETHODCALLTYPE *get_UserDataFolder)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *add_ProcessInfosChanged)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_ProcessInfosChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *GetProcessInfos)(void *This, void ** value);
  HRESULT (STDMETHODCALLTYPE *CreateContextMenuItem)(void *This, const wchar_t * Label, void * iconStream, int Kind, void ** value);
  HRESULT (STDMETHODCALLTYPE *CreateCoreWebView2ControllerOptions)(void *This, void ** value);
  HRESULT (STDMETHODCALLTYPE *CreateCoreWebView2ControllerWithOptions)(void *This, void * ParentWindow, void * options, void * handler);
  HRESULT (STDMETHODCALLTYPE *CreateCoreWebView2CompositionControllerWithOptions)(void *This, void * ParentWindow, void * options, void * handler);
  HRESULT (STDMETHODCALLTYPE *get_FailureReportFolderPath)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *CreateSharedBuffer)(void *This, unsigned long long Size, void ** value);
  HRESULT (STDMETHODCALLTYPE *GetProcessExtendedInfos)(void *This, void * handler);
  HRESULT (STDMETHODCALLTYPE *CreateWebFileSystemFileHandle)(void *This, const wchar_t * path, int permission, void ** value);
  HRESULT (STDMETHODCALLTYPE *CreateWebFileSystemDirectoryHandle)(void *This, const wchar_t * path, int permission, void ** value);
  HRESULT (STDMETHODCALLTYPE *CreateObjectCollection)(void *This, int length, void ** items, void ** objectCollection);
  HRESULT (STDMETHODCALLTYPE *CreateFindOptions)(void *This, void ** value);
} ICoreWebView2EnvironmentVtbl;

typedef struct COMEXE_WIN32COM_INTERFACE ICoreWebView2ControllerVtbl {
  HRESULT (STDMETHODCALLTYPE *QueryInterface)(void *This, REFIID riid, void **ppvObject);
  ULONG   (STDMETHODCALLTYPE *AddRef)(void *This);
  ULONG   (STDMETHODCALLTYPE *Release)(void *This);
  HRESULT (STDMETHODCALLTYPE *get_IsVisible)(void *This, BOOL *isVisible);
  HRESULT (STDMETHODCALLTYPE *put_IsVisible)(void *This, BOOL isVisible);
  HRESULT (STDMETHODCALLTYPE *get_Bounds)(void *This, RECT *bounds);
  HRESULT (STDMETHODCALLTYPE *put_Bounds)(void *This, RECT bounds);
  HRESULT (STDMETHODCALLTYPE *get_ZoomFactor)(void *This, double *zoomFactor);
  HRESULT (STDMETHODCALLTYPE *put_ZoomFactor)(void *This, double zoomFactor);
  HRESULT (STDMETHODCALLTYPE *add_ZoomFactorChanged)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_ZoomFactorChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *SetBoundsAndZoomFactor)(void *This, RECT bounds, double zoomFactor);
  HRESULT (STDMETHODCALLTYPE *MoveFocus)(void *This, int reason);
  HRESULT (STDMETHODCALLTYPE *add_MoveFocusRequested)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_MoveFocusRequested)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_GotFocus)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_GotFocus)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_LostFocus)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_LostFocus)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_AcceleratorKeyPressed)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_AcceleratorKeyPressed)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_ParentWindow)(void *This, void **parentWindow);
  HRESULT (STDMETHODCALLTYPE *put_ParentWindow)(void *This, void *parentWindow);
  HRESULT (STDMETHODCALLTYPE *NotifyParentWindowPositionChanged)(void *This);
  HRESULT (STDMETHODCALLTYPE *Close)(void *This);
  HRESULT (STDMETHODCALLTYPE *get_CoreWebView2)(void *This, void **coreWebView2);
  HRESULT (STDMETHODCALLTYPE *get_DefaultBackgroundColor)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *put_DefaultBackgroundColor)(void *This, COREWEBVIEW2_COLOR value);
  HRESULT (STDMETHODCALLTYPE *get_RasterizationScale)(void *This, void * scale);
  HRESULT (STDMETHODCALLTYPE *put_RasterizationScale)(void *This, double scale);
  HRESULT (STDMETHODCALLTYPE *get_ShouldDetectMonitorScaleChanges)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *put_ShouldDetectMonitorScaleChanges)(void *This, BOOL value);
  HRESULT (STDMETHODCALLTYPE *add_RasterizationScaleChanged)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_RasterizationScaleChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_BoundsMode)(void *This, void * boundsMode);
  HRESULT (STDMETHODCALLTYPE *put_BoundsMode)(void *This, int boundsMode);
  HRESULT (STDMETHODCALLTYPE *get_AllowExternalDrop)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *put_AllowExternalDrop)(void *This, BOOL value);
} ICoreWebView2ControllerVtbl;

typedef struct COMEXE_WIN32COM_INTERFACE ICoreWebView2Vtbl {
  HRESULT (STDMETHODCALLTYPE *QueryInterface)(void *This, REFIID riid, void **ppvObject);
  ULONG   (STDMETHODCALLTYPE *AddRef)(void *This);
  ULONG   (STDMETHODCALLTYPE *Release)(void *This);
  HRESULT (STDMETHODCALLTYPE *get_Settings)(void *This, void **settings);
  HRESULT (STDMETHODCALLTYPE *get_Source)(void *This, LPWSTR *uri);
  HRESULT (STDMETHODCALLTYPE *Navigate)(void *This, LPCWSTR uri);
  HRESULT (STDMETHODCALLTYPE *NavigateToString)(void *This, LPCWSTR htmlContent);
  HRESULT (STDMETHODCALLTYPE *add_NavigationStarting)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_NavigationStarting)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_ContentLoading)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_ContentLoading)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_SourceChanged)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_SourceChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_HistoryChanged)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_HistoryChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_NavigationCompleted)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_NavigationCompleted)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_FrameNavigationStarting)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_FrameNavigationStarting)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_FrameNavigationCompleted)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_FrameNavigationCompleted)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_ScriptDialogOpening)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_ScriptDialogOpening)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_PermissionRequested)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_PermissionRequested)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_ProcessFailed)(void *This, void *eventHandler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_ProcessFailed)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *AddScriptToExecuteOnDocumentCreated)(void *This, LPCWSTR javaScript, void *handler);
  HRESULT (STDMETHODCALLTYPE *RemoveScriptToExecuteOnDocumentCreated)(void *This, UINT64 id);
  HRESULT (STDMETHODCALLTYPE *ExecuteScript)(void *This, LPCWSTR javaScript, void *handler);
  HRESULT (STDMETHODCALLTYPE *CapturePreview)(void *This, int imageFormat, void *imageStream, void *handler);
  HRESULT (STDMETHODCALLTYPE *Reload)(void *This);
  HRESULT (STDMETHODCALLTYPE *PostWebMessageAsJson)(void *This, LPCWSTR webMessageAsJson);
  HRESULT (STDMETHODCALLTYPE *PostWebMessageAsString)(void *This, LPCWSTR webMessageAsString);
  HRESULT (STDMETHODCALLTYPE *add_WebMessageReceived)(void *This, void *handler, void *token);
  HRESULT (STDMETHODCALLTYPE *remove_WebMessageReceived)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *CallDevToolsProtocolMethod)(void *This, const wchar_t * methodName, const wchar_t * parametersAsJson, void * handler);
  HRESULT (STDMETHODCALLTYPE *get_BrowserProcessId)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *get_CanGoBack)(void *This, void * canGoBack);
  HRESULT (STDMETHODCALLTYPE *get_CanGoForward)(void *This, void * canGoForward);
  HRESULT (STDMETHODCALLTYPE *GoBack)(void *This);
  HRESULT (STDMETHODCALLTYPE *GoForward)(void *This);
  HRESULT (STDMETHODCALLTYPE *GetDevToolsProtocolEventReceiver)(void *This, const wchar_t * eventName, void ** receiver);
  HRESULT (STDMETHODCALLTYPE *Stop)(void *This);
  HRESULT (STDMETHODCALLTYPE *add_NewWindowRequested)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_NewWindowRequested)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_DocumentTitleChanged)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_DocumentTitleChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_DocumentTitle)(void *This, void * title);
  HRESULT (STDMETHODCALLTYPE *AddHostObjectToScript)(void *This, const wchar_t * name, void * object);
  HRESULT (STDMETHODCALLTYPE *RemoveHostObjectFromScript)(void *This, const wchar_t * name);
  HRESULT (STDMETHODCALLTYPE *OpenDevToolsWindow)(void *This);
  HRESULT (STDMETHODCALLTYPE *add_ContainsFullScreenElementChanged)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_ContainsFullScreenElementChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_ContainsFullScreenElement)(void *This, void * containsFullScreenElement);
  HRESULT (STDMETHODCALLTYPE *add_WebResourceRequested)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_WebResourceRequested)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *AddWebResourceRequestedFilter)(void *This, const wchar_t * uri, int resourceContext);
  HRESULT (STDMETHODCALLTYPE *RemoveWebResourceRequestedFilter)(void *This, const wchar_t * uri, int resourceContext);
  HRESULT (STDMETHODCALLTYPE *add_WindowCloseRequested)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_WindowCloseRequested)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_WebResourceResponseReceived)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_WebResourceResponseReceived)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *NavigateWithWebResourceRequest)(void *This, void * request);
  HRESULT (STDMETHODCALLTYPE *add_DOMContentLoaded)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_DOMContentLoaded)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_CookieManager)(void *This, void ** cookieManager);
  HRESULT (STDMETHODCALLTYPE *get_Environment)(void *This, void ** environment);
  HRESULT (STDMETHODCALLTYPE *TrySuspend)(void *This, void * handler);
  HRESULT (STDMETHODCALLTYPE *Resume)(void *This);
  HRESULT (STDMETHODCALLTYPE *get_IsSuspended)(void *This, void * isSuspended);
  HRESULT (STDMETHODCALLTYPE *SetVirtualHostNameToFolderMapping)(void *This, const wchar_t * hostName, const wchar_t * folderPath, int accessKind);
  HRESULT (STDMETHODCALLTYPE *ClearVirtualHostNameToFolderMapping)(void *This, const wchar_t * hostName);
  HRESULT (STDMETHODCALLTYPE *add_FrameCreated)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_FrameCreated)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_DownloadStarting)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_DownloadStarting)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_ClientCertificateRequested)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_ClientCertificateRequested)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *OpenTaskManagerWindow)(void *This);
  HRESULT (STDMETHODCALLTYPE *PrintToPdf)(void *This, const wchar_t * ResultFilePath, void * printSettings, void * handler);
  HRESULT (STDMETHODCALLTYPE *add_IsMutedChanged)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_IsMutedChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_IsMuted)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *put_IsMuted)(void *This, BOOL value);
  HRESULT (STDMETHODCALLTYPE *add_IsDocumentPlayingAudioChanged)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_IsDocumentPlayingAudioChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_IsDocumentPlayingAudio)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *add_IsDefaultDownloadDialogOpenChanged)(void *This, void * handler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_IsDefaultDownloadDialogOpenChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_IsDefaultDownloadDialogOpen)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *OpenDefaultDownloadDialog)(void *This);
  HRESULT (STDMETHODCALLTYPE *CloseDefaultDownloadDialog)(void *This);
  HRESULT (STDMETHODCALLTYPE *get_DefaultDownloadDialogCornerAlignment)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *put_DefaultDownloadDialogCornerAlignment)(void *This, int value);
  HRESULT (STDMETHODCALLTYPE *get_DefaultDownloadDialogMargin)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *put_DefaultDownloadDialogMargin)(void *This, POINT value);
  HRESULT (STDMETHODCALLTYPE *add_BasicAuthenticationRequested)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_BasicAuthenticationRequested)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *CallDevToolsProtocolMethodForSession)(void *This, const wchar_t * sessionId, const wchar_t * methodName, const wchar_t * parametersAsJson, void * handler);
  HRESULT (STDMETHODCALLTYPE *add_ContextMenuRequested)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_ContextMenuRequested)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_StatusBarTextChanged)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_StatusBarTextChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_StatusBarText)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *get_Profile)(void *This, void ** value);
  HRESULT (STDMETHODCALLTYPE *add_ServerCertificateErrorDetected)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_ServerCertificateErrorDetected)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *ClearServerCertificateErrorActions)(void *This, void * handler);
  HRESULT (STDMETHODCALLTYPE *add_FaviconChanged)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_FaviconChanged)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_FaviconUri)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *GetFavicon)(void *This, int format, void * completedHandler);
  HRESULT (STDMETHODCALLTYPE *Print)(void *This, void * printSettings, void * handler);
  HRESULT (STDMETHODCALLTYPE *ShowPrintUI)(void *This, int printDialogKind);
  HRESULT (STDMETHODCALLTYPE *PrintToPdfStream)(void *This, void * printSettings, void * handler);
  HRESULT (STDMETHODCALLTYPE *PostSharedBufferToScript)(void *This, void * sharedBuffer, int access, const wchar_t * additionalDataAsJson);
  HRESULT (STDMETHODCALLTYPE *add_LaunchingExternalUriScheme)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_LaunchingExternalUriScheme)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_MemoryUsageTargetLevel)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *put_MemoryUsageTargetLevel)(void *This, int value);
  HRESULT (STDMETHODCALLTYPE *get_FrameId)(void *This, void * value);
  HRESULT (STDMETHODCALLTYPE *ExecuteScriptWithResult)(void *This, const wchar_t * javaScript, void * handler);
  HRESULT (STDMETHODCALLTYPE *AddWebResourceRequestedFilterWithRequestSourceKinds)(void *This, const wchar_t * uri, int ResourceContext, int requestSourceKinds);
  HRESULT (STDMETHODCALLTYPE *RemoveWebResourceRequestedFilterWithRequestSourceKinds)(void *This, const wchar_t * uri, int ResourceContext, int requestSourceKinds);
  HRESULT (STDMETHODCALLTYPE *PostWebMessageAsJsonWithAdditionalObjects)(void *This, const wchar_t * webMessageAsJson, void * additionalObjects);
  HRESULT (STDMETHODCALLTYPE *add_NotificationReceived)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_NotificationReceived)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_SaveAsUIShowing)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_SaveAsUIShowing)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *ShowSaveAsUI)(void *This, void * handler);
  HRESULT (STDMETHODCALLTYPE *add_SaveFileSecurityCheckStarting)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_SaveFileSecurityCheckStarting)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *add_ScreenCaptureStarting)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_ScreenCaptureStarting)(void *This, UINT64 token);
  HRESULT (STDMETHODCALLTYPE *get_Find)(void *This, void ** value);
  HRESULT (STDMETHODCALLTYPE *add_DedicatedWorkerCreated)(void *This, void * eventHandler, void * token);
  HRESULT (STDMETHODCALLTYPE *remove_DedicatedWorkerCreated)(void *This, UINT64 token);
} ICoreWebView2Vtbl;

typedef struct COMEXE_WIN32COM_INTERFACE ICoreWebView2SettingsVtbl {
  HRESULT (STDMETHODCALLTYPE *QueryInterface)(void *This, REFIID riid, void **ppvObject);
  ULONG   (STDMETHODCALLTYPE *AddRef)(void *This);
  ULONG   (STDMETHODCALLTYPE *Release)(void *This);
  HRESULT (STDMETHODCALLTYPE *get_IsScriptEnabled)(void *This, BOOL *isScriptEnabled);
  HRESULT (STDMETHODCALLTYPE *put_IsScriptEnabled)(void *This, BOOL isScriptEnabled);
  HRESULT (STDMETHODCALLTYPE *get_IsWebMessageEnabled)(void *This, BOOL *isWebMessageEnabled);
  HRESULT (STDMETHODCALLTYPE *put_IsWebMessageEnabled)(void *This, BOOL isWebMessageEnabled);
  HRESULT (STDMETHODCALLTYPE *get_AreDefaultScriptDialogsEnabled)(void *This, BOOL *areDefaultScriptDialogsEnabled);
  HRESULT (STDMETHODCALLTYPE *put_AreDefaultScriptDialogsEnabled)(void *This, BOOL areDefaultScriptDialogsEnabled);
  HRESULT (STDMETHODCALLTYPE *get_IsStatusBarEnabled)(void *This, BOOL *isStatusBarEnabled);
  HRESULT (STDMETHODCALLTYPE *put_IsStatusBarEnabled)(void *This, BOOL isStatusBarEnabled);
  HRESULT (STDMETHODCALLTYPE *get_AreDevToolsEnabled)(void *This, BOOL *areDevToolsEnabled);
  HRESULT (STDMETHODCALLTYPE *put_AreDevToolsEnabled)(void *This, BOOL areDevToolsEnabled);
  HRESULT (STDMETHODCALLTYPE *get_AreDefaultContextMenusEnabled)(void *This, BOOL *enabled);
  HRESULT (STDMETHODCALLTYPE *put_AreDefaultContextMenusEnabled)(void *This, BOOL enabled);
  HRESULT (STDMETHODCALLTYPE *get_AreHostObjectsAllowed)(void *This, BOOL *allowed);
  HRESULT (STDMETHODCALLTYPE *put_AreHostObjectsAllowed)(void *This, BOOL allowed);
  HRESULT (STDMETHODCALLTYPE *get_IsZoomControlEnabled)(void *This, BOOL *enabled);
  HRESULT (STDMETHODCALLTYPE *put_IsZoomControlEnabled)(void *This, BOOL enabled);
  HRESULT (STDMETHODCALLTYPE *get_IsBuiltInErrorPageEnabled)(void *This, BOOL *enabled);
  HRESULT (STDMETHODCALLTYPE *put_IsBuiltInErrorPageEnabled)(void *This, BOOL enabled);
  HRESULT (STDMETHODCALLTYPE *get_UserAgent)(void *This, LPWSTR *value);
  HRESULT (STDMETHODCALLTYPE *put_UserAgent)(void *This, LPCWSTR value);
  HRESULT (STDMETHODCALLTYPE *get_AreBrowserAcceleratorKeysEnabled)(void *This, BOOL *value);
  HRESULT (STDMETHODCALLTYPE *put_AreBrowserAcceleratorKeysEnabled)(void *This, BOOL value);
  HRESULT (STDMETHODCALLTYPE *get_IsPasswordAutosaveEnabled)(void *This, BOOL *value);
  HRESULT (STDMETHODCALLTYPE *put_IsPasswordAutosaveEnabled)(void *This, BOOL value);
  HRESULT (STDMETHODCALLTYPE *get_IsGeneralAutofillEnabled)(void *This, BOOL *value);
  HRESULT (STDMETHODCALLTYPE *put_IsGeneralAutofillEnabled)(void *This, BOOL value);
} ICoreWebView2SettingsVtbl;

typedef struct COMEXE_WIN32COM_INTERFACE ICoreWebView2WebMessageReceivedEventArgsVtbl {
  HRESULT (STDMETHODCALLTYPE *QueryInterface)(void *This, REFIID riid, void **ppvObject);
  ULONG   (STDMETHODCALLTYPE *AddRef)(void *This);
  ULONG   (STDMETHODCALLTYPE *Release)(void *This);
  HRESULT (STDMETHODCALLTYPE *get_Source)(void *This, LPWSTR *value);
  HRESULT (STDMETHODCALLTYPE *get_WebMessageAsJson)(void *This, LPWSTR *value);
  HRESULT (STDMETHODCALLTYPE *TryGetWebMessageAsString)(void *This, LPWSTR *value);
} ICoreWebView2WebMessageReceivedEventArgsVtbl;

#endif /* WEBVIEW2_H */
