#ifndef MZ_CONFIG_H
#define MZ_CONFIG_H

#if defined(_WIN32)
/* Windows host (zig cc / MinGW provides dirent.h and DIR) */
#define HAVE_DIRENT_H     1
#define HAVE_SYS_DIRENT_H 0
#define HAVE_INTTYPES_H   1
#define HAVE_STDINT_H     1
#define HAVE_PDIR         1
#define HAVE_FSEEKO       0
#define HAVE_SYMLINK      0
#define HAVE_READLINK     0
#else
/* Linux host (glibc, musl) */
#define HAVE_DIRENT_H     1
#define HAVE_SYS_DIRENT_H 0
#define HAVE_INTTYPES_H   1
#define HAVE_STDINT_H     1
#define HAVE_PDIR         1
#define HAVE_FSEEKO       1
#define HAVE_SYMLINK      1
#define HAVE_READLINK     1
#endif

#endif
