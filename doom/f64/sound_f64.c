/*
 * sound_f64.c - DOOM sound effects on a Sound Blaster 16 (f64OS).
 *
 * Output: 8-bit unsigned stereo at 22050 Hz, auto-init DMA on channel 1,
 * from a 16 KiB ring buffer below 16 MiB (ISA DMA limit). doom.f gives
 * the buffer address in the boot block.
 *
 * The mixer runs in the main program (f64_sound_pump). It keeps the ring
 * filled a little ahead of the DMA play position. The SB16 raises IRQ 5
 * after each half of the ring. A small interrupt handler fills the half
 * that just finished with silence. Thus, when DOOM stops pumping (for
 * example while it loads a level), the card plays silence and does not
 * repeat old audio.
 *
 * QEMU: -audiodev <driver>,id=snd0 -device sb16,audiodev=snd0
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "f64.h"
#include "doomtype.h"
#include "i_sound.h"
#include "w_wad.h"
#include "z_zone.h"
#include "deh_str.h"

/* Needed by i_sound.c and m_config.c when FEATURE_SOUND is on. */
int   use_libsamplerate = 0;
float libsamplerate_scale = 0.65f;

#define SB_BASE      0x220
#define SB_RESET     (SB_BASE + 0x6)
#define SB_READ      (SB_BASE + 0xA)
#define SB_WRITE     (SB_BASE + 0xC)
#define SB_STATUS    (SB_BASE + 0xE)

#define SB_IRQ       5
#define SB_VECTOR    (0x20 + SB_IRQ)  /* the kernel maps IRQ 0-7 to 0x20-0x27 */

#define OUT_RATE     22050
#define RING_SIZE    16384            /* bytes; must be a power of two */
#define RING_HALF    (RING_SIZE / 2)
#define RING_LEAD    2560             /* bytes mixed ahead (about 58 ms) */

#define NUM_CHANNELS 16

/* The interrupt handler uses these values as literal numbers. */
_Static_assert(SB_STATUS == 0x22E, "update f64_sb16_isr");
_Static_assert(RING_HALF == 8192, "update f64_sb16_isr");

/* Used by the interrupt handler below. */
uint64_t f64_sb16_buf;

/*
 * IRQ 5 handler. Acknowledge the DSP, find the ring half that just
 * finished from the DMA address, and fill it with silence (0x80).
 * The ring is 64 KiB aligned, so the low 16 bits of the DMA address are
 * the offset in the ring. It uses only general registers.
 */
__asm__(
    ".text\n"
    ".globl f64_sb16_isr\n"
    "f64_sb16_isr:\n"
    "    push %rax\n"
    "    push %rcx\n"
    "    push %rdx\n"
    "    push %rdi\n"
    "    mov  $0x22E, %dx\n"              /* SB_STATUS */
    "    in   %dx, %al\n"                 /* acknowledge 8-bit DMA IRQ */
    "    xor  %eax, %eax\n"
    "    out  %al, $0x0C\n"               /* clear the DMA flip-flop */
    "    in   $0x02, %al\n"
    "    mov  %al, %cl\n"
    "    in   $0x02, %al\n"
    "    mov  %al, %ch\n"
    "    movzwl %cx, %ecx\n"
    "    xor  %edi, %edi\n"
    "    cmp  $8192, %ecx\n"              /* RING_HALF */
    "    jae  1f\n"
    "    mov  $8192, %edi\n"              /* lower half plays: clear the upper */
    "1:\n"
    "    add  f64_sb16_buf(%rip), %rdi\n"
    "    mov  $8192, %ecx\n"              /* RING_HALF */
    "    mov  $0x80, %al\n"
    "    cld\n"
    "    rep stosb\n"
    "    mov  $0x20, %al\n"
    "    out  %al, $0x20\n"               /* EOI to the master PIC */
    "    pop  %rdi\n"
    "    pop  %rdx\n"
    "    pop  %rcx\n"
    "    pop  %rax\n"
    "    iretq\n");

void f64_sb16_isr(void);

struct idt_entry {
    uint16_t off_lo;
    uint16_t selector;
    uint8_t  ist;
    uint8_t  type;
    uint16_t off_mid;
    uint32_t off_hi;
    uint32_t zero;
} __attribute__((packed));

struct sfx {
    const uint8_t *data;     /* 8-bit unsigned samples */
    uint32_t       length;   /* number of samples */
    uint32_t       step;     /* 16.16 source samples per output sample */
};

struct channel {
    const struct sfx *sfx;
    uint32_t          pos;   /* 16.16 */
    int               lvol, rvol;
};

static int              sb_ok;
static int              sfx_prefix;
static uint8_t         *ring;
static uint32_t         wr;            /* next ring offset to mix */
static struct channel   channels[NUM_CHANNELS];
static struct idt_entry saved_idt;
static uint8_t          saved_pic_mask;
static int              irq_installed;

/* ---- hardware ---------------------------------------------------------- */

static void io_delay(void)
{
    outb(0x80, 0);
}

static int dsp_write(uint8_t v)
{
    int i;

    for (i = 0; i < 100000; i++)
        if (!(inb(SB_WRITE) & 0x80))
        {
            outb(SB_WRITE, v);
            return 1;
        }
    return 0;
}

static int dsp_read(void)
{
    int i;

    for (i = 0; i < 100000; i++)
        if (inb(SB_STATUS) & 0x80)
            return inb(SB_READ);
    return -1;
}

static int dsp_reset(void)
{
    int i;

    outb(SB_RESET, 1);
    for (i = 0; i < 10; i++)
        io_delay();
    outb(SB_RESET, 0);
    for (i = 0; i < 1000; i++)
        if (dsp_read() == 0xAA)
            return 1;
    return 0;
}

/* Current DMA channel 1 offset in the ring. */
static uint32_t dma_pos(void)
{
    uint64_t flags;
    uint8_t lo, hi;

    __asm__ volatile("pushfq; pop %0; cli" : "=r"(flags));
    outb(0x0C, 0);
    lo = inb(0x02);
    hi = inb(0x02);
    if (flags & 0x200)
        __asm__ volatile("sti");
    return (uint32_t)((hi << 8) | lo) & (RING_SIZE - 1);
}

static void dma_start(uint32_t phys, uint32_t len)
{
    outb(0x0A, 0x05);                       /* mask channel 1 */
    outb(0x0C, 0x00);                       /* clear flip-flop */
    outb(0x0B, 0x59);                       /* single, auto-init, read, ch 1 */
    outb(0x02, phys & 0xFF);
    outb(0x02, (phys >> 8) & 0xFF);
    outb(0x83, (phys >> 16) & 0xFF);        /* page register for ch 1 */
    outb(0x03, (len - 1) & 0xFF);
    outb(0x03, ((len - 1) >> 8) & 0xFF);
    outb(0x0A, 0x01);                       /* unmask channel 1 */
}

static void idt_set(int vector, const struct idt_entry *e, struct idt_entry *old)
{
    struct { uint16_t limit; uint64_t base; } __attribute__((packed)) idtr;
    struct idt_entry *idt;
    uint64_t flags;

    __asm__ volatile("sidt %0" : "=m"(idtr));
    idt = (struct idt_entry *)idtr.base;
    __asm__ volatile("pushfq; pop %0; cli" : "=r"(flags));
    if (old)
        *old = idt[vector];
    idt[vector] = *e;
    if (flags & 0x200)
        __asm__ volatile("sti");
}

static void irq_install(void)
{
    struct idt_entry e;
    uint64_t addr = (uint64_t)(uintptr_t)f64_sb16_isr;
    uint16_t cs;

    __asm__ volatile("mov %%cs, %0" : "=r"(cs));
    e.off_lo = addr & 0xFFFF;
    e.selector = cs;
    e.ist = 0;
    e.type = 0x8E;                          /* present, interrupt gate */
    e.off_mid = (addr >> 16) & 0xFFFF;
    e.off_hi = addr >> 32;
    e.zero = 0;
    idt_set(SB_VECTOR, &e, &saved_idt);

    saved_pic_mask = inb(0x21);
    outb(0x21, saved_pic_mask & ~(1 << SB_IRQ));
    irq_installed = 1;
}

static void irq_remove(void)
{
    if (!irq_installed)
        return;
    outb(0x21, inb(0x21) | (1 << SB_IRQ));
    idt_set(SB_VECTOR, &saved_idt, NULL);
    outb(0x21, saved_pic_mask);
    irq_installed = 0;
}

/* ---- mixer ------------------------------------------------------------- */

static void mix(uint8_t *out, uint32_t frames)
{
    uint32_t f;
    int c;

    for (f = 0; f < frames; f++)
    {
        int l = 0, r = 0;

        for (c = 0; c < NUM_CHANNELS; c++)
        {
            struct channel *ch = &channels[c];
            uint32_t i;
            int s;

            if (!ch->sfx)
                continue;
            i = ch->pos >> 16;
            if (i >= ch->sfx->length)
            {
                ch->sfx = NULL;
                continue;
            }
            s = (int)ch->sfx->data[i] - 128;
            l += s * ch->lvol;
            r += s * ch->rvol;
            ch->pos += ch->sfx->step;
        }
        l = (l >> 7) + 128;
        r = (r >> 7) + 128;
        out[2 * f]     = l < 0 ? 0 : l > 255 ? 255 : l;
        out[2 * f + 1] = r < 0 ? 0 : r > 255 ? 255 : r;
    }
}

static void sfx_pump(void)
{
    uint32_t play, lag, n, first;

    if (!sb_ok)
        return;

    play = dma_pos();
    lag = (wr - play) & (RING_SIZE - 1);
    if (lag > RING_HALF)
    {
        /* The DMA passed the mixer (a long stall). Start again near it. */
        wr = (play + 64) & (RING_SIZE - 1) & ~1u;
        lag = (wr - play) & (RING_SIZE - 1);
    }
    if (lag >= RING_LEAD)
        return;

    n = (RING_LEAD - lag) & ~1u;
    first = RING_SIZE - wr;
    if (first > n)
        first = n;
    mix(ring + wr, first / 2);
    if (n > first)
        mix(ring, (n - first) / 2);
    wr = (wr + n) & (RING_SIZE - 1);
}

/* ---- DOOM sound module ------------------------------------------------- */

static void sb_shutdown(void)
{
    if (!sb_ok)
        return;
    dsp_write(0xDA);                        /* exit 8-bit auto-init */
    dsp_write(0xD3);                        /* speaker off */
    outb(0x0A, 0x05);                       /* mask DMA channel 1 */
    irq_remove();
    dsp_reset();
    sb_ok = 0;
}

static boolean sb_init(boolean use_sfx_prefix)
{
    int major, minor;

    sfx_prefix = use_sfx_prefix;
    memset(channels, 0, sizeof(channels));

    if (!f64_boot->dma_buf || ((uintptr_t)f64_boot->dma_buf & 0xFFFF)
        || (uintptr_t)f64_boot->dma_buf + RING_SIZE > 0x1000000)
    {
        printf("I_InitSound: no usable DMA buffer\n");
        return false;
    }
    if (!dsp_reset())
    {
        printf("I_InitSound: no Sound Blaster at 0x%x\n", SB_BASE);
        return false;
    }
    dsp_write(0xE1);
    major = dsp_read();
    minor = dsp_read();
    if (major < 4)
    {
        printf("I_InitSound: DSP version %d.%d, need 4 (SB16)\n", major, minor);
        return false;
    }

    ring = f64_boot->dma_buf;
    f64_sb16_buf = (uint64_t)(uintptr_t)ring;
    memset(ring, 0x80, RING_SIZE);
    wr = 0;

    irq_install();
    dma_start((uint32_t)(uintptr_t)ring, RING_SIZE);

    dsp_write(0x41);                        /* output sample rate */
    dsp_write(OUT_RATE >> 8);
    dsp_write(OUT_RATE & 0xFF);
    dsp_write(0xD1);                        /* speaker on */
    dsp_write(0xC6);                        /* 8-bit, auto-init, FIFO */
    dsp_write(0x20);                        /* stereo, unsigned */
    dsp_write((RING_HALF - 1) & 0xFF);      /* block = half the ring */
    dsp_write((RING_HALF - 1) >> 8);

    sb_ok = 1;
    printf("I_InitSound: Sound Blaster 16 (DSP %d.%d), %d Hz stereo\n",
           major, minor, OUT_RATE);
    return true;
}

static int sb_get_lump(sfxinfo_t *sfx)
{
    char name[9];

    if (sfx->link)
        sfx = sfx->link;
    if (sfx_prefix)
        snprintf(name, sizeof(name), "ds%s", DEH_String(sfx->name));
    else
        snprintf(name, sizeof(name), "%s", DEH_String(sfx->name));
    return W_CheckNumForName(name);
}

/* Read a DMX sound lump once. Returns NULL if it is not a usable sound. */
static const struct sfx *sb_load(sfxinfo_t *info)
{
    struct sfx *s;
    const uint8_t *d;
    uint32_t rate, len;
    int lumplen;

    if (info->driver_data)
        return info->driver_data;
    if (info->lumpnum < 0)
        return NULL;

    d = W_CacheLumpNum(info->lumpnum, PU_STATIC);
    lumplen = W_LumpLength(info->lumpnum);
    if (lumplen < 8 || d[0] != 3 || d[1] != 0)
        return NULL;
    rate = d[2] | (d[3] << 8);
    len = d[4] | (d[5] << 8) | (d[6] << 16) | ((uint32_t)d[7] << 24);
    if (len > (uint32_t)lumplen - 8 || len <= 48 || rate == 0)
        return NULL;

    s = malloc(sizeof(*s));
    if (!s)
        return NULL;
    /* DMX skips 16 bytes of padding at each end of the samples. */
    s->data = d + 8 + 16;
    s->length = len - 32;
    s->step = (uint32_t)(((uint64_t)rate << 16) / OUT_RATE);
    info->driver_data = s;
    return s;
}

static void sb_set_params(int c, int vol, int sep)
{
    if (vol < 0) vol = 0;
    if (vol > 127) vol = 127;
    if (sep < 0) sep = 0;
    if (sep > 254) sep = 254;
    channels[c].lvol = vol * (254 - sep) / 127;
    channels[c].rvol = vol * sep / 127;
}

static void sb_update_params(int c, int vol, int sep)
{
    if (sb_ok && c >= 0 && c < NUM_CHANNELS)
        sb_set_params(c, vol, sep);
}

static int sb_start(sfxinfo_t *info, int c, int vol, int sep)
{
    const struct sfx *s;

    if (!sb_ok || c < 0 || c >= NUM_CHANNELS)
        return -1;
    s = sb_load(info);
    if (!s)
        return -1;
    channels[c].sfx = NULL;
    channels[c].pos = 0;
    sb_set_params(c, vol, sep);
    channels[c].sfx = s;
    return c;
}

static void sb_stop(int c)
{
    if (c >= 0 && c < NUM_CHANNELS)
        channels[c].sfx = NULL;
}

static boolean sb_playing(int c)
{
    return c >= 0 && c < NUM_CHANNELS && channels[c].sfx != NULL;
}

static void sb_update(void)
{
    f64_sound_pump();
}

static snddevice_t sb_devices[] = {
    SNDDEVICE_SB, SNDDEVICE_PAS, SNDDEVICE_GUS,
    SNDDEVICE_WAVEBLASTER, SNDDEVICE_SOUNDCANVAS, SNDDEVICE_AWE32,
};

sound_module_t DG_sound_module = {
    sb_devices,
    sizeof(sb_devices) / sizeof(sb_devices[0]),
    sb_init,
    sb_shutdown,
    sb_get_lump,
    sb_update,
    sb_update_params,
    sb_start,
    sb_stop,
    sb_playing,
    NULL,
};

/* ---- entry points for the platform layer -------------------------------- */

void f64_music_pump(void);
void f64_music_shutdown(void);

void f64_sound_pump(void)
{
    sfx_pump();
    f64_music_pump();
}

void f64_sound_shutdown(void)
{
    sb_shutdown();
    f64_music_shutdown();
}
