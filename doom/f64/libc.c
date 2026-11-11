/*
 * libc.c - the small C library that DOOM needs on f64OS.
 *
 * Memory:  first-fit allocator over the heap range in the boot block.
 * Files:   the WAD is a read-only file in RAM. Files that DOOM writes
 *          are RAM files. Savegames (*.dsg) and config files (*.cfg)
 *          are also written to the f64OS disk when DOOM closes or
 *          renames them, and read from the disk when they are not in
 *          RAM (see disk_f64.c).
 * Console: stdout and stderr go to COM1 and, until DOOM sets the
 *          graphics mode, to the VGA text screen. The last stderr text
 *          is kept for the error message that doom.f shows.
 */
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <unistd.h>
#include <sys/stat.h>

#include "f64.h"

int errno;

/* ==== Memory ========================================================== */

/* Each block has a header. 'size' includes the header and is a multiple
 * of 16. The blocks fill the heap from start to end without gaps. */
struct block {
    size_t size;
    size_t used;
};

#define BLOCK_HDR   sizeof(struct block)
#define BLOCK_ALIGN 16
#define BLOCK_MIN   (BLOCK_HDR + BLOCK_ALIGN)

static uint8_t *heap_start;
static uint8_t *heap_end;

static struct block *next_block(struct block *b)
{
    return (struct block *)((uint8_t *)b + b->size);
}

static void heap_init(void)
{
    struct block *b;

    heap_start = (uint8_t *)(((uintptr_t)f64_boot->heap_start + 15) & ~(uintptr_t)15);
    heap_end = (uint8_t *)((uintptr_t)f64_boot->heap_end & ~(uintptr_t)15);
    b = (struct block *)heap_start;
    b->size = heap_end - heap_start;
    b->used = 0;
}

void *malloc(size_t size)
{
    struct block *b, *n;
    size_t need;

    if (size == 0)
        size = 1;
    need = (size + BLOCK_HDR + BLOCK_ALIGN - 1) & ~(size_t)(BLOCK_ALIGN - 1);

    for (b = (struct block *)heap_start; (uint8_t *)b < heap_end; b = next_block(b))
    {
        if (b->used)
            continue;

        /* Join the free blocks that follow this one. */
        for (n = next_block(b); (uint8_t *)n < heap_end && !n->used; n = next_block(b))
            b->size += n->size;

        if (b->size < need)
            continue;

        if (b->size - need >= BLOCK_MIN)
        {
            n = (struct block *)((uint8_t *)b + need);
            n->size = b->size - need;
            n->used = 0;
            b->size = need;
        }
        b->used = 1;
        return (uint8_t *)b + BLOCK_HDR;
    }

    errno = ENOMEM;
    return NULL;
}

void free(void *ptr)
{
    if (ptr)
        ((struct block *)((uint8_t *)ptr - BLOCK_HDR))->used = 0;
}

void *calloc(size_t n, size_t size)
{
    size_t total = n * size;
    void *p = malloc(total);

    if (p)
        memset(p, 0, total);
    return p;
}

void *realloc(void *ptr, size_t size)
{
    struct block *b;
    size_t have;
    void *p;

    if (!ptr)
        return malloc(size);
    if (size == 0)
    {
        free(ptr);
        return NULL;
    }
    b = (struct block *)((uint8_t *)ptr - BLOCK_HDR);
    have = b->size - BLOCK_HDR;
    if (have >= size)
        return ptr;
    p = malloc(size);
    if (p)
    {
        memcpy(p, ptr, have);
        free(ptr);
    }
    return p;
}

/* ==== Strings and memory ============================================== */

void *memcpy(void *dst, const void *src, size_t n)
{
    void *d = dst;
    __asm__ volatile("rep movsb" : "+D"(d), "+S"(src), "+c"(n) : : "memory");
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    uint8_t *d = dst;
    const uint8_t *s = src;

    if (d <= s || d >= s + n)
        return memcpy(dst, src, n);
    while (n--)
        d[n] = s[n];
    return dst;
}

void *memset(void *dst, int c, size_t n)
{
    void *d = dst;
    __asm__ volatile("rep stosb" : "+D"(d), "+c"(n) : "a"(c) : "memory");
    return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const uint8_t *x = a, *y = b;

    for (; n; n--, x++, y++)
        if (*x != *y)
            return *x - *y;
    return 0;
}

void *memchr(const void *s, int c, size_t n)
{
    const uint8_t *p = s;

    for (; n; n--, p++)
        if (*p == (uint8_t)c)
            return (void *)p;
    return NULL;
}

size_t strlen(const char *s)
{
    const char *p = s;

    while (*p)
        p++;
    return p - s;
}

size_t strnlen(const char *s, size_t n)
{
    size_t i = 0;

    while (i < n && s[i])
        i++;
    return i;
}

char *strcpy(char *dst, const char *src)
{
    char *d = dst;

    while ((*d++ = *src++))
        ;
    return dst;
}

char *strncpy(char *dst, const char *src, size_t n)
{
    size_t i = 0;

    for (; i < n && src[i]; i++)
        dst[i] = src[i];
    for (; i < n; i++)
        dst[i] = '\0';
    return dst;
}

char *strcat(char *dst, const char *src)
{
    strcpy(dst + strlen(dst), src);
    return dst;
}

char *strncat(char *dst, const char *src, size_t n)
{
    char *d = dst + strlen(dst);

    while (n-- && *src)
        *d++ = *src++;
    *d = '\0';
    return dst;
}

int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b)
        a++, b++;
    return (uint8_t)*a - (uint8_t)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    for (; n; n--, a++, b++)
    {
        if (*a != *b)
            return (uint8_t)*a - (uint8_t)*b;
        if (!*a)
            return 0;
    }
    return 0;
}

int strcasecmp(const char *a, const char *b)
{
    while (*a && tolower((uint8_t)*a) == tolower((uint8_t)*b))
        a++, b++;
    return tolower((uint8_t)*a) - tolower((uint8_t)*b);
}

int strncasecmp(const char *a, const char *b, size_t n)
{
    for (; n; n--, a++, b++)
    {
        int x = tolower((uint8_t)*a), y = tolower((uint8_t)*b);

        if (x != y)
            return x - y;
        if (!x)
            return 0;
    }
    return 0;
}

char *strchr(const char *s, int c)
{
    for (;; s++)
    {
        if (*s == (char)c)
            return (char *)s;
        if (!*s)
            return NULL;
    }
}

char *strrchr(const char *s, int c)
{
    const char *r = NULL;

    for (;; s++)
    {
        if (*s == (char)c)
            r = s;
        if (!*s)
            return (char *)r;
    }
}

char *strstr(const char *hay, const char *needle)
{
    size_t n = strlen(needle);

    for (; *hay; hay++)
        if (!strncmp(hay, needle, n))
            return (char *)hay;
    return n ? NULL : (char *)hay;
}

char *strdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *d = malloc(n);

    if (d)
        memcpy(d, s, n);
    return d;
}

char *strerror(int err)
{
    switch (err)
    {
    case ENOENT: return "No such file";
    case ENOMEM: return "Out of memory";
    case EINVAL: return "Invalid argument";
    default:     return "Error";
    }
}

/* ==== Numbers ========================================================= */

unsigned long strtoul(const char *s, char **end, int base)
{
    unsigned long v = 0;
    int neg = 0, d;

    while (isspace((uint8_t)*s))
        s++;
    if (*s == '+' || *s == '-')
        neg = (*s++ == '-');
    if ((base == 0 || base == 16) && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
    {
        s += 2;
        base = 16;
    }
    else if (base == 0)
        base = (*s == '0') ? 8 : 10;

    for (;; s++)
    {
        if (isdigit((uint8_t)*s))      d = *s - '0';
        else if (isalpha((uint8_t)*s)) d = tolower((uint8_t)*s) - 'a' + 10;
        else break;
        if (d >= base)
            break;
        v = v * base + d;
    }
    if (end)
        *end = (char *)s;
    return neg ? -v : v;
}

long strtol(const char *s, char **end, int base)
{
    return (long)strtoul(s, end, base);
}

int  atoi(const char *s) { return (int)strtol(s, NULL, 10); }
long atol(const char *s) { return strtol(s, NULL, 10); }

double strtod(const char *s, char **end)
{
    double v = 0, scale = 1;
    int neg = 0;

    while (isspace((uint8_t)*s))
        s++;
    if (*s == '+' || *s == '-')
        neg = (*s++ == '-');
    while (isdigit((uint8_t)*s))
        v = v * 10 + (*s++ - '0');
    if (*s == '.')
    {
        s++;
        while (isdigit((uint8_t)*s))
        {
            scale /= 10;
            v += (*s++ - '0') * scale;
        }
    }
    if (end)
        *end = (char *)s;
    return neg ? -v : v;
}

double atof(const char *s) { return strtod(s, NULL); }

int  abs(int x)   { return x < 0 ? -x : x; }
long labs(long x) { return x < 0 ? -x : x; }

static unsigned long rand_state = 1;
int  rand(void)          { rand_state = rand_state * 1103515245 + 12345; return (rand_state >> 16) & RAND_MAX; }
void srand(unsigned s)   { rand_state = s; }

void qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *))
{
    uint8_t *a = base, tmp;
    size_t i, j, k;

    /* Insertion sort. DOOM sorts only small arrays. */
    for (i = 1; i < n; i++)
        for (j = i; j > 0 && cmp(a + (j - 1) * size, a + j * size) > 0; j--)
            for (k = 0; k < size; k++)
            {
                tmp = a[(j - 1) * size + k];
                a[(j - 1) * size + k] = a[j * size + k];
                a[j * size + k] = tmp;
            }
}

double fabs(double x)  { return x < 0 ? -x : x; }
float  fabsf(float x)  { return x < 0 ? -x : x; }
double sqrt(double x)  { __asm__("sqrtsd %1, %0" : "=x"(x) : "x"(x)); return x; }
double floor(double x) { double t = (double)(long)x; return t > x ? t - 1 : t; }
double ceil(double x)  { double t = (double)(long)x; return t < x ? t + 1 : t; }

double pow(double x, double y)
{
    /* Integer powers only. DOOM does not need more. */
    double r = 1;
    long n = (long)y;
    int neg = n < 0;

    if (neg)
        n = -n;
    while (n--)
        r *= x;
    return neg ? 1 / r : r;
}

/* ==== Process ========================================================= */

char *getenv(const char *name)   { (void)name; return NULL; }
int   system(const char *cmd)    { (void)cmd; return -1; }
int   atexit(void (*fn)(void))   { (void)fn; return 0; }
int   usleep(unsigned usec)      { (void)usec; return 0; }

void f64_assert_fail(const char *expr, const char *file, int line)
{
    fprintf(stderr, "Assertion failed: %s (%s:%d)\n", expr, file, line);
    exit(-1);
}

/* ==== Console ========================================================= */

#define TEXT_MEM ((volatile uint16_t *)0xB8000)
#define TEXT_W   80
#define TEXT_H   25
#define TEXT_TOP 1          /* row 0 is the f64OS status bar */

static int con_x, con_y = TEXT_TOP;
static int con_graphics;

static char   err_text[512];
static size_t err_len;

static void serial_putc(char c)
{
    int i;

    /* Wait for the transmit buffer. Stop waiting if there is no UART. */
    for (i = 0; i < 100000 && !(inb(0x3FD) & 0x20); i++)
        ;
    outb(0x3F8, c);
}

static void text_scroll(void)
{
    int i;

    for (i = TEXT_TOP * TEXT_W; i < (TEXT_H - 1) * TEXT_W; i++)
        TEXT_MEM[i] = TEXT_MEM[i + TEXT_W];
    for (i = (TEXT_H - 1) * TEXT_W; i < TEXT_H * TEXT_W; i++)
        TEXT_MEM[i] = 0x0720;
    con_y = TEXT_H - 1;
}

static void text_putc(char c)
{
    if (c == '\n')
    {
        con_x = 0;
        if (++con_y >= TEXT_H)
            text_scroll();
        return;
    }
    if (c == '\r')
    {
        con_x = 0;
        return;
    }
    if (c == '\t')
        c = ' ';
    TEXT_MEM[con_y * TEXT_W + con_x] = 0x0700 | (uint8_t)c;
    if (++con_x >= TEXT_W)
    {
        con_x = 0;
        if (++con_y >= TEXT_H)
            text_scroll();
    }
}

void f64_console_clear(void)
{
    int i;

    for (i = TEXT_TOP * TEXT_W; i < TEXT_H * TEXT_W; i++)
        TEXT_MEM[i] = 0x0720;
    con_x = 0;
    con_y = TEXT_TOP;
}

void f64_console_graphics(int on)
{
    con_graphics = on;
}

void f64_console_write(const char *s, size_t n)
{
    size_t i;

    for (i = 0; i < n; i++)
    {
        if (s[i] == '\n')
            serial_putc('\r');
        serial_putc(s[i]);
        if (!con_graphics)
            text_putc(s[i]);
    }
}

static void error_capture(const char *s, size_t n)
{
    size_t i;

    for (i = 0; i < n; i++)
    {
        if (err_len >= sizeof(err_text) - 1)
        {
            /* Keep the newest text. */
            memmove(err_text, err_text + 256, err_len - 256);
            err_len -= 256;
        }
        err_text[err_len++] = s[i];
    }
    err_text[err_len] = '\0';
}

const char *f64_error_text(void)
{
    char *p = err_text;
    size_t n;

    /* Show the text without leading and trailing blank lines. */
    while (*p == '\n' || *p == ' ')
        p++;
    n = strlen(p);
    while (n && (p[n - 1] == '\n' || p[n - 1] == ' '))
        p[--n] = '\0';
    return *p ? p : "DOOM stopped with an error.";
}

/* ==== Files =========================================================== */

enum { F_CONSOLE, F_ERROR, F_MEM };

#define RAMFILE_MAX  32
#define RAMFILE_NAME 64

struct ramfile {
    char     name[RAMFILE_NAME];
    uint8_t *data;
    size_t   size;
    size_t   cap;
    int      used;
};

struct f64_file {
    int             kind;
    const uint8_t  *rdata;     /* read-only data (WAD), or NULL */
    struct ramfile *rf;        /* RAM file, or NULL */
    size_t          pos;
    int             writable;
    int             eof;
    int             dirty;     /* written since it was opened */
};

static struct ramfile ramfiles[RAMFILE_MAX];

static struct f64_file console_out = { F_CONSOLE };
static struct f64_file console_err = { F_ERROR };
static struct f64_file console_in  = { F_CONSOLE };

FILE *stdin  = &console_in;
FILE *stdout = &console_out;
FILE *stderr = &console_err;

static const char *base_name(const char *path)
{
    const char *b = path, *p;

    for (p = path; *p; p++)
        if (*p == '/' || *p == '\\')
            b = p + 1;
    return b;
}

static int is_wad_name(const char *path)
{
    const char *b = base_name(path);
    size_t n = f64_boot->wad_name_len;

    return strlen(b) == n && !strncasecmp(b, f64_boot->wad_name, n);
}

static struct ramfile *ramfile_find(const char *path)
{
    const char *b = base_name(path);
    int i;

    for (i = 0; i < RAMFILE_MAX; i++)
        if (ramfiles[i].used && !strcasecmp(ramfiles[i].name, b))
            return &ramfiles[i];
    return NULL;
}

static struct ramfile *ramfile_create(const char *path)
{
    const char *b = base_name(path);
    int i;

    for (i = 0; i < RAMFILE_MAX; i++)
        if (!ramfiles[i].used)
        {
            memset(&ramfiles[i], 0, sizeof(ramfiles[i]));
            strncpy(ramfiles[i].name, b, RAMFILE_NAME - 1);
            ramfiles[i].used = 1;
            return &ramfiles[i];
        }
    return NULL;
}

int  f64_disk_usable(const char *name);
int  f64_disk_load(const char *name, uint8_t **data, size_t *size);
int  f64_disk_save(const char *name, const uint8_t *data, size_t size);

static int ends_with(const char *s, const char *suffix)
{
    size_t n = strlen(s), m = strlen(suffix);

    return n >= m && !strcasecmp(s + n - m, suffix);
}

/* Files that stay on the disk: savegames and config files. temp.dsg is
 * only the first step of a save (DOOM renames it), so it stays in RAM. */
static int is_persistent(const char *name)
{
    return f64_disk_usable(name)
        && ((ends_with(name, ".dsg") && strcasecmp(name, "temp.dsg"))
            || ends_with(name, ".cfg"));
}

static void ramfile_persist(struct ramfile *rf)
{
    if (rf && is_persistent(rf->name))
        f64_disk_save(rf->name, rf->data ? rf->data : (const uint8_t *)"", rf->size);
}

/* Make a RAM file from a file on the disk. */
static struct ramfile *ramfile_from_disk(const char *path)
{
    const char *b = base_name(path);
    struct ramfile *rf;
    uint8_t *data;
    size_t size;

    if (!is_persistent(b) || !f64_disk_load(b, &data, &size))
        return NULL;
    rf = ramfile_create(path);
    if (!rf)
    {
        free(data);
        return NULL;
    }
    rf->data = data;
    rf->size = size;
    rf->cap = size;
    return rf;
}

static size_t file_size(FILE *f)
{
    return f->rf ? f->rf->size : f64_boot->wad_size;
}

FILE *fopen(const char *path, const char *mode)
{
    struct ramfile *rf = NULL;
    FILE *f;
    int write = strchr(mode, 'w') != NULL;
    int append = strchr(mode, 'a') != NULL;
    int plus = strchr(mode, '+') != NULL;

    if (!write && !append && is_wad_name(path))
    {
        f = calloc(1, sizeof(*f));
        if (!f)
            return NULL;
        f->kind = F_MEM;
        f->rdata = f64_boot->wad;
        return f;
    }

    rf = ramfile_find(path);
    if (!rf && !write)
        rf = ramfile_from_disk(path);
    if (!rf && (write || append))
        rf = ramfile_create(path);
    if (!rf)
    {
        errno = ENOENT;
        return NULL;
    }
    if (write)
        rf->size = 0;

    f = calloc(1, sizeof(*f));
    if (!f)
        return NULL;
    f->kind = F_MEM;
    f->rf = rf;
    f->writable = write || append || plus;
    f->pos = append ? rf->size : 0;
    return f;
}

int fclose(FILE *f)
{
    if (f && f->kind == F_MEM)
    {
        if (f->dirty)
            ramfile_persist(f->rf);
        free(f);
    }
    return 0;
}

size_t fread(void *ptr, size_t size, size_t n, FILE *f)
{
    size_t total = size * n, have;
    const uint8_t *src;

    if (f->kind != F_MEM || size == 0)
        return 0;
    have = file_size(f) > f->pos ? file_size(f) - f->pos : 0;
    if (total > have)
    {
        total = have - have % size;
        f->eof = 1;
    }
    src = f->rf ? f->rf->data : f->rdata;
    memcpy(ptr, src + f->pos, total);
    f->pos += total;
    return total / size;
}

size_t fwrite(const void *ptr, size_t size, size_t n, FILE *f)
{
    size_t total = size * n;
    struct ramfile *rf = f->rf;

    if (f->kind == F_CONSOLE || f->kind == F_ERROR)
    {
        f64_console_write(ptr, total);
        if (f->kind == F_ERROR)
            error_capture(ptr, total);
        return n;
    }
    if (!f->writable || !rf || size == 0)
        return 0;
    if (f->pos + total > rf->cap)
    {
        size_t cap = rf->cap ? rf->cap : 4096;
        uint8_t *d;

        while (cap < f->pos + total)
            cap *= 2;
        d = realloc(rf->data, cap);
        if (!d)
            return 0;
        rf->data = d;
        rf->cap = cap;
    }
    if (f->pos > rf->size)
        memset(rf->data + rf->size, 0, f->pos - rf->size);
    memcpy(rf->data + f->pos, ptr, total);
    f->pos += total;
    f->dirty = 1;
    if (f->pos > rf->size)
        rf->size = f->pos;
    return n;
}

int fseek(FILE *f, long offset, int whence)
{
    long base;

    if (f->kind != F_MEM)
        return -1;
    base = whence == SEEK_SET ? 0 : whence == SEEK_CUR ? (long)f->pos : (long)file_size(f);
    if (base + offset < 0)
        return -1;
    f->pos = base + offset;
    f->eof = 0;
    return 0;
}

long ftell(FILE *f)  { return f->kind == F_MEM ? (long)f->pos : -1; }
int  fflush(FILE *f) { (void)f; return 0; }
int  feof(FILE *f)   { return f->eof; }
int  ferror(FILE *f) { (void)f; return 0; }
int  setvbuf(FILE *f, char *buf, int mode, size_t size) { (void)f; (void)buf; (void)mode; (void)size; return 0; }

int fgetc(FILE *f)
{
    unsigned char c;

    return fread(&c, 1, 1, f) == 1 ? c : EOF;
}

char *fgets(char *s, int n, FILE *f)
{
    int i = 0, c;

    while (i < n - 1 && (c = fgetc(f)) != EOF)
    {
        s[i++] = c;
        if (c == '\n')
            break;
    }
    if (i == 0)
        return NULL;
    s[i] = '\0';
    return s;
}

int fputc(int c, FILE *f)
{
    unsigned char ch = c;

    return fwrite(&ch, 1, 1, f) == 1 ? ch : EOF;
}

int fputs(const char *s, FILE *f) { fwrite(s, 1, strlen(s), f); return 0; }
int putchar(int c)                { return fputc(c, stdout); }
int puts(const char *s)           { fputs(s, stdout); return fputc('\n', stdout); }

int remove(const char *path)
{
    struct ramfile *rf = ramfile_find(path);

    if (!rf)
        return -1;
    free(rf->data);
    rf->used = 0;
    return 0;
}

int unlink(const char *path) { return remove(path); }

int rename(const char *oldpath, const char *newpath)
{
    struct ramfile *rf = ramfile_find(oldpath);

    if (!rf)
        return -1;
    remove(newpath);
    strncpy(rf->name, base_name(newpath), RAMFILE_NAME - 1);
    ramfile_persist(rf);                    /* temp.dsg -> doomsavN.dsg */
    return 0;
}

int access(const char *path, int mode)
{
    (void)mode;
    return (is_wad_name(path) || ramfile_find(path) || ramfile_from_disk(path)) ? 0 : -1;
}

int mkdir(const char *path, mode_t mode)
{
    (void)path;
    (void)mode;
    return 0;
}

int stat(const char *path, struct stat *st)
{
    struct ramfile *rf;

    if (is_wad_name(path))
    {
        st->st_size = f64_boot->wad_size;
        st->st_mode = S_IFREG;
        return 0;
    }
    if ((rf = ramfile_find(path)) || (rf = ramfile_from_disk(path)))
    {
        st->st_size = rf->size;
        st->st_mode = S_IFREG;
        return 0;
    }
    errno = ENOENT;
    return -1;
}

/* ==== printf ========================================================== */

struct out {
    char  *buf;
    size_t cap;
    size_t len;
};

static void out_c(struct out *o, char c)
{
    if (o->len + 1 < o->cap)
        o->buf[o->len] = c;
    o->len++;
}

static void out_pad(struct out *o, char c, int n)
{
    while (n-- > 0)
        out_c(o, c);
}

static void out_str(struct out *o, const char *s, int len, int width, int left)
{
    int i;

    if (!left)
        out_pad(o, ' ', width - len);
    for (i = 0; i < len; i++)
        out_c(o, s[i]);
    if (left)
        out_pad(o, ' ', width - len);
}

int vsnprintf(char *buf, size_t cap, const char *fmt, va_list ap)
{
    struct out o = { buf, cap, 0 };

    for (; *fmt; fmt++)
    {
        int left = 0, zero = 0, plus = 0, space = 0, alt = 0;
        int width = 0, prec = -1, lng = 0;
        char tmp[64], *s;
        int len;

        if (*fmt != '%')
        {
            out_c(&o, *fmt);
            continue;
        }
        fmt++;

        for (;; fmt++)
        {
            if (*fmt == '-')      left = 1;
            else if (*fmt == '0') zero = 1;
            else if (*fmt == '+') plus = 1;
            else if (*fmt == ' ') space = 1;
            else if (*fmt == '#') alt = 1;
            else break;
        }
        if (*fmt == '*')
        {
            width = va_arg(ap, int);
            if (width < 0) { left = 1; width = -width; }
            fmt++;
        }
        else
            while (isdigit((uint8_t)*fmt))
                width = width * 10 + (*fmt++ - '0');
        if (*fmt == '.')
        {
            fmt++;
            prec = 0;
            if (*fmt == '*') { prec = va_arg(ap, int); fmt++; }
            else
                while (isdigit((uint8_t)*fmt))
                    prec = prec * 10 + (*fmt++ - '0');
        }
        while (*fmt == 'l' || *fmt == 'h' || *fmt == 'z' || *fmt == 'j' || *fmt == 't')
        {
            if (*fmt == 'l' || *fmt == 'z' || *fmt == 'j' || *fmt == 't')
                lng = 1;
            fmt++;
        }

        switch (*fmt)
        {
        case 'd': case 'i': case 'u': case 'x': case 'X': case 'o': case 'p':
        {
            unsigned long long v;
            int neg = 0, base = 10, upper = 0, n = 0, digits;
            char sign = 0;
            const char *prefix = "";

            if (*fmt == 'p')
            {
                v = (uintptr_t)va_arg(ap, void *);
                base = 16;
                prefix = "0x";
            }
            else if (*fmt == 'd' || *fmt == 'i')
            {
                long long sv = lng ? va_arg(ap, long) : va_arg(ap, int);
                if (sv < 0) { neg = 1; v = -(unsigned long long)sv; }
                else v = sv;
            }
            else
            {
                v = lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned int);
                if (*fmt == 'x' || *fmt == 'X') base = 16;
                if (*fmt == 'o') base = 8;
                if (*fmt == 'X') upper = 1;
                if (alt && base == 16 && v) prefix = upper ? "0X" : "0x";
                if (alt && base == 8) prefix = "0";
            }

            do {
                int d = v % base;
                tmp[sizeof(tmp) - 1 - n++] = d < 10 ? '0' + d : (upper ? 'A' : 'a') + d - 10;
                v /= base;
            } while (v);
            if (prec == 0 && n == 1 && tmp[sizeof(tmp) - 1] == '0')
                n = 0;

            if (neg) sign = '-';
            else if (plus && (*fmt == 'd' || *fmt == 'i')) sign = '+';
            else if (space && (*fmt == 'd' || *fmt == 'i')) sign = ' ';

            digits = n > prec ? n : prec;
            len = digits + (sign ? 1 : 0) + (int)strlen(prefix);

            if (!left && !(zero && prec < 0))
                out_pad(&o, ' ', width - len);
            if (sign)
                out_c(&o, sign);
            for (s = (char *)prefix; *s; s++)
                out_c(&o, *s);
            if (!left && zero && prec < 0)
                out_pad(&o, '0', width - len);
            out_pad(&o, '0', digits - n);
            for (s = tmp + sizeof(tmp) - n; s < tmp + sizeof(tmp); s++)
                out_c(&o, *s);
            if (left)
                out_pad(&o, ' ', width - len);
            break;
        }
        case 'f': case 'g': case 'e':
        {
            double v = va_arg(ap, double);
            unsigned long long ip;
            double frac;
            int n = 0, i;

            if (prec < 0) prec = 6;
            if (prec > 9) prec = 9;
            if (v < 0) { tmp[n++] = '-'; v = -v; }
            for (i = 0, frac = 0.5; i < prec; i++)
                frac /= 10;
            v += frac;
            ip = (unsigned long long)v;
            frac = v - (double)ip;
            n += snprintf(tmp + n, sizeof(tmp) - n, "%llu", ip);
            if (prec > 0)
            {
                tmp[n++] = '.';
                for (i = 0; i < prec; i++)
                {
                    frac *= 10;
                    tmp[n++] = '0' + (int)frac;
                    frac -= (int)frac;
                }
            }
            out_str(&o, tmp, n, width, left);
            break;
        }
        case 's':
            s = va_arg(ap, char *);
            if (!s)
                s = "(null)";
            len = prec >= 0 ? (int)strnlen(s, prec) : (int)strlen(s);
            out_str(&o, s, len, width, left);
            break;
        case 'c':
            tmp[0] = (char)va_arg(ap, int);
            out_str(&o, tmp, 1, width, left);
            break;
        case '%':
            out_c(&o, '%');
            break;
        case '\0':
            fmt--;
            break;
        default:
            out_c(&o, '%');
            out_c(&o, *fmt);
            break;
        }
    }

    if (cap)
        buf[o.len < cap ? o.len : cap - 1] = '\0';
    return (int)o.len;
}

int vsprintf(char *buf, const char *fmt, va_list ap)
{
    return vsnprintf(buf, (size_t)-1 >> 1, fmt, ap);
}

int vfprintf(FILE *f, const char *fmt, va_list ap)
{
    char buf[1024];
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);

    fwrite(buf, 1, n < (int)sizeof(buf) ? n : (int)sizeof(buf) - 1, f);
    return n;
}

int vprintf(const char *fmt, va_list ap)
{
    return vfprintf(stdout, fmt, ap);
}

int snprintf(char *buf, size_t n, const char *fmt, ...)
{
    va_list ap;
    int r;

    va_start(ap, fmt);
    r = vsnprintf(buf, n, fmt, ap);
    va_end(ap);
    return r;
}

int sprintf(char *buf, const char *fmt, ...)
{
    va_list ap;
    int r;

    va_start(ap, fmt);
    r = vsprintf(buf, fmt, ap);
    va_end(ap);
    return r;
}

int fprintf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    int r;

    va_start(ap, fmt);
    r = vfprintf(f, fmt, ap);
    va_end(ap);
    return r;
}

int printf(const char *fmt, ...)
{
    va_list ap;
    int r;

    va_start(ap, fmt);
    r = vfprintf(stdout, fmt, ap);
    va_end(ap);
    return r;
}

/* ==== scanf =========================================================== */

/* Enough of sscanf for DOOM: %d %i %u %x %o %s %c and %[...], with a
 * width, and literal text. Returns the number of fields assigned. */
static int vsscanf_core(const char *str, const char *fmt, va_list ap)
{
    const char *s = str;
    int count = 0;

    for (; *fmt; fmt++)
    {
        int width = 0;

        if (isspace((uint8_t)*fmt))
        {
            while (isspace((uint8_t)*s))
                s++;
            continue;
        }
        if (*fmt != '%')
        {
            if (*s != *fmt)
                break;
            s++;
            continue;
        }
        fmt++;
        while (isdigit((uint8_t)*fmt))
            width = width * 10 + (*fmt++ - '0');

        if (*fmt == 'd' || *fmt == 'i' || *fmt == 'u' || *fmt == 'x' || *fmt == 'o')
        {
            int base = *fmt == 'x' ? 16 : *fmt == 'o' ? 8 : *fmt == 'i' ? 0 : 10;
            char *end;
            long v;

            while (isspace((uint8_t)*s))
                s++;
            v = strtol(s, &end, base);
            if (end == s)
                break;
            s = end;
            *va_arg(ap, int *) = (int)v;
            count++;
        }
        else if (*fmt == 's')
        {
            char *d = va_arg(ap, char *);
            int n = 0;

            while (isspace((uint8_t)*s))
                s++;
            if (!*s)
                break;
            while (*s && !isspace((uint8_t)*s) && (!width || n < width))
                d[n++] = *s++;
            d[n] = '\0';
            count++;
        }
        else if (*fmt == 'c')
        {
            if (!*s)
                break;
            *va_arg(ap, char *) = *s++;
            count++;
        }
        else if (*fmt == '[')
        {
            char *d = va_arg(ap, char *);
            const char *set = ++fmt;
            int neg = 0, n = 0;

            if (*set == '^') { neg = 1; set++; fmt++; }
            while (*fmt && *fmt != ']')
                fmt++;
            while (*s && (!width || n < width))
            {
                const char *p;
                int in = 0;

                for (p = set; p < fmt; p++)
                {
                    if (*p == '\\' && p[1] == 'n') { if (*s == '\n') in = 1; p++; }
                    else if (*p == *s) in = 1;
                }
                if (in == neg)
                    break;
                d[n++] = *s++;
            }
            if (n == 0)
                break;
            d[n] = '\0';
            count++;
        }
        else
            break;
    }
    return count;
}

int sscanf(const char *str, const char *fmt, ...)
{
    va_list ap;
    int r;

    va_start(ap, fmt);
    r = vsscanf_core(str, fmt, ap);
    va_end(ap);
    return r;
}

/* fscanf reads one line and scans it. DOOM uses it only for config
 * files, one setting per line. */
int fscanf(FILE *f, const char *fmt, ...)
{
    char line[512];
    va_list ap;
    int r;

    if (!fgets(line, sizeof(line), f))
        return EOF;
    va_start(ap, fmt);
    r = vsscanf_core(line, fmt, ap);
    va_end(ap);
    return r;
}

/* ==== Start ========================================================== */

void f64_libc_init(void)
{
    heap_init();
    errno = 0;
}
