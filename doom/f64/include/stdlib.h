#ifndef F64_STDLIB_H
#define F64_STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 0x7fffffff

void  *malloc(size_t size);
void  *calloc(size_t n, size_t size);
void  *realloc(void *ptr, size_t size);
void   free(void *ptr);

int    atoi(const char *s);
long   atol(const char *s);
double atof(const char *s);
long   strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);
double strtod(const char *s, char **end);
int    abs(int x);
long   labs(long x);

void   exit(int code) __attribute__((noreturn));
void   abort(void) __attribute__((noreturn));
int    atexit(void (*fn)(void));
char  *getenv(const char *name);
int    system(const char *cmd);
void   qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *));
int    rand(void);
void   srand(unsigned seed);

#endif
