/* Minimal stdio for DOOM on f64OS. Files live in RAM (see libc.c). */
#ifndef F64_STDIO_H
#define F64_STDIO_H

#include <stddef.h>
#include <stdarg.h>

typedef struct f64_file FILE;

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

#define EOF      (-1)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define BUFSIZ   512
#define FILENAME_MAX 256

FILE  *fopen(const char *path, const char *mode);
int    fclose(FILE *f);
size_t fread(void *ptr, size_t size, size_t n, FILE *f);
size_t fwrite(const void *ptr, size_t size, size_t n, FILE *f);
int    fseek(FILE *f, long offset, int whence);
long   ftell(FILE *f);
int    fflush(FILE *f);
int    feof(FILE *f);
int    ferror(FILE *f);
int    fgetc(FILE *f);
char  *fgets(char *s, int n, FILE *f);
int    fputc(int c, FILE *f);
int    fputs(const char *s, FILE *f);
int    putchar(int c);
int    puts(const char *s);
int    remove(const char *path);
int    rename(const char *oldpath, const char *newpath);
int    setvbuf(FILE *f, char *buf, int mode, size_t size);

#define getc(f)    fgetc(f)
#define putc(c, f) fputc((c), (f))
#define _IONBF 2

int printf(const char *fmt, ...);
int fprintf(FILE *f, const char *fmt, ...);
int sprintf(char *buf, const char *fmt, ...);
int snprintf(char *buf, size_t n, const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int vfprintf(FILE *f, const char *fmt, va_list ap);
int vsprintf(char *buf, const char *fmt, va_list ap);
int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap);
int sscanf(const char *str, const char *fmt, ...);
int fscanf(FILE *f, const char *fmt, ...);

#endif
