/*
 * doomgeneric_f64.c - doomgeneric platform layer for f64OS.
 *
 * Video:    VGA mode 13h (320x200, 256 colors), the native DOOM size.
 *           The text mode state (registers, font, screen, palette) is
 *           saved at start and put back at exit.
 * Timer:    the PIT runs at 1000 Hz while DOOM runs, so one kernel tick
 *           is one millisecond. The BIOS rate (18.2 Hz) comes back at exit.
 * Keyboard: raw set-1 scancodes from the kernel scancode ring.
 */
#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include "f64.h"
#include "doomgeneric.h"
#include "doomkeys.h"
#include "i_video.h"

/* ---- VGA ports ------------------------------------------------------- */

#define VGA_AC_INDEX     0x3C0
#define VGA_AC_READ      0x3C1
#define VGA_MISC_WRITE   0x3C2
#define VGA_SEQ_INDEX    0x3C4
#define VGA_SEQ_DATA     0x3C5
#define VGA_DAC_RINDEX   0x3C7
#define VGA_DAC_WINDEX   0x3C8
#define VGA_DAC_DATA     0x3C9
#define VGA_MISC_READ    0x3CC
#define VGA_GC_INDEX     0x3CE
#define VGA_GC_DATA      0x3CF
#define VGA_CRTC_INDEX   0x3D4
#define VGA_CRTC_DATA    0x3D5
#define VGA_INSTAT_READ  0x3DA

#define VGA_GRAPHICS ((volatile uint8_t *)0xA0000)
#define VGA_TEXT     ((volatile uint8_t *)0xB8000)
#define TEXT_BYTES   (80 * 25 * 2)
#define FONT_BYTES   (256 * 32)

struct vga_regs {
    uint8_t misc;
    uint8_t seq[5];
    uint8_t crtc[25];
    uint8_t gc[9];
    uint8_t ac[21];
};

/* Standard VGA mode 13h register values. */
static const struct vga_regs mode13h = {
    0x63,
    { 0x03, 0x01, 0x0F, 0x00, 0x0E },
    { 0x5F, 0x4F, 0x50, 0x82, 0x54, 0x80, 0xBF, 0x1F, 0x00, 0x41, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x9C, 0x0E, 0x8F, 0x28, 0x40, 0x96, 0xB9, 0xA3,
      0xFF },
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x05, 0x0F, 0xFF },
    { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B,
      0x0C, 0x0D, 0x0E, 0x0F, 0x41, 0x00, 0x0F, 0x00, 0x00 }
};

static struct vga_regs saved_regs;
static uint8_t saved_text[TEXT_BYTES];
static uint8_t saved_font[FONT_BYTES];
static uint8_t saved_dac[768];
static int     in_graphics;

static uint8_t seq_read(int i)  { outb(VGA_SEQ_INDEX, i);  return inb(VGA_SEQ_DATA); }
static uint8_t gc_read(int i)   { outb(VGA_GC_INDEX, i);   return inb(VGA_GC_DATA); }
static uint8_t crtc_read(int i) { outb(VGA_CRTC_INDEX, i); return inb(VGA_CRTC_DATA); }
static void seq_write(int i, uint8_t v)  { outb(VGA_SEQ_INDEX, i);  outb(VGA_SEQ_DATA, v); }
static void gc_write(int i, uint8_t v)   { outb(VGA_GC_INDEX, i);   outb(VGA_GC_DATA, v); }
static void crtc_write(int i, uint8_t v) { outb(VGA_CRTC_INDEX, i); outb(VGA_CRTC_DATA, v); }

static void vga_read_regs(struct vga_regs *r)
{
    int i;

    r->misc = inb(VGA_MISC_READ);
    for (i = 0; i < 5; i++)  r->seq[i] = seq_read(i);
    for (i = 0; i < 25; i++) r->crtc[i] = crtc_read(i);
    for (i = 0; i < 9; i++)  r->gc[i] = gc_read(i);
    for (i = 0; i < 21; i++)
    {
        (void)inb(VGA_INSTAT_READ);      /* reset the AC flip-flop */
        outb(VGA_AC_INDEX, i);
        r->ac[i] = inb(VGA_AC_READ);
    }
    (void)inb(VGA_INSTAT_READ);
    outb(VGA_AC_INDEX, 0x20);            /* display on */
}

static void vga_write_regs(const struct vga_regs *r)
{
    int i;
    uint8_t v;

    outb(VGA_MISC_WRITE, r->misc);
    for (i = 0; i < 5; i++)
        seq_write(i, r->seq[i]);

    /* Unlock CRTC registers 0-7. */
    crtc_write(0x03, crtc_read(0x03) | 0x80);
    crtc_write(0x11, crtc_read(0x11) & ~0x80);
    for (i = 0; i < 25; i++)
    {
        v = r->crtc[i];
        if (i == 0x03) v |= 0x80;
        if (i == 0x11) v &= ~0x80;
        crtc_write(i, v);
    }

    for (i = 0; i < 9; i++)
        gc_write(i, r->gc[i]);

    for (i = 0; i < 21; i++)
    {
        (void)inb(VGA_INSTAT_READ);
        outb(VGA_AC_INDEX, i);
        outb(VGA_AC_INDEX, r->ac[i]);
    }
    (void)inb(VGA_INSTAT_READ);
    outb(VGA_AC_INDEX, 0x20);
}

/* Give the CPU flat access to plane 2 (the text font) at 0xA0000.
 * The caller must put back seq 2/4 and gc 4/5/6 after. */
static void vga_plane2_access(void)
{
    seq_write(2, 0x04);   /* write plane 2 only */
    seq_write(4, 0x07);   /* sequential addressing, no odd/even */
    gc_write(4, 0x02);    /* read plane 2 */
    gc_write(5, 0x00);    /* no odd/even */
    gc_write(6, 0x04);    /* map 0xA0000, 64 KiB, no chaining */
}

static void vga_plane_access_restore(const struct vga_regs *r)
{
    seq_write(2, r->seq[2]);
    seq_write(4, r->seq[4]);
    gc_write(4, r->gc[4]);
    gc_write(5, r->gc[5]);
    gc_write(6, r->gc[6]);
}

static void vga_save_text_mode(void)
{
    int i;

    vga_read_regs(&saved_regs);

    for (i = 0; i < TEXT_BYTES; i++)
        saved_text[i] = VGA_TEXT[i];

    outb(VGA_DAC_RINDEX, 0);
    for (i = 0; i < 768; i++)
        saved_dac[i] = inb(VGA_DAC_DATA);

    vga_plane2_access();
    for (i = 0; i < FONT_BYTES; i++)
        saved_font[i] = VGA_GRAPHICS[i];
    vga_plane_access_restore(&saved_regs);
}

/* Put text mode back: registers, font and palette. The screen contents
 * are the caller's job. */
static void vga_text_mode(void)
{
    int i;

    vga_write_regs(&saved_regs);

    vga_plane2_access();
    for (i = 0; i < FONT_BYTES; i++)
        VGA_GRAPHICS[i] = saved_font[i];
    vga_plane_access_restore(&saved_regs);

    outb(VGA_DAC_WINDEX, 0);
    for (i = 0; i < 768; i++)
        outb(VGA_DAC_DATA, saved_dac[i]);

    in_graphics = 0;
    f64_console_graphics(0);
}

static void vga_graphics_mode(void)
{
    int i;

    vga_write_regs(&mode13h);
    for (i = 0; i < 320 * 200; i++)
        VGA_GRAPHICS[i] = 0;
    in_graphics = 1;
    f64_console_graphics(1);
}

/* ---- PIT ------------------------------------------------------------ */

static void pit_set_hz(unsigned hz)
{
    unsigned divisor = hz ? 1193182 / hz : 0;   /* 0 means 65536 */

    outb(0x43, 0x36);                           /* channel 0, mode 3 */
    outb(0x40, divisor & 0xFF);
    outb(0x40, (divisor >> 8) & 0xFF);
}

/* ---- Keyboard -------------------------------------------------------- */

/* Set-1 make codes (0x00-0x7F) without the 0xE0 prefix. */
static const unsigned char scancode_map[128] = {
    [0x01] = KEY_ESCAPE,
    [0x02] = '1', [0x03] = '2', [0x04] = '3', [0x05] = '4', [0x06] = '5',
    [0x07] = '6', [0x08] = '7', [0x09] = '8', [0x0A] = '9', [0x0B] = '0',
    [0x0C] = KEY_MINUS, [0x0D] = KEY_EQUALS, [0x0E] = KEY_BACKSPACE,
    [0x0F] = KEY_TAB,
    [0x10] = 'q', [0x11] = 'w', [0x12] = 'e', [0x13] = 'r', [0x14] = 't',
    [0x15] = 'y', [0x16] = 'u', [0x17] = 'i', [0x18] = 'o', [0x19] = 'p',
    [0x1A] = '[', [0x1B] = ']', [0x1C] = KEY_ENTER, [0x1D] = KEY_FIRE,
    [0x1E] = 'a', [0x1F] = 's', [0x20] = 'd', [0x21] = 'f', [0x22] = 'g',
    [0x23] = 'h', [0x24] = 'j', [0x25] = 'k', [0x26] = 'l', [0x27] = ';',
    [0x28] = '\'', [0x29] = '`', [0x2A] = KEY_RSHIFT, [0x2B] = '\\',
    [0x2C] = 'z', [0x2D] = 'x', [0x2E] = 'c', [0x2F] = 'v', [0x30] = 'b',
    [0x31] = 'n', [0x32] = 'm', [0x33] = ',', [0x34] = '.', [0x35] = '/',
    [0x36] = KEY_RSHIFT, [0x37] = KEYP_MULTIPLY, [0x38] = KEY_RALT,
    [0x39] = KEY_USE, [0x3A] = KEY_CAPSLOCK,
    [0x3B] = KEY_F1, [0x3C] = KEY_F2, [0x3D] = KEY_F3, [0x3E] = KEY_F4,
    [0x3F] = KEY_F5, [0x40] = KEY_F6, [0x41] = KEY_F7, [0x42] = KEY_F8,
    [0x43] = KEY_F9, [0x44] = KEY_F10, [0x45] = KEY_NUMLOCK,
    [0x46] = KEY_SCRLCK,
    /* keypad */
    [0x47] = KEYP_7, [0x48] = KEYP_8, [0x49] = KEYP_9, [0x4A] = KEYP_MINUS,
    [0x4B] = KEYP_4, [0x4C] = KEYP_5, [0x4D] = KEYP_6, [0x4E] = KEYP_PLUS,
    [0x4F] = KEYP_1, [0x50] = KEYP_2, [0x51] = KEYP_3,
    [0x57] = KEY_F11, [0x58] = KEY_F12,
};

/* Set-1 make codes after an 0xE0 prefix. */
static unsigned char scancode_e0(uint8_t code)
{
    switch (code)
    {
    case 0x1C: return KEY_ENTER;      /* keypad Enter */
    case 0x1D: return KEY_FIRE;       /* right Ctrl */
    case 0x35: return KEYP_DIVIDE;
    case 0x38: return KEY_RALT;       /* right Alt */
    case 0x47: return KEY_HOME;
    case 0x48: return KEY_UPARROW;
    case 0x49: return KEY_PGUP;
    case 0x4B: return KEY_LEFTARROW;
    case 0x4D: return KEY_RIGHTARROW;
    case 0x4F: return KEY_END;
    case 0x50: return KEY_DOWNARROW;
    case 0x51: return KEY_PGDN;
    case 0x52: return KEY_INS;
    case 0x53: return KEY_DEL;
    default:   return 0;              /* includes the fake shifts E0 2A/AA */
    }
}

static uint8_t scan_rpos;
static int     scan_e0;
static int     scan_e1;

/* Take one raw scancode from the kernel ring. Returns -1 if it is empty. */
static int scan_next(void)
{
    struct f64_ksvc *k = f64_boot->ksvc;

    if (scan_rpos == *k->scan_wpos)
        return -1;
    return k->scan_ring[scan_rpos++];
}

int DG_GetKey(int *pressed, unsigned char *doomKey)
{
    int sc;

    while ((sc = scan_next()) >= 0)
    {
        uint8_t code = sc & 0x7F;
        int release = (sc & 0x80) != 0;
        unsigned char key;

        if (sc == 0xE0) { scan_e0 = 1; continue; }

        /* Pause sends E1 1D 45 E1 9D C5 and has no release code. */
        if (sc == 0xE1) { scan_e1 = 2; continue; }
        if (scan_e1)
        {
            if (--scan_e1 == 0 && code == 0x45)
            {
                *pressed = !release;
                *doomKey = KEY_PAUSE;
                return 1;
            }
            continue;
        }

        key = scan_e0 ? scancode_e0(code) : scancode_map[code];
        scan_e0 = 0;
        if (key == 0)
            continue;

        *pressed = !release;
        *doomKey = key;
        return 1;
    }
    return 0;
}

/* Discard all keyboard input that the Forth console has not read. */
static void keyboard_flush(void)
{
    struct f64_ksvc *k = f64_boot->ksvc;

    *k->kbd_rpos = *k->kbd_wpos;
    scan_rpos = *k->scan_wpos;
}

/* ---- doomgeneric interface ------------------------------------------- */

static uint64_t start_ticks;

void DG_Init(void)
{
    vga_graphics_mode();
}

void DG_DrawFrame(void)
{
    int i;

    if (palette_changed)
    {
        palette_changed = false;
        outb(VGA_DAC_WINDEX, 0);
        for (i = 0; i < 256; i++)
        {
            outb(VGA_DAC_DATA, colors[i].r >> 2);
            outb(VGA_DAC_DATA, colors[i].g >> 2);
            outb(VGA_DAC_DATA, colors[i].b >> 2);
        }
    }
    memcpy((void *)VGA_GRAPHICS, DG_ScreenBuffer, 320 * 200);
    f64_sound_pump();
}

uint32_t DG_GetTicksMs(void)
{
    return (uint32_t)(*f64_boot->ksvc->ticks - start_ticks);
}

void DG_SleepMs(uint32_t ms)
{
    uint32_t until = DG_GetTicksMs() + ms;

    f64_sound_pump();
    while ((int32_t)(DG_GetTicksMs() - until) < 0)
    {
        f64_hlt();
        f64_sound_pump();
    }
}

void DG_SetWindowTitle(const char *title)
{
    (void)title;
}

/* Show the ENDOOM text screen (called from I_Endoom) until a key press. */
void f64_endoom(const unsigned char *data)
{
    int i, sc;

    f64_sound_shutdown();
    vga_text_mode();
    for (i = 0; i < TEXT_BYTES; i++)
        VGA_TEXT[i] = data[i];

    keyboard_flush();
    for (;;)
    {
        sc = scan_next();
        if (sc >= 0 && sc < 0x80 && sc != 0xE0 && sc != 0xE1)
            break;
        f64_hlt();
    }
}

/* ---- start and stop -------------------------------------------------- */

void f64_platform_start(void)
{
    vga_save_text_mode();
    in_graphics = 0;
    f64_console_clear();

    pit_set_hz(1000);
    start_ticks = *f64_boot->ksvc->ticks;
    scan_rpos = *f64_boot->ksvc->scan_wpos;
}

void f64_platform_stop(void)
{
    int i;

    f64_sound_shutdown();
    pit_set_hz(0);
    vga_text_mode();
    for (i = 0; i < TEXT_BYTES; i++)
        VGA_TEXT[i] = saved_text[i];
    keyboard_flush();
}
