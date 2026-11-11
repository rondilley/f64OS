/*
 * music_f64.c - DOOM music on an OPL2 (AdLib) FM chip (f64OS).
 *
 * DOOM IWADs store music as MUS. Freedoom stores it as MIDI. MUS songs
 * go through mus2mid() first, so this file plays only standard MIDI
 * files (format 0 or 1, PPQN timing).
 *
 * The instruments come from the GENMIDI lump in the WAD, the same OPL
 * patches that DOOM used on DOS. The OPL2 has 9 voices.
 *
 * Timing: f64_music_pump() runs the events up to the current time. The
 * platform layer calls it often (every DG_SleepMs loop and every frame).
 *
 * QEMU: -audiodev <driver>,id=snd0 -device adlib,audiodev=snd0
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "f64.h"
#include "doomtype.h"
#include "doomgeneric.h"
#include "i_sound.h"
#include "w_wad.h"
#include "z_zone.h"
#include "memio.h"
#include "mus2mid.h"

#define OPL_ADDR     0x388
#define OPL_DATA     0x389
#define OPL_VOICES   9

#define GENMIDI_INSTRS     175
#define GENMIDI_INSTR_SIZE 36
#define GENMIDI_FIXED      0x01
#define GENMIDI_DOUBLE     0x04

#define MIDI_PERC_CHANNEL  9
#define MAX_TRACKS         64

/* MIDI note frequencies in millihertz, notes 0 to 129. */
static const uint32_t note_mhz[130] = {
    8176, 8662, 9177, 9723, 10301, 10913, 11562, 12250,
    12978, 13750, 14568, 15434, 16352, 17324, 18354, 19445,
    20602, 21827, 23125, 24500, 25957, 27500, 29135, 30868,
    32703, 34648, 36708, 38891, 41203, 43654, 46249, 48999,
    51913, 55000, 58270, 61735, 65406, 69296, 73416, 77782,
    82407, 87307, 92499, 97999, 103826, 110000, 116541, 123471,
    130813, 138591, 146832, 155563, 164814, 174614, 184997, 195998,
    207652, 220000, 233082, 246942, 261626, 277183, 293665, 311127,
    329628, 349228, 369994, 391995, 415305, 440000, 466164, 493883,
    523251, 554365, 587330, 622254, 659255, 698456, 739989, 783991,
    830609, 880000, 932328, 987767, 1046502, 1108731, 1174659, 1244508,
    1318510, 1396913, 1479978, 1567982, 1661219, 1760000, 1864655, 1975533,
    2093005, 2217461, 2349318, 2489016, 2637020, 2793826, 2959955, 3135963,
    3322438, 3520000, 3729310, 3951066, 4186009, 4434922, 4698636, 4978032,
    5274041, 5587652, 5919911, 6271927, 6644875, 7040000, 7458620, 7902133,
    8372018, 8869844, 9397273, 9956063, 10548082, 11175303, 11839822, 12543854,
    13289750, 14080000,
};

/* Operator offset of the modulator for each voice. Carrier = +3. */
static const uint8_t op_mod[OPL_VOICES] = { 0x00, 0x01, 0x02, 0x08, 0x09, 0x0A, 0x10, 0x11, 0x12 };

struct voice {
    int            used;
    int            chan;       /* MIDI channel */
    int            key;        /* MIDI key that started it */
    int            note;       /* note played, after the instrument offset */
    int            velocity;
    const uint8_t *patch;      /* 16-byte GENMIDI voice data loaded */
    uint8_t        reg_b0;     /* last value of register 0xB0 */
    uint32_t       age;
};

struct midi_chan {
    int instr;
    int volume;
    int bend;                  /* -8192 to 8191 */
};

struct track {
    const uint8_t *p, *start, *end;
    uint32_t       next_tick;
    uint8_t        running;
    int            done;
};

struct song {
    uint8_t     *data;
    size_t       len;
    int          ntracks;
    int          division;
    struct track tracks[MAX_TRACKS];
};

static int              opl_ok;
static const uint8_t   *genmidi;      /* first instrument */
static struct voice     voices[OPL_VOICES];
static struct midi_chan chans[16];
static uint32_t         voice_age;
static int              music_volume = 100;

static struct song     *song;         /* song that plays */
static int              playing, paused, looping;
static uint32_t         tempo;        /* microseconds per quarter note */
static uint32_t         cur_tick;
static uint64_t         cur_us, pos_us;
static uint32_t         last_ms;

/* ---- OPL --------------------------------------------------------------- */

static void opl_write(int reg, int val)
{
    int i;

    outb(OPL_ADDR, reg);
    for (i = 0; i < 6; i++)
        (void)inb(OPL_ADDR);
    outb(OPL_DATA, val);
    for (i = 0; i < 35; i++)
        (void)inb(OPL_ADDR);
}

static int opl_detect(void)
{
    uint8_t s1, s2;
    uint32_t t;

    opl_write(0x04, 0x60);
    opl_write(0x04, 0x80);
    s1 = inb(OPL_ADDR);
    opl_write(0x02, 0xFF);
    opl_write(0x04, 0x21);
    t = DG_GetTicksMs();
    while (DG_GetTicksMs() - t < 2)
        f64_hlt();
    s2 = inb(OPL_ADDR);
    opl_write(0x04, 0x60);
    opl_write(0x04, 0x80);
    return (s1 & 0xE0) == 0x00 && (s2 & 0xE0) == 0xC0;
}

/* Put the OPL in a silent state. First stop all notes with the fastest
 * release and full attenuation. Then clear the other registers. If the
 * envelopes do not finish first, a zero release rate keeps them on, and
 * zero frequency gives a fixed output level (a DC offset and a click). */
static void opl_reset(void)
{
    uint32_t t;
    int r, v;

    for (v = 0; v < OPL_VOICES; v++)
    {
        int mod = op_mod[v], car = mod + 3;

        opl_write(0x40 + mod, 0x3F);
        opl_write(0x40 + car, 0x3F);
        opl_write(0x80 + mod, 0xFF);        /* lowest sustain, fastest release */
        opl_write(0x80 + car, 0xFF);
        opl_write(0xB0 + v, voices[v].reg_b0 & ~0x20);
    }
    t = DG_GetTicksMs();
    while (DG_GetTicksMs() - t < 10)
        f64_hlt();

    for (r = 0x01; r <= 0xF5; r++)
        opl_write(r, (r >= 0x40 && r <= 0x55) ? 0x3F : 0);
    opl_write(0x01, 0x20);                  /* allow waveform select */
    for (v = 0; v < OPL_VOICES; v++)
    {
        voices[v].patch = NULL;
        voices[v].reg_b0 = 0;
    }
}

/* ---- voices ------------------------------------------------------------ */

static int scale_volume(int v)
{
    /* MIDI volume to OPL output, louder in the middle than linear. */
    if (v < 0) v = 0;
    if (v > 127) v = 127;
    return 127 - ((127 - v) * (127 - v)) / 127;
}

/* OPL attenuation (0.75 dB steps) for a patch level at volume vol.
 * MUSIC_HEADROOM gives 3 dB of headroom: with 9 voices at full volume,
 * the QEMU AdLib output clips without it. */
#define MUSIC_HEADROOM 4

static int attenuate(int level, int vol)
{
    int att = 0x3F - ((0x3F - (level & 0x3F)) * vol) / 127 + MUSIC_HEADROOM;

    return att > 0x3F ? 0x3F : att;
}

static void voice_load(int v, const uint8_t *patch)
{
    int mod = op_mod[v], car = mod + 3;

    if (voices[v].patch == patch)
        return;
    opl_write(0x20 + mod, patch[0]);
    opl_write(0x60 + mod, patch[1]);
    opl_write(0x80 + mod, patch[2]);
    opl_write(0xE0 + mod, patch[3]);
    opl_write(0x20 + car, patch[7]);
    opl_write(0x60 + car, patch[8]);
    opl_write(0x80 + car, patch[9]);
    opl_write(0xE0 + car, patch[10]);
    opl_write(0xC0 + v, patch[6] | 0x30);   /* 0x30: both outputs on OPL3 */
    voices[v].patch = patch;
}

static void voice_volume(int v)
{
    struct voice *vo = &voices[v];
    const uint8_t *p = vo->patch;
    int mod = op_mod[v], car = mod + 3;
    int vol;

    vol = vo->velocity * chans[vo->chan].volume / 127;
    vol = scale_volume(vol * music_volume / 127);

    opl_write(0x40 + car, (p[11] & 0xC0) | attenuate(p[12], vol));
    if (p[6] & 0x01)                        /* additive: modulator is heard */
        opl_write(0x40 + mod, (p[4] & 0xC0) | attenuate(p[5], vol));
    else
        opl_write(0x40 + mod, (p[4] & 0xC0) | (p[5] & 0x3F));
}

static void voice_freq(int v, int keyon)
{
    struct voice *vo = &voices[v];
    int pos, idx, frac, block;
    uint32_t f, fnum = 1023;

    pos = vo->note * 256;
    if (vo->chan != MIDI_PERC_CHANNEL)
        pos += chans[vo->chan].bend / 16;   /* bend range: 2 semitones */
    if (pos < 0) pos = 0;
    if (pos > 128 * 256) pos = 128 * 256;
    idx = pos >> 8;
    frac = pos & 0xFF;
    f = note_mhz[idx] + (uint32_t)((note_mhz[idx + 1] - note_mhz[idx]) * frac / 256);

    for (block = 0; block < 8; block++)
    {
        fnum = (uint32_t)(((uint64_t)f << (20 - block)) / 49716000u);
        if (fnum < 1024)
            break;
    }
    if (block > 7) { block = 7; fnum = 1023; }

    vo->reg_b0 = (keyon ? 0x20 : 0) | (block << 2) | (fnum >> 8);
    opl_write(0xA0 + v, fnum & 0xFF);
    opl_write(0xB0 + v, vo->reg_b0);
}

static void voice_off(int v)
{
    voices[v].reg_b0 &= ~0x20;
    opl_write(0xB0 + v, voices[v].reg_b0);
    voices[v].used = 0;
}

static int voice_alloc(int steal)
{
    int v, best = -1;

    for (v = 0; v < OPL_VOICES; v++)
        if (!voices[v].used)
            return v;
    if (!steal)
        return -1;
    for (v = 0; v < OPL_VOICES; v++)
        if (best < 0 || voices[v].age < voices[best].age)
            best = v;
    voice_off(best);
    return best;
}

static void all_notes_off(int chan)
{
    int v;

    for (v = 0; v < OPL_VOICES; v++)
        if (voices[v].used && (chan < 0 || voices[v].chan == chan))
            voice_off(v);
}

static void note_off(int chan, int key)
{
    int v;

    for (v = 0; v < OPL_VOICES; v++)
        if (voices[v].used && voices[v].chan == chan && voices[v].key == key)
            voice_off(v);
}

static void note_on(int chan, int key, int velocity)
{
    const uint8_t *instr;
    int flags, nvoices, i;

    if (velocity == 0)
    {
        note_off(chan, key);
        return;
    }
    if (chan == MIDI_PERC_CHANNEL)
    {
        if (key < 35 || key > 81)
            return;
        instr = genmidi + (128 + key - 35) * GENMIDI_INSTR_SIZE;
    }
    else
        instr = genmidi + chans[chan].instr * GENMIDI_INSTR_SIZE;

    flags = instr[0] | (instr[1] << 8);
    nvoices = (flags & GENMIDI_DOUBLE) ? 2 : 1;

    for (i = 0; i < nvoices; i++)
    {
        const uint8_t *patch = instr + 4 + 16 * i;
        int offset = (int16_t)(patch[14] | (patch[15] << 8));
        int v = voice_alloc(i == 0);
        int note;

        if (v < 0)
            break;
        note = (flags & GENMIDI_FIXED) ? instr[3] : key;
        note += offset;
        while (note < 0) note += 12;
        while (note > 127) note -= 12;

        voice_load(v, patch);
        voices[v].used = 1;
        voices[v].chan = chan;
        voices[v].key = key;
        voices[v].note = note;
        voices[v].velocity = velocity;
        voices[v].age = ++voice_age;
        voice_volume(v);
        voice_freq(v, 1);
    }
}

static void controller(int chan, int ctrl, int val)
{
    int v;

    switch (ctrl)
    {
    case 7:                                 /* channel volume */
        chans[chan].volume = val;
        for (v = 0; v < OPL_VOICES; v++)
            if (voices[v].used && voices[v].chan == chan)
                voice_volume(v);
        break;
    case 0x78:                              /* all sound off */
    case 0x7B:                              /* all notes off */
        all_notes_off(chan);
        break;
    case 0x79:                              /* reset controllers */
        chans[chan].volume = 100;
        chans[chan].bend = 0;
        break;
    default:
        break;
    }
}

static void pitch_bend(int chan, int bend)
{
    int v;

    chans[chan].bend = bend;
    for (v = 0; v < OPL_VOICES; v++)
        if (voices[v].used && voices[v].chan == chan)
            voice_freq(v, 1);
}

static void reset_channels(void)
{
    int c;

    for (c = 0; c < 16; c++)
    {
        chans[c].instr = 0;
        chans[c].volume = 100;
        chans[c].bend = 0;
    }
}

/* ---- MIDI file --------------------------------------------------------- */

static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
static uint32_t be16(const uint8_t *p) { return (p[0] << 8) | p[1]; }

static uint32_t read_varlen(struct track *t)
{
    uint32_t v = 0;
    int i;

    for (i = 0; i < 4 && t->p < t->end; i++)
    {
        uint8_t b = *t->p++;
        v = (v << 7) | (b & 0x7F);
        if (!(b & 0x80))
            break;
    }
    return v;
}

static void track_rewind(struct track *t)
{
    t->p = t->start;
    t->running = 0;
    t->done = t->p >= t->end;
    t->next_tick = t->done ? 0 : read_varlen(t);
}

static void song_rewind(struct song *s)
{
    int i;

    for (i = 0; i < s->ntracks; i++)
        track_rewind(&s->tracks[i]);
    tempo = 500000;
    cur_tick = 0;
    cur_us = pos_us;
}

/* Process one event of track t. */
static void track_event(struct track *t)
{
    uint8_t status, d1, d2;

    if (t->p >= t->end)
    {
        t->done = 1;
        return;
    }
    if (*t->p & 0x80)
    {
        status = *t->p++;
        if (status < 0xF0)
            t->running = status;
    }
    else
        status = t->running;

    switch (status >> 4)
    {
    case 0x8:
        if (t->end - t->p < 2) { t->done = 1; return; }
        d1 = *t->p++; d2 = *t->p++;
        note_off(status & 0x0F, d1);
        break;
    case 0x9:
        if (t->end - t->p < 2) { t->done = 1; return; }
        d1 = *t->p++; d2 = *t->p++;
        note_on(status & 0x0F, d1, d2);
        break;
    case 0xA:
        t->p += 2;
        break;
    case 0xB:
        if (t->end - t->p < 2) { t->done = 1; return; }
        d1 = *t->p++; d2 = *t->p++;
        controller(status & 0x0F, d1, d2);
        break;
    case 0xC:
        if (t->p >= t->end) { t->done = 1; return; }
        chans[status & 0x0F].instr = *t->p++ & 0x7F;
        break;
    case 0xD:
        t->p += 1;
        break;
    case 0xE:
        if (t->end - t->p < 2) { t->done = 1; return; }
        d1 = *t->p++; d2 = *t->p++;
        pitch_bend(status & 0x0F, ((d2 << 7) | d1) - 8192);
        break;
    case 0xF:
        if (status == 0xFF)
        {
            uint8_t type;
            uint32_t len;

            if (t->p >= t->end) { t->done = 1; return; }
            type = *t->p++;
            len = read_varlen(t);
            if (type == 0x51 && len == 3 && t->end - t->p >= 3)
                tempo = (t->p[0] << 16) | (t->p[1] << 8) | t->p[2];
            if (type == 0x2F)
            {
                t->done = 1;
                return;
            }
            t->p += len;
        }
        else if (status == 0xF0 || status == 0xF7)
            t->p += read_varlen(t);
        else
            t->done = 1;                    /* unknown: stop this track */
        break;
    default:
        t->done = 1;                        /* data byte with no status */
        return;
    }

    if (t->p >= t->end)
        t->done = 1;
    if (!t->done)
        t->next_tick += read_varlen(t);
}

static struct song *song_parse(uint8_t *data, size_t len)
{
    struct song *s;
    size_t off;

    if (len < 14 || memcmp(data, "MThd", 4) || be32(data + 4) < 6)
        return NULL;
    if (be16(data + 12) & 0x8000)           /* SMPTE timing: not supported */
        return NULL;

    s = calloc(1, sizeof(*s));
    if (!s)
        return NULL;
    s->data = data;
    s->len = len;
    s->division = be16(data + 12);
    if (s->division == 0)
        s->division = 96;

    off = 8 + be32(data + 4);
    while (off + 8 <= len && s->ntracks < MAX_TRACKS)
    {
        uint32_t clen = be32(data + off + 4);

        if (off + 8 + clen > len)
            clen = len - off - 8;
        if (!memcmp(data + off, "MTrk", 4))
        {
            s->tracks[s->ntracks].start = data + off + 8;
            s->tracks[s->ntracks].end = data + off + 8 + clen;
            s->ntracks++;
        }
        off += 8 + clen;
    }
    if (s->ntracks == 0)
    {
        free(s);
        return NULL;
    }
    return s;
}

/* ---- pump -------------------------------------------------------------- */

void f64_music_pump(void)
{
    uint32_t now;
    int restarts = 0;

    if (!opl_ok)
        return;
    now = DG_GetTicksMs();
    if (!playing || paused)
    {
        last_ms = now;
        return;
    }
    pos_us += (uint64_t)(now - last_ms) * 1000;
    last_ms = now;

    for (;;)
    {
        struct track *next = NULL;
        uint64_t ev_us;
        int i;

        for (i = 0; i < song->ntracks; i++)
        {
            struct track *t = &song->tracks[i];
            if (!t->done && (!next || t->next_tick < next->next_tick))
                next = t;
        }
        if (!next)
        {
            all_notes_off(-1);
            if (!looping || restarts++)
            {
                playing = looping;          /* wait for the next pump */
                if (looping)
                    song_rewind(song);
                return;
            }
            reset_channels();
            song_rewind(song);
            continue;
        }

        ev_us = cur_us + (uint64_t)(next->next_tick - cur_tick) * tempo / song->division;
        if (ev_us > pos_us)
            break;
        cur_us = ev_us;
        cur_tick = next->next_tick;
        track_event(next);
    }
}

/* ---- DOOM music module ------------------------------------------------- */

static boolean mus_init(void)
{
    int lump;

    if (opl_ok)
        return true;
    if (!opl_detect())
    {
        printf("I_InitMusic: no OPL2 (AdLib) at 0x%x\n", OPL_ADDR);
        return false;
    }
    lump = W_CheckNumForName("GENMIDI");
    if (lump < 0 || W_LumpLength(lump) < 8 + GENMIDI_INSTRS * GENMIDI_INSTR_SIZE)
    {
        printf("I_InitMusic: no GENMIDI lump\n");
        return false;
    }
    genmidi = W_CacheLumpNum(lump, PU_STATIC);
    if (memcmp(genmidi, "#OPL_II#", 8))
    {
        printf("I_InitMusic: bad GENMIDI lump\n");
        return false;
    }
    genmidi += 8;

    opl_reset();
    memset(voices, 0, sizeof(voices));
    reset_channels();
    opl_ok = 1;
    printf("I_InitMusic: OPL2 FM music\n");
    return true;
}

static void mus_shutdown(void)
{
    if (!opl_ok)
        return;
    all_notes_off(-1);
    opl_reset();
    playing = 0;
    opl_ok = 0;
}

static void mus_set_volume(int volume)
{
    int v;

    music_volume = volume;
    if (!opl_ok)
        return;
    for (v = 0; v < OPL_VOICES; v++)
        if (voices[v].used)
            voice_volume(v);
}

static void mus_pause(void)
{
    paused = 1;
    if (opl_ok)
        all_notes_off(-1);
}

static void mus_resume(void)
{
    paused = 0;
    last_ms = DG_GetTicksMs();
}

static void *mus_register(void *data, int len)
{
    uint8_t *buf;
    size_t blen;
    struct song *s;

    if (!opl_ok || len < 4)
        return NULL;

    if (!memcmp(data, "MUS\x1a", 4))
    {
        MEMFILE *in = mem_fopen_read(data, len);
        MEMFILE *out = mem_fopen_write();
        void *mid;

        if (mus2mid(in, out))
        {
            mem_fclose(in);
            mem_fclose(out);
            return NULL;
        }
        mem_get_buf(out, &mid, &blen);
        buf = malloc(blen);
        if (buf)
            memcpy(buf, mid, blen);
        mem_fclose(in);
        mem_fclose(out);
    }
    else
    {
        blen = len;
        buf = malloc(blen);
        if (buf)
            memcpy(buf, data, blen);
    }
    if (!buf)
        return NULL;

    s = song_parse(buf, blen);
    if (!s)
        free(buf);
    return s;
}

static void mus_unregister(void *handle)
{
    struct song *s = handle;

    if (!s)
        return;
    if (s == song)
    {
        all_notes_off(-1);
        playing = 0;
        song = NULL;
    }
    free(s->data);
    free(s);
}

static void mus_play(void *handle, boolean loop)
{
    if (!opl_ok || !handle)
        return;
    all_notes_off(-1);
    reset_channels();
    song = handle;
    looping = loop;
    pos_us = 0;
    song_rewind(song);
    last_ms = DG_GetTicksMs();
    playing = 1;
    paused = 0;
}

static void mus_stop(void)
{
    playing = 0;
    if (opl_ok)
        all_notes_off(-1);
}

static boolean mus_is_playing(void)
{
    return playing;
}

static void mus_poll(void)
{
    f64_music_pump();
}

void f64_music_shutdown(void)
{
    mus_shutdown();
}

static snddevice_t mus_devices[] = {
    SNDDEVICE_ADLIB, SNDDEVICE_SB, SNDDEVICE_PAS, SNDDEVICE_GUS,
    SNDDEVICE_WAVEBLASTER, SNDDEVICE_SOUNDCANVAS, SNDDEVICE_GENMIDI,
    SNDDEVICE_AWE32,
};

music_module_t DG_music_module = {
    mus_devices,
    sizeof(mus_devices) / sizeof(mus_devices[0]),
    mus_init,
    mus_shutdown,
    mus_set_volume,
    mus_pause,
    mus_resume,
    mus_register,
    mus_unregister,
    mus_play,
    mus_stop,
    mus_is_playing,
    mus_poll,
};
