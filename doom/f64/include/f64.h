/*
 * f64.h - interface between DOOM and the f64OS kernel.
 *
 * doom.f (Forth) loads doom.bin and the WAD file into memory, fills a
 * boot block, and calls the first byte of doom.bin with CALL-NATIVE.
 * The layouts below must agree with doom.f and with Kernel_services in
 * kernel/kernel.nasm.
 */
#ifndef F64_H
#define F64_H

#include <stdint.h>
#include <stddef.h>

/* Kernel service table (Kernel_services in kernel.nasm). */
struct f64_ksvc {
    uint64_t          version;    /* 2 or more for the mouse fields */
    volatile uint64_t *ticks;     /* PIT ticks since boot */
    volatile uint8_t  *scan_ring; /* 256-byte ring of raw set-1 scancodes */
    volatile uint8_t  *scan_wpos; /* next write slot in scan_ring */
    volatile uint8_t  *kbd_wpos;  /* next write slot in the ASCII ring */
    volatile uint8_t  *kbd_rpos;  /* next read slot in the ASCII ring */
    volatile uint8_t  *mouse_ring; /* version 2: 256-byte ring of PS/2 mouse bytes */
    volatile uint8_t  *mouse_wpos; /* version 2: next write slot in mouse_ring */
};

/* Boot block, filled by doom.f. One 64-bit cell per field. */
struct f64_boot {
    uint64_t         version;      /* 1 */
    struct f64_ksvc *ksvc;
    uint8_t         *wad;          /* WAD file contents */
    uint64_t         wad_size;
    const char      *wad_name;     /* WAD file name (not NUL-terminated) */
    uint64_t         wad_name_len;
    uint8_t         *heap_start;   /* free RAM for malloc */
    uint8_t         *heap_end;
    uint8_t         *image_limit;  /* doom.bin + BSS must end below this */
    uint8_t         *dma_buf;      /* 64 KiB aligned, below 16 MiB, for sound */
    uint64_t         cwd_lba;      /* f64OS directory for savegames and config */
};

extern struct f64_boot *f64_boot;

static inline void outb(uint16_t port, uint8_t v)
{
    __asm__ volatile("outb %0, %1" : : "a"(v), "Nd"(port));
}

static inline uint8_t inb(uint16_t port)
{
    uint8_t v;
    __asm__ volatile("inb %1, %0" : "=a"(v) : "Nd"(port));
    return v;
}

static inline void f64_hlt(void)
{
    __asm__ volatile("hlt");
}

/* libc.c */
void        f64_libc_init(void);
void        f64_console_write(const char *s, size_t n);
void        f64_console_clear(void);
void        f64_console_graphics(int on);
const char *f64_error_text(void);

/* disk_f64.c */
void f64_disk_init(void);

/* sound_f64.c and music_f64.c */
void f64_sound_pump(void);      /* mix sound and run music events */
void f64_sound_shutdown(void);  /* stop all sound output */

/* doomgeneric_f64.c */
void f64_platform_start(void);
void f64_platform_stop(void);
void f64_mouse_events(void);    /* post mouse movement and buttons to DOOM */

#endif
