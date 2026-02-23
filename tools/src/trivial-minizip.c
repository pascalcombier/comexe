/*
   minizip.c
   Version 1.1, February 14h, 2010
   sample part of the MiniZip project - ( http://www.winimage.com/zLibDll/minizip.html )

         Copyright (C) 1998-2010 Gilles Vollant (minizip) ( http://www.winimage.com/zLibDll/minizip.html )

         Modifications of Unzip for Zip64
         Copyright (C) 2007-2008 Even Rouault

         Modifications for Zip64 support on both zip and unzip
         Copyright (C) 2009-2010 Mathias Svensson ( http://result42.com )
         
         Modifications for ComEXE
         Copyright (C) 2025-2026 Pascal COMBIER  
*/

/*
   trivial-minizip.c
   Simple zip file creator using minizip

   Basic usage: trivial-minizip zipfile.zip zip-contents.txt
   zipfile.zip: the output zip file
   zip-contents.txt: file containing the list of files to zip

   The zip-contents.txt file contains pairs of:
   file-to-zip ZipEntryName
   Whitespaces are used to separate the file name from the zip entry name.

   If the zip file already exists, it will be overwritten.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#else
#include <dirent.h>
#include <sys/stat.h>
#endif

#include "zip.h"

#ifdef _WIN32
        #define USEWIN32IOAPI
        #include "iowin32.h"
#endif

#define WRITEBUFFERSIZE (16384)
#define ARRAY_SIZE(Array) ((int)(sizeof(Array) / sizeof((Array)[0])))

static int verbose_mode = 0;
static int normalize_paths = 0;

static void show_usage(void) {
    printf("Trivial MiniZip - Simple zip file creator\n");
    printf("Usage: trivial-minizip -o OUT.zip DIR1 [DIR2] [DIR3] [-N] [0-9] [-v]\n\n");
    printf("  -o OUT.zip: output zip file (create new)\n");
    printf("  DIR1 [DIR2] [DIR3]: one or more directories to zip recursively\n");
    printf("  [0-9]: optional compression level (0=store, 1=fastest, 9=best, default=6)\n");
    printf("  -v: verbose mode (show progress messages)\n");
    printf("  -N: normalize paths (convert \\ to / in zip entries)\n\n");
    printf("Files are added with paths relative to each specified directory.\n");
    printf("Example: trivial-minizip -o test.zip runtime src-lua55ce 9 -N\n");
}

/* Normalize path by converting backslashes to forward slashes */
static void normalize_path(char* path) {
    if (!normalize_paths) return;
    
    char* p = path;
    while (*p) {
        if (*p == '\\') {
            *p = '/';
        }
        p++;
    }
}

/* Add a file to the zip archive */
static int add_file_to_zip(zipFile zf, const char* source_file, const char* zip_entry_name, int compression_level) {
    FILE* fin = NULL;
    void* buf = NULL;
    size_t size_read;
    int err = ZIP_OK;
    zip_fileinfo zi;
    size_t size_buf = WRITEBUFFERSIZE;

    /* Initialize zip_fileinfo with minimal data */
    memset(&zi, 0, sizeof(zi));
    
    /* Open source file */
    fin = fopen(source_file, "rb");
    if (fin == NULL) {
        printf("Error: Cannot open source file '%s'\n", source_file);
        return ZIP_ERRNO;
    }

    /* Allocate buffer */
    buf = malloc(size_buf);
    if (buf == NULL) {
        printf("Error: Cannot allocate memory\n");
        fclose(fin);
        return ZIP_INTERNALERROR;
    }

    /* Open new file in zip */
    err = zipOpenNewFileInZip(zf, zip_entry_name, &zi,
                             NULL, 0, NULL, 0, NULL,
                             Z_DEFLATED, compression_level);

    if (err != ZIP_OK) {
        printf("Error: Cannot create entry '%s' in zip file\n", zip_entry_name);
        free(buf);
        fclose(fin);
        return err;
    }

    /* Copy file content to zip */
    do {
        size_read = fread(buf, 1, size_buf, fin);
        if (size_read < size_buf && !feof(fin)) {
            printf("Error: Cannot read from file '%s'\n", source_file);
            err = ZIP_ERRNO;
            break;
        }

        if (size_read > 0) {
            err = zipWriteInFileInZip(zf, buf, (unsigned int)size_read);
            if (err < 0) {
                printf("Error: Cannot write to zip file\n");
                break;
            }
        }
    } while (err == ZIP_OK && size_read > 0);

    /* Close file in zip */
    if (err == ZIP_OK) {
        err = zipCloseFileInZip(zf);
        if (err != ZIP_OK) {
            printf("Error: Cannot close entry '%s' in zip file\n", zip_entry_name);
        } else {
            if (verbose_mode) {
                printf("Added: %s -> %s\n", source_file, zip_entry_name);
            }
        }
    }

    free(buf);
    fclose(fin);
    return err;
}

#ifdef _WIN32
/* Add files from directory recursively to zip (Windows implementation) */
static int add_directory_to_zip_recursive(zipFile zf, const char* directory, const char* base_directory, int compression_level, int* files_added) {
    WIN32_FIND_DATA findFileData;
    HANDLE hFind;
    char searchPath[MAX_PATH];
    char fullPath[MAX_PATH];
    char relativePath[MAX_PATH];
    int err = ZIP_OK;
    
    snprintf(searchPath, sizeof(searchPath), "%s\\*", directory);
    
    hFind = FindFirstFile(searchPath, &findFileData);
    if (hFind == INVALID_HANDLE_VALUE) {
        return ZIP_OK; /* Empty directory is not an error */
    }
    
    do {
        if (strcmp(findFileData.cFileName, ".") == 0 || strcmp(findFileData.cFileName, "..") == 0) {
            continue;
        }
        
        snprintf(fullPath, sizeof(fullPath), "%s\\%s", directory, findFileData.cFileName);
        
        if (findFileData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            /* Recursively process subdirectory */
            err = add_directory_to_zip_recursive(zf, fullPath, base_directory, compression_level, files_added);
            if (err != ZIP_OK) break;
        } else {
            /* Calculate relative path from base directory */
            const char* rel_start = fullPath;
            size_t base_len = strlen(base_directory);
            
            /* Skip base directory path and separator */
            if (strncmp(fullPath, base_directory, base_len) == 0) {
                rel_start = fullPath + base_len;
                /* Skip leading separator */
                if (*rel_start == '\\' || *rel_start == '/') {
                    rel_start++;
                }
            }
            
            /* Copy to relative path buffer and normalize if needed */
            strncpy(relativePath, rel_start, sizeof(relativePath) - 1);
            relativePath[sizeof(relativePath) - 1] = '\0';
            normalize_path(relativePath);
            
            /* Add file to zip */
            err = add_file_to_zip(zf, fullPath, relativePath, compression_level);
            if (err == ZIP_OK) {
                (*files_added)++;
            } else {
                printf("Warning: Failed to add file '%s' to zip\n", fullPath);
                err = ZIP_OK; /* Continue with other files */
            }
        }
    } while (FindNextFile(hFind, &findFileData) != 0);
    
    FindClose(hFind);
    return err;
}
#else
/* Add files from directory recursively to zip (Unix/Linux implementation) */
static int add_directory_to_zip_recursive(zipFile zf, const char* directory, const char* base_directory, int compression_level, int* files_added) {
    DIR *dir;
    struct dirent *entry;
    struct stat statbuf;
    char fullPath[1024];
    char relativePath[1024];
    int err = ZIP_OK;
    
    dir = opendir(directory);
    if (dir == NULL) {
        return ZIP_OK; /* Empty directory is not an error */
    }
    
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        
        snprintf(fullPath, sizeof(fullPath), "%s/%s", directory, entry->d_name);
        
        if (stat(fullPath, &statbuf) == 0) {
            if (S_ISDIR(statbuf.st_mode)) {
                /* Recursively process subdirectory */
                err = add_directory_to_zip_recursive(zf, fullPath, base_directory, compression_level, files_added);
                if (err != ZIP_OK) break;
            } else {
                /* Calculate relative path from base directory */
                const char* rel_start = fullPath;
                size_t base_len = strlen(base_directory);
                
                /* Skip base directory path and separator */
                if (strncmp(fullPath, base_directory, base_len) == 0) {
                    rel_start = fullPath + base_len;
                    /* Skip leading separator */
                    if (*rel_start == '\\' || *rel_start == '/') {
                        rel_start++;
                    }
                }
                
                /* Copy to relative path buffer and normalize if needed */
                strncpy(relativePath, rel_start, sizeof(relativePath) - 1);
                relativePath[sizeof(relativePath) - 1] = '\0';
                normalize_path(relativePath);
                
                /* Add file to zip */
                err = add_file_to_zip(zf, fullPath, relativePath, compression_level);
                if (err == ZIP_OK) {
                    (*files_added)++;
                } else {
                    printf("Warning: Failed to add file '%s' to zip\n", fullPath);
                    err = ZIP_OK; /* Continue with other files */
                }
            }
        }
    }
    
    closedir(dir);
    return err;
}
#endif

int main (int argc, char* argv[])
{
  if (argc < 2) {
    show_usage();
    return 1;
  }

  const char* zip_filename = NULL;
  const char* source_directories[64];
  int source_directory_count = 0;
  int compression_level = Z_DEFAULT_COMPRESSION; /* Default compression level (6) */
    
  /* Parse command line arguments */
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-v") == 0) {
      verbose_mode = 1;
    } else if (strcmp(argv[i], "-N") == 0) {
      normalize_paths = 1;
    } else if (strcmp(argv[i], "-o") == 0) {
      if (i + 1 >= argc) {
        printf("Error: -o requires output filename\n");
        show_usage();
        return 1;
      }
      zip_filename = argv[++i];
    } else if (argv[i][0] >= '0' && argv[i][0] <= '9' && argv[i][1] == '\0') {
      compression_level = argv[i][0] - '0';
    } else if (argv[i][0] == '-') {
      printf("Error: Unknown option '%s'\n", argv[i]);
      show_usage();
      return 1;
    } else {
      if (source_directory_count >= ARRAY_SIZE(source_directories)) {
        printf("Error: Too many directories (max %d)\n", ARRAY_SIZE(source_directories));
        return 1;
      }
      source_directories[source_directory_count++] = argv[i];
    }
  }
    
  /* Validate arguments */
  if (zip_filename == NULL || source_directory_count == 0) {
    printf("Error: -o and at least one directory are required\n");
    show_usage();
    return 1;
  }
    
  zipFile zf = NULL;
  int err = ZIP_OK;
  int files_added = 0;

  /* Create zip file */
  int zip_mode = APPEND_STATUS_CREATE;
#ifdef USEWIN32IOAPI
  zlib_filefunc64_def ffunc;
  fill_win32_filefunc64A(&ffunc);
  zf = zipOpen2_64(zip_filename, zip_mode, NULL, &ffunc);
#else
  zf = zipOpen64(zip_filename, zip_mode);
#endif

  if (zf == NULL) {
    printf("Error: Cannot create zip file '%s'\n", zip_filename);
    return 1;
  }

  if (verbose_mode) {
    printf("Creating zip file: %s\n", zip_filename);
    for (int i = 0; i < source_directory_count; i++) {
      printf("Adding files from directory: %s\n", source_directories[i]);
    }
  }

  for (int i = 0; i < source_directory_count; i++) {
    err = add_directory_to_zip_recursive(zf, source_directories[i], source_directories[i], compression_level, &files_added);
    if (err != ZIP_OK) {
      printf("Error: Failed to add directory contents to zip from '%s'\n", source_directories[i]);
      zipClose(zf, NULL);
      return 1;
    }
  }

  /* Close zip file */
  err = zipClose(zf, NULL);
  if (err != ZIP_OK) {
    printf("Error: Cannot close zip file '%s'\n", zip_filename);
    return 1;
  }

  if (verbose_mode) {
    printf("Zip file created successfully with %d files\n", files_added);
  }
  return 0;
}
