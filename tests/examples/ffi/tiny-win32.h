/* Window styles */
#define WS_OVERLAPPEDWINDOW 0x00CF0000
#define WS_EX_CLIENTEDGE    0x00000200
#define CW_USEDEFAULT       0x80000000
#define SW_SHOWDEFAULT      10
#define WS_CHILD            0x40000000
#define WS_VISIBLE          0x10000000
#define WS_CLIPCHILDREN     0x02000000

/* Class styles */
#define CS_HREDRAW 0x0002
#define CS_VREDRAW 0x0001
#define CS_OWNDC   0x0020

/* Standard IDs */
#define IDI_APPLICATION 32512
#define IDC_ARROW       32512

/* Stock objects */
#define COLOR_WINDOW 5
#define LTGRAY_BRUSH 1

/* UTF-8 code page */
#define CP_UTF8 65001

/* Window messages */
#define WM_DESTROY 0x0002
#define WM_PAINT   0x000F
#define WM_QUIT    0x0012
#define WM_TIMER   0x0113
#define WM_SIZE    0x0005
#define WM_COMMAND 0x0111

/* System parameters */
#define SPI_GETNONCLIENTMETRICS 41

/* DrawText format */
#define DT_SINGLELINE 0x00000020
#define DT_CENTER     0x00000001
#define DT_VCENTER    0x00000004
#define DT_CALCRECT   0x00000400

/* Font constants */
#define FW_NORMAL           400
#define DEFAULT_CHARSET     1
#define ANTIALIASED_QUALITY 4
#define DEFAULT_PITCH       0
#define FF_SWISS            32
#define TRANSPARENT         1

/* Structures */

typedef struct {
  int           lfHeight;
  int           lfWidth;
  int           lfEscapement;
  int           lfOrientation;
  int           lfWeight;
  unsigned char lfItalic;
  unsigned char lfUnderline;
  unsigned char lfStrikeOut;
  unsigned char lfCharSet;
  unsigned char lfOutPrecision;
  unsigned char lfClipPrecision;
  unsigned char lfQuality;
  unsigned char lfPitchAndFamily;
  char          lfFaceName[32];
  
} LOGFONTA;

typedef struct {
  unsigned int cbSize;
  int          iBorderWidth;
  int          iScrollWidth;
  int          iScrollHeight;
  int          iCaptionWidth;
  int          iCaptionHeight;
  LOGFONTA     lfCaptionFont;
  int          iSmCaptionWidth;
  int          iSmCaptionHeight;
  LOGFONTA     lfSmCaptionFont;
  int          iMenuWidth;
  int          iMenuHeight;
  LOGFONTA     lfMenuFont;
  LOGFONTA     lfStatusFont;
  LOGFONTA     lfMessageFont;
  
} NONCLIENTMETRICSA;

typedef struct {
  int x;
  int y;
  
} POINT;

typedef struct {
  int left;
  int top;
  int right;
  int bottom;
  
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
  const char   *lpszMenuName;
  const char   *lpszClassName;
  void         *hIconSm;
  
} WNDCLASSEX;

typedef struct {
  void               *hwnd;
  unsigned int        message;
  unsigned long long  wParam;
  long long           lParam;
  unsigned int        time;
  POINT               pt;
  unsigned int        lPrivate;
  
} MSG;

typedef struct {
  void               *hdc;
  int                 fErase;
  RECT                rcPaint;
  int                 fRestore;
  int                 fIncUpdate;
  unsigned long long  reservedA;
  unsigned long long  reservedB;
  unsigned long long  reservedC;
  unsigned long long  reservedD;
  
} PAINTSTRUCT;

/* kernel32.dll */
void *GetModuleHandleA(const char *lpModuleName);
int   MultiByteToWideChar(unsigned int CodePage, unsigned int dwFlags, const char *lpMultiByteStr, int cbMultiByte, void *lpWideCharStr, int cchWideChar);

/* user32.dll */
unsigned short RegisterClassExA(const void *lpWndClassEx);
void PostQuitMessage(int nExitCode);
void *BeginPaint(void *hWnd, void *lpPaint);
int GetClientRect(void *hWnd, void *lpRect);
int DrawTextW(void *hdc, const void *lpchText, int cchText, void *lprc, unsigned int format);
int EndPaint(void *hWnd, const void *lpPaint);
long long DefWindowProcA(void *hWnd, unsigned int Msg, unsigned long long wParam, long long lParam);
void *CreateWindowExA(unsigned int dwExStyle, const char* lpClassName, const char* lpWindowName, unsigned int dwStyle, int X, int Y, int nWidth, int nHeight, void *hWndParent, void *hMenu, void *hInstance, void *lpParam);
void *GetDC(void *hWnd);
void *LoadIconA(void *hInstance, void *lpIconName);
void *LoadCursorA(void *hInstance, void *lpCursorName);
int ShowWindow(void *hWnd, int nCmdShow);
int UpdateWindow(void *hWnd);
int GetMessageA(void *lpMsg, void *hWnd, unsigned int wMsgFilterMin, unsigned int wMsgFilterMax);
int TranslateMessage(const void *lpMsg);
long long DispatchMessageA(const void *lpMsg);
int InvalidateRect(void *hWnd, const void *lpRect, int bErase);
int MoveWindow(void *hWnd, int X, int Y, int nWidth, int nHeight, int bRepaint);
int FillRect(void *hdc, const void *lprc, void *hbr);
unsigned long long SetTimer(void *hWnd, unsigned long long nIDEvent, unsigned int uElapse, void *lpTimerFunc);
int KillTimer(void *hWnd, unsigned long long uIDEvent);
int ReleaseDC(void *hWnd, void *hdc);
int SystemParametersInfoA(unsigned int uiAction, unsigned int uiParam, void *pvParam, unsigned int fWinIni);

/* gdi32.dll */
void *GetStockObject(int i);
void *CreateFontA(int cHeight, int cWidth, int cEscapement, int cOrientation, int cWeight, unsigned int bItalic, unsigned int bUnderline, unsigned int bStrikeOut, unsigned int iCharSet, unsigned int iOutPrecision, unsigned int iClipPrecision, unsigned int iQuality, unsigned int iPitchAndFamily, const char* pszFaceName);
void *CreateFontIndirectA(const void *lplf);
void *SelectObject(void *hdc, void *h);
int DeleteObject(void *h);
int SetBkMode(void *hdc, int mode);
