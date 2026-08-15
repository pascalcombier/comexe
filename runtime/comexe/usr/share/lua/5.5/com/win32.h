/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME win32.h                                                           *
 * CONTENT  Win32 API declarations for the raw Lua layer in com.win32         *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*/

#ifndef COMEXE_WIN32_H
#define COMEXE_WIN32_H

/*============================================================================*/
/* CONSTANTS                                                                  */
/*============================================================================*/

#define SEE_MASK_NOCLOSEPROCESS 0x00000040
#define INFINITE                0xFFFFFFFF

/* winerror.h */
#define ERROR_SUCCESS 0

/* winnls.h */
#define CP_UTF8              65001
#define WC_ERR_INVALID_CHARS 0x00000080
#define MB_ERR_INVALID_CHARS 0x00000008

/* winbase.h */
#define FORMAT_MESSAGE_FROM_SYSTEM    0x00001000
#define FORMAT_MESSAGE_IGNORE_INSERTS 0x00000200
#define FORMAT_MESSAGE_MAX_WIDTH_MASK 0x000000FF

/* winreg.h: Registry SAM access rights */
#define KEY_ALL_ACCESS         0x000F003F
#define KEY_CREATE_LINK        0x00000020
#define KEY_CREATE_SUB_KEY     0x00000004
#define KEY_ENUMERATE_SUB_KEYS 0x00000008
#define KEY_EXECUTE            0x00020019
#define KEY_NOTIFY             0x00000010
#define KEY_QUERY_VALUE        0x00000001
#define KEY_READ               0x00020019
#define KEY_SET_VALUE          0x00000002
#define KEY_WOW64_32KEY        0x00000200
#define KEY_WOW64_64KEY        0x00000100
#define KEY_WRITE              0x00020006

/* winreg.h: RegCreateKeyEx options */
#define REG_OPTION_NON_VOLATILE   0x00000000
#define REG_OPTION_VOLATILE       0x00000001
#define REG_OPTION_CREATE_LINK    0x00000002
#define REG_OPTION_BACKUP_RESTORE 0x00000004

/* winnt.h: Registry value types */
#define REG_NONE                       0
#define REG_SZ                         1
#define REG_EXPAND_SZ                  2
#define REG_BINARY                     3
#define REG_DWORD                      4
#define REG_DWORD_LITTLE_ENDIAN        4
#define REG_DWORD_BIG_ENDIAN           5
#define REG_LINK                       6
#define REG_MULTI_SZ                   7
#define REG_RESOURCE_LIST              8
#define REG_FULL_RESOURCE_DESCRIPTOR   9
#define REG_RESOURCE_REQUIREMENTS_LIST 10
#define REG_QWORD                      11
#define REG_QWORD_LITTLE_ENDIAN        11

/* winuser.h: ShowWindow commands */
#define SW_HIDE            0
#define SW_SHOWNORMAL      1
#define SW_NORMAL          1
#define SW_SHOWMINIMIZED   2
#define SW_SHOWMAXIMIZED   3
#define SW_MAXIMIZE        3
#define SW_SHOWNOACTIVATE  4
#define SW_SHOW            5
#define SW_MINIMIZE        6
#define SW_SHOWMINNOACTIVE 7
#define SW_SHOWNA          8
#define SW_RESTORE         9
#define SW_SHOWDEFAULT     10
#define SW_FORCEMINIMIZE   11

/* winuser.h: MessageBox type and icon */
#define MB_OK              0x00000000
#define MB_OKCANCEL        0x00000001
#define MB_YESNO           0x00000004
#define MB_YESNOCANCEL     0x00000003
#define MB_ICONINFORMATION 0x00000040
#define MB_ICONWARNING     0x00000030
#define MB_ICONERROR       0x00000010
#define MB_ICONQUESTION    0x00000020

/* winuser.h: MessageBox return values */
#define IDOK     1
#define IDCANCEL 2
#define IDYES    6
#define IDNO     7

/*============================================================================*/
/* STRUCTURES                                                                 */
/*============================================================================*/

typedef struct {
  unsigned int  cbSize;
  unsigned int  fMask;
  void         *hwnd;
  wchar_t      *lpVerb;
  wchar_t      *lpFile;
  wchar_t      *lpParameters;
  wchar_t      *lpDirectory;
  int           nShow;
  void         *hInstApp;
  void         *lpIDList;
  wchar_t      *lpClass;
  void         *hkeyClass;
  unsigned int  dwHotKey;
  void         *hIcon;
  void         *hProcess;
} SHELLEXECUTEINFOW;

/*============================================================================*/
/* kernel32.dll                                                               */
/*============================================================================*/

/*------------------*/
/* ERROR MANAGEMENT */
/*------------------*/

unsigned int GetLastError(void);

/* NOTE: the last parameter is va_list*, declared as void* */
unsigned int FormatMessageW(unsigned int flags, void *source, unsigned int messageId, unsigned int languageId, wchar_t *buffer, unsigned int size, void *args);

/*---------------------*/
/* UNICODE CONVERSIONS */
/*---------------------*/

int MultiByteToWideChar(unsigned int CodePage, unsigned int Flags, const char *StringUtf8, int StringUtf8Size, wchar_t *StringUtf16, int StringUtf16Length);
int WideCharToMultiByte(unsigned int CodePage, unsigned int Flags, const wchar_t *StringUtf16, int StringUtf16Length, char *Utf8Buffer, int Utf8BufferSize, const char *DefaultChar, int *UsedDefaultChar);

/*-------------------------*/
/* ENVIRONMENT AND PROCESS */
/*-------------------------*/

unsigned int ExpandEnvironmentStringsW(const wchar_t *Input, wchar_t *Output, unsigned int BufferSize);
unsigned int WaitForSingleObject(void *Handle, unsigned int Milliseconds);
int          GetExitCodeProcess(void *Process, unsigned int *ExitCode);
int          CloseHandle(void *Object);

/*============================================================================*/
/* advapi32.dll                                                               */
/*============================================================================*/

/*----------*/
/* REGISTRY */
/*----------*/

int RegCreateKeyExW(void *RootKey, const wchar_t *SubKey, unsigned int Reserved, wchar_t *Class, unsigned int Options, unsigned int Sam, void *SecurityAttrs, void *ResultKey, unsigned int *Disposition);
int RegOpenKeyExW(void *RootKey, const wchar_t *SubKey, unsigned int Options, unsigned int Sam, void *ResultKey);
int RegCloseKey(void *Key);
int RegQueryValueExW(void *Key, const wchar_t *ValueName, void *Reserved, unsigned int *Type, void *Data, unsigned int *DataSize);
int RegQueryInfoKeyW(void *Key, void *Class, void *ClassSize, void *Reserved, unsigned int *SubKeyCount, unsigned int *SubKeyMaxLength, void *MaxClassLength, void *ValueCount, void *MaxValueNameLength, void *MaxValueLength, void *SecurityDescriptor, void *LastWriteTime);
int RegEnumKeyExW(void *Key, unsigned int Index, wchar_t *Name, unsigned int *NameCount, void *Reserved, void *Class, void *ClassSize, void *LastWriteTime);
int RegDeleteKeyW(void *RootKey, const wchar_t *SubKey);
int RegSetValueExW(void *Key, const wchar_t *ValueName, unsigned int Reserved, unsigned int Type, void *Data, unsigned int DataSize);
int RegEnumValueW(void *Key, unsigned int Index, wchar_t *Name, unsigned int *NameCount, void *Reserved, unsigned int *Type, void *Data, unsigned int *DataSize);
int RegDeleteValueW(void *Key, const wchar_t *ValueName);
int RegFlushKey(void *Key);

/*============================================================================*/
/* shell32.dll                                                                */
/*============================================================================*/

/*-------*/
/* SHELL */
/*-------*/

int ShellExecuteExW(void *ShellExecuteInfo);

/*============================================================================*/
/* user32.dll                                                                 */
/*============================================================================*/

/*------------*/
/* MESSAGEBOX */
/*------------*/

int MessageBoxW(void *hWnd, const wchar_t *lpText, const wchar_t *lpCaption, unsigned int uType);

#endif /* COMEXE_WIN32_H */
