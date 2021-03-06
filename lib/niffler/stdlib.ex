defmodule Niffler.Stdlib do
  @moduledoc false
  def include() do
    """
    /* Simple libc header for TCC
    *
    * Add any function you want from the libc there. This file is here
    * only for your convenience so that you do not need to put the whole
    * glibc include files on your floppy disk
    */
    #ifndef _TCCLIB_H
    #define _TCCLIB_H

    /* stdarg.h */
    typedef __builtin_va_list va_list;

    /* stddef.h */
    typedef __SIZE_TYPE__ size_t;
    typedef __PTRDIFF_TYPE__ ssize_t;
    typedef __WCHAR_TYPE__ wchar_t;
    typedef __PTRDIFF_TYPE__ ptrdiff_t;
    typedef __PTRDIFF_TYPE__ intptr_t;
    typedef __SIZE_TYPE__ uintptr_t;
    void *alloca(size_t size);

    /* stdlib.h */
    void *calloc(size_t nmemb, size_t size);
    void *malloc(size_t size);
    void free(void *ptr);
    void *realloc(void *ptr, size_t size);
    int atoi(const char *nptr);
    long int strtol(const char *nptr, char **endptr, int base);
    unsigned long int strtoul(const char *nptr, char **endptr, int base);
    void exit(int);

    /* stdio.h */
    typedef struct __FILE FILE;
    #define EOF (-1)
    extern FILE *stdin;
    extern FILE *stdout;
    extern FILE *stderr;
    FILE *fopen(const char *path, const char *mode);
    FILE *fdopen(int fildes, const char *mode);
    FILE *freopen(const  char *path, const char *mode, FILE *stream);
    int fclose(FILE *stream);
    size_t  fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
    size_t  fwrite(void *ptr, size_t size, size_t nmemb, FILE *stream);
    int fgetc(FILE *stream);
    int fputs(const char *s, FILE *stream);
    char *fgets(char *s, int size, FILE *stream);
    int getc(FILE *stream);
    int getchar(void);
    char *gets(char *s);
    int ungetc(int c, FILE *stream);
    int fflush(FILE *stream);
    int putchar(int c);

    int printf(const char *format, ...);
    int fprintf(FILE *stream, const char *format, ...);
    int sprintf(char *str, const char *format, ...);
    int snprintf(char *str, size_t size, const  char  *format, ...);
    int asprintf(char **strp, const char *format, ...);
    int vprintf(const char *format, va_list ap);
    int vfprintf(FILE  *stream,  const  char *format, va_list ap);
    int vsprintf(char *str, const char *format, va_list ap);
    int vsnprintf(char *str, size_t size, const char  *format, va_list ap);
    int vasprintf(char  **strp,  const  char *format, va_list ap);

    void perror(const char *s);

    /* string.h */
    char *strcat(char *dest, const char *src);
    char *strchr(const char *s, int c);
    char *strrchr(const char *s, int c);
    char *strcpy(char *dest, const char *src);
    void *memcpy(void *dest, const void *src, size_t n);
    void *memmove(void *dest, const void *src, size_t n);
    void *memset(void *s, int c, size_t n);
    char *strdup(const char *s);
    size_t strlen(const char *s);

    /* dlfcn.h */
    #define RTLD_LAZY       0x001
    #define RTLD_NOW        0x002
    #define RTLD_GLOBAL     0x100

    void *dlopen(const char *filename, int flag);
    const char *dlerror(void);
    void *dlsym(void *handle, char *symbol);
    int dlclose(void *handle);

    /* Niffler extensions */

    void *niffler_alloc(Env *, size_t);
    #define $alloc(size) niffler_alloc(niffler_env, (size))


    #endif /* _TCCLIB_H */
    """
  end

  def symbols() do
    Regex.scan(~r" ([a-z]+)\(", include())
    |> Enum.map(fn [_all, match] -> match end)
  end
end
