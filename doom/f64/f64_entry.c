/*
 * f64_entry.c - entry point of doom.bin on f64OS.
 *
 * The linker script puts the .entry section at the first byte of
 * doom.bin, so CALL-NATIVE can jump to the load address directly.
 * f64_main() returns NULL after a normal quit, or a pointer to an error
 * message that doom.f shows on the Forth console.
 */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "f64.h"
#include "doomgeneric.h"

extern char __bss_start[], __bss_end[];

struct f64_boot *f64_boot;

static void *exit_buf[5];
static int   exit_status;
static char  iwad_name[64];
static char *doom_argv[] = { "doom", "-iwad", iwad_name, NULL };

__attribute__((section(".entry"), used, noinline))
const char *f64_main(struct f64_boot *boot)
{
    volatile char *p;
    size_t n;

    /* doom.bin holds no BSS. Clear it before any C code uses it. */
    for (p = __bss_start; p < __bss_end; p++)
        *p = 0;

    if (boot->version != 1)
        return "DOOM: boot block version is not 1.";
    if ((uint8_t *)__bss_end > boot->image_limit)
        return "DOOM: doom.bin and its BSS do not fit below the stack.";

    f64_boot = boot;

    n = boot->wad_name_len;
    if (n >= sizeof(iwad_name))
        n = sizeof(iwad_name) - 1;
    memcpy(iwad_name, boot->wad_name, n);
    iwad_name[n] = '\0';

    f64_libc_init();
    f64_platform_start();

    if (__builtin_setjmp(exit_buf) == 0)
    {
        doomgeneric_Create(3, doom_argv);
        for (;;)
            doomgeneric_Tick();
    }

    /* exit() comes back here. */
    f64_platform_stop();
    return exit_status ? f64_error_text() : NULL;
}

void exit(int status)
{
    exit_status = status;
    __builtin_longjmp(exit_buf, 1);
}

void abort(void)
{
    exit(-1);
}
