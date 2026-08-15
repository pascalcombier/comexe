/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME win32-base.h                                                      *
 * CONTENT  Win32 API header                                                  *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

#ifndef WIN32_BASE_H
#define WIN32_BASE_H

/*============================================================================*/
/* CLASS / WINDOW / CONSTANTS                                                 */
/*============================================================================*/

#define CS_HREDRAW 0x00000002
#define CS_VREDRAW 0x00000001

#define WS_OVERLAPPEDWINDOW 0x00CF0000
#define WS_CLIPCHILDREN     0x02000000
#define WS_CLIPSIBLINGS     0x04000000

#define CW_USEDEFAULT  0x80000000
#define SW_SHOWDEFAULT 10
#define EXIT_SUCCESS   0

#define IDI_APPLICATION 32512
#define IDC_ARROW       32512
#define COLOR_WINDOW    5

#define WM_DESTROY 0x0002
#define WM_CLOSE   0x0010
#define WM_SIZE    0x0005
#define WM_PAINT   0x000F
#define WM_TIMER   0x0113

/*============================================================================*/
/* DRAWTEXT                                                                   */
/*============================================================================*/

#define DT_CENTER     0x0001
#define DT_VCENTER    0x0004
#define DT_SINGLELINE 0x0020

/*============================================================================*/
/* STRUCTURES                                                                 */
/*============================================================================*/

typedef struct {
  long left;
  long top;
  long right;
  long bottom;
} RECT;

typedef struct {
  unsigned int  cbSize;
  unsigned int  style;
  void         *lpfnWndProc;
  int           cbClsExtra;
  int           cbWndExtra;
  void         *hInstance;
  void         *hIcon;
  void         *hCursor;
  void         *hbrBackground;
  char         *lpszMenuName;
  char         *lpszClassName;
  void         *hIconSm;
} WNDCLASSEX;

typedef struct {
  void               *hwnd;
  unsigned int        message;
  unsigned long long  wParam;
  long long           lParam;
  unsigned int        time;
  int                 pt_x;
  int                 pt_y;
  unsigned int        lPrivate;
} MSG;

typedef struct {
  void      *hdc;
  int        fErase;
  RECT       rcPaint;
  int        fRestore;
  int        fIncUpdate;
  long long  reserved01;
  long long  reserved02;
  long long  reserved03;
  long long  reserved04;
} PAINTSTRUCT;

/*============================================================================*/
/* user32.dll                                                                 */
/*============================================================================*/

/*----------------*/
/* WINDOW CLASSES */
/*----------------*/

unsigned short  RegisterClassExW(const void *lpWndClass);
int             UnregisterClassW(void *lpClassName, void *hInstance);

/*----------------------*/
/* WINDOWS AND MESSAGES */
/*----------------------*/

void      *CreateWindowExW(unsigned int dwExStyle, const wchar_t *lpClassName, const wchar_t *lpWindowName, unsigned int dwStyle, int X, int Y, int nWidth, int nHeight, void *hWndParent, void *hMenu, void *hInstance, void *lpParam);
int        DestroyWindow(void *hWnd);
int        ShowWindow(void *hWnd, int nCmdShow);
int        UpdateWindow(void *hWnd);
int        GetClientRect(void *hWnd, void *lpRect);
long long  DefWindowProcW(void *hWnd, unsigned int Msg, unsigned long long wParam, long long lParam);
int        GetMessageW(void *lpMsg, void *hWnd, unsigned int wMsgFilterMin, unsigned int wMsgFilterMax);
int        TranslateMessage(const void *lpMsg);
long long  DispatchMessageW(const void *lpmsg);
int        PostMessageW(void *hWnd, unsigned int Msg, unsigned long long wParam, long long lParam);
void       PostQuitMessage(int nExitCode);

/*--------*/
/* TIMERS */
/*--------*/

unsigned long long SetTimer(void *hWnd, unsigned long long nIDEvent, unsigned int uElapse, void *lpTimerFunc);
int                KillTimer(void *hWnd, unsigned long long uIDEvent);

/*------------------*/
/* CURSOR AND ICONS */
/*------------------*/

void *LoadCursorA(void *hInstance, const char *lpCursorName);
void *LoadIconA(void *hInstance, const char *lpIconName);

/*----------------------*/
/* PAINTING AND DRAWING */
/*----------------------*/

void *BeginPaint(void *hWnd, void *lpPaint);
int   EndPaint(void *hWnd, void *lpPaint);
int   DrawTextW(void *hdc, const wchar_t *lpchText, int cchText, void *lprc, unsigned int format);

/*---------------------*/
/* MODULE AND INSTANCE */
/*---------------------*/

void *GetModuleHandleA(const char *lpModuleName);

/*============================================================================*/
/* ole32.dll                                                                  */
/*============================================================================*/

/*-----*/
/* COM */
/*-----*/

void CoTaskMemFree(void *pv);

#endif /* WIN32_BASE_H */
