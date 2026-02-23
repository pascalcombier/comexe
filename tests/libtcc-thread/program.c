#include <stdio.h>
#include <stdbool.h>

extern int  SleepMs       (int Milliseconds);
extern int  NeedExit      ();
extern void ProcessEvents ();

int main()
{
  const int SleepTimeMs = 1000;

  bool Continue = true;
  int  ExitRequest;

  while (Continue)
  {
    SleepMs(SleepTimeMs);
    ProcessEvents();
    ExitRequest = NeedExit();

    printf("ExitRequest %d\n", ExitRequest);
    Continue = (ExitRequest == 0);
  }

  return 0; /* This value is check in Lua */
}
