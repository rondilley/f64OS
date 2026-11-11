/*
 * disk_f64.c - read and write files in the f64OS file system (for DOOM
 * savegames and config files).
 *
 * The format is the one that kernel/f64.f uses:
 * - A directory is 4 sectors: 64 entries of 32 bytes. An entry is a
 *   16-byte name (zero-padded, bit 7 of byte 0 set for a directory),
 *   the start LBA (8 bytes) and the size in bytes (8 bytes).
 * - A file is one contiguous run of sectors.
 * - New sectors come from a bump pointer: the root directory (LBA 128)
 *   has a file ".HIGH_LBA" whose first 8 bytes are the next free LBA.
 *
 * The disk is the ATA primary master, in LBA28 PIO mode, as SECTOR@ and
 * SECTOR! use it. Forth does not run while DOOM runs, so there is no
 * other user of the disk.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

#include "f64.h"

#define ATA_DATA     0x1F0
#define ATA_COUNT    0x1F2
#define ATA_LBA0     0x1F3
#define ATA_LBA1     0x1F4
#define ATA_LBA2     0x1F5
#define ATA_DRIVE    0x1F6
#define ATA_STATUS   0x1F7
#define ATA_COMMAND  0x1F7

#define ATA_BSY      0x80
#define ATA_DRQ      0x08
#define ATA_ERR      0x01
#define ATA_DF       0x20

#define ROOT_LBA     128
#define DIR_SECTORS  4
#define DIR_ENTRIES  64
#define NAME_LEN     16

struct f64_dirent {
    char     name[NAME_LEN];
    uint64_t lba;
    uint64_t size;
};

_Static_assert(sizeof(struct f64_dirent) == 32, "directory entry is 32 bytes");

static struct f64_dirent dir[DIR_ENTRIES];
static uint8_t           sector[512] __attribute__((aligned(16)));
static uint32_t          capacity;     /* sectors on the disk; 0 = no disk */
static uint32_t          dir_lba;      /* directory that DOOM was started from */

/* ---- ATA PIO ------------------------------------------------------------ */

static int ata_wait(int want_drq)
{
    int i;

    for (i = 0; i < 1000000; i++)
    {
        uint8_t s = inb(ATA_STATUS);

        if (s & ATA_BSY)
            continue;
        if (s & (ATA_ERR | ATA_DF))
            return 0;
        if (!want_drq || (s & ATA_DRQ))
            return 1;
    }
    return 0;
}

static void ata_select(uint32_t lba)
{
    int i;

    ata_wait(0);
    outb(ATA_DRIVE, 0xE0 | ((lba >> 24) & 0x0F));
    for (i = 0; i < 4; i++)                 /* 400 ns after drive select */
        (void)inb(ATA_STATUS);
    outb(ATA_COUNT, 1);
    outb(ATA_LBA0, lba & 0xFF);
    outb(ATA_LBA1, (lba >> 8) & 0xFF);
    outb(ATA_LBA2, (lba >> 16) & 0xFF);
}

static int ata_read(uint32_t lba, void *buf)
{
    void *p = buf;
    size_t n = 256;

    ata_select(lba);
    outb(ATA_COMMAND, 0x20);                /* READ SECTORS */
    if (!ata_wait(1))
        return 0;
    __asm__ volatile("rep insw" : "+D"(p), "+c"(n) : "d"(ATA_DATA) : "memory");
    return 1;
}

static int ata_write(uint32_t lba, const void *buf)
{
    const void *p = buf;
    size_t n = 256;

    ata_select(lba);
    outb(ATA_COMMAND, 0x30);                /* WRITE SECTORS */
    if (!ata_wait(1))
        return 0;
    __asm__ volatile("rep outsw" : "+S"(p), "+c"(n) : "d"(ATA_DATA) : "memory");
    return ata_wait(0);
}

static void ata_flush(void)
{
    ata_wait(0);
    outb(ATA_COMMAND, 0xE7);                /* FLUSH CACHE */
    ata_wait(0);
}

static uint32_t ata_identify(void)
{
    uint16_t id[256];
    void *p = id;
    size_t n = 256;
    int i;

    ata_wait(0);
    outb(ATA_DRIVE, 0xE0);
    for (i = 0; i < 4; i++)
        (void)inb(ATA_STATUS);
    outb(ATA_COMMAND, 0xEC);                /* IDENTIFY DEVICE */
    if (inb(ATA_STATUS) == 0 || !ata_wait(1))
        return 0;
    __asm__ volatile("rep insw" : "+D"(p), "+c"(n) : "d"(ATA_DATA) : "memory");
    return id[60] | ((uint32_t)id[61] << 16); /* LBA28 sector count */
}

/* ---- directories -------------------------------------------------------- */

static int dir_load(uint32_t lba)
{
    int i;

    for (i = 0; i < DIR_SECTORS; i++)
        if (!ata_read(lba + i, (uint8_t *)dir + 512 * i))
            return 0;
    return 1;
}

/* Write back the directory sector that holds entry e. */
static int dir_store_entry(uint32_t lba, const struct f64_dirent *e)
{
    int s = (int)(e - dir) / (512 / sizeof(*e));

    return ata_write(lba + s, (uint8_t *)dir + 512 * s);
}

static int name_matches(const struct f64_dirent *e, const char *name)
{
    size_t len = strlen(name), elen = 0;
    size_t i;

    while (elen < NAME_LEN && e->name[elen])
        elen++;
    if (elen != len)
        return 0;
    for (i = 0; i < len; i++)
    {
        int c = (uint8_t)e->name[i];

        if (i == 0)
            c &= 0x7F;                      /* directory flag */
        if (toupper(c) != toupper((uint8_t)name[i]))
            return 0;
    }
    return 1;
}

/* Find a file (not a directory) in the loaded directory. */
static struct f64_dirent *dir_find(const char *name)
{
    int i;

    for (i = 0; i < DIR_ENTRIES; i++)
        if (dir[i].name[0] && !(dir[i].name[0] & 0x80) && name_matches(&dir[i], name))
            return &dir[i];
    return NULL;
}

static struct f64_dirent *dir_free(void)
{
    int i;

    for (i = 0; i < DIR_ENTRIES; i++)
        if (!dir[i].name[0])
            return &dir[i];
    return NULL;
}

/* Read the bump pointer. Returns its sector in *sec and value in *high. */
static int high_get(uint32_t *sec, uint64_t *high)
{
    struct f64_dirent *e;

    if (!dir_load(ROOT_LBA))
        return 0;
    e = dir_find(".HIGH_LBA");
    if (!e || !ata_read((uint32_t)e->lba, sector))
        return 0;
    *sec = (uint32_t)e->lba;
    memcpy(high, sector, sizeof(*high));
    return 1;
}

static uint32_t sectors_for(uint64_t size)
{
    return size ? (uint32_t)((size + 511) / 512) : 1;
}

/* ---- interface ---------------------------------------------------------- */

void f64_disk_init(void)
{
    dir_lba = (uint32_t)f64_boot->cwd_lba;
    capacity = dir_lba ? ata_identify() : 0;
    if (capacity)
        printf("f64_disk_init: %u sectors, files in directory LBA %u\n",
               capacity, dir_lba);
    else
        printf("f64_disk_init: no disk, files stay in RAM\n");
}

int f64_disk_usable(const char *name)
{
    return capacity && name[0] && strlen(name) <= NAME_LEN;
}

/* Read file 'name' from the DOOM directory. On success, *data is a new
 * malloc() buffer and the function returns 1. */
int f64_disk_load(const char *name, uint8_t **data, size_t *size)
{
    struct f64_dirent *e;
    uint8_t *buf;
    uint64_t n;
    uint32_t i;

    if (!f64_disk_usable(name) || !dir_load(dir_lba) || !(e = dir_find(name)))
        return 0;
    n = e->size;
    buf = malloc(n ? n : 1);
    if (!buf)
        return 0;
    for (i = 0; i < sectors_for(n) && (uint64_t)i * 512 < n; i++)
    {
        size_t chunk = n - (uint64_t)i * 512 < 512 ? (size_t)(n - (uint64_t)i * 512) : 512;

        if (!ata_read((uint32_t)e->lba + i, sector))
        {
            free(buf);
            return 0;
        }
        memcpy(buf + (size_t)i * 512, sector, chunk);
    }
    *data = buf;
    *size = (size_t)n;
    return 1;
}

/* Write file 'name' to the DOOM directory. If the file exists and the new
 * data fits in its sectors, or the file is the last one on the disk, it
 * stays in place. Otherwise it gets new sectors at the bump pointer.
 * Returns 1 on success. */
int f64_disk_save(const char *name, const uint8_t *data, size_t size)
{
    struct f64_dirent *e;
    uint32_t hsec, lba, sectors, i;
    uint64_t high, new_high;

    if (!f64_disk_usable(name) || !high_get(&hsec, &high) || !dir_load(dir_lba))
        return 0;

    sectors = sectors_for(size);
    new_high = high;
    e = dir_find(name);
    if (e && sectors <= sectors_for(e->size))
        lba = (uint32_t)e->lba;                         /* fits in place */
    else if (e && e->lba + sectors_for(e->size) == high)
    {
        lba = (uint32_t)e->lba;                         /* last file: grow it */
        new_high = lba + sectors;
    }
    else
    {
        if (!e && !(e = dir_free()))
        {
            printf("f64_disk_save: directory full, %s not saved\n", name);
            return 0;
        }
        lba = (uint32_t)high;
        new_high = high + sectors;
    }
    if (new_high > capacity)
    {
        printf("f64_disk_save: disk full, %s not saved\n", name);
        return 0;
    }

    for (i = 0; i < sectors; i++)
    {
        size_t off = (size_t)i * 512;
        size_t chunk = size - off < 512 ? size - off : 512;

        memset(sector, 0, sizeof(sector));
        if (off < size)
            memcpy(sector, data + off, chunk);
        if (!ata_write(lba + i, sector))
            return 0;
    }

    if (new_high != high)
    {
        if (!ata_read(hsec, sector))
            return 0;
        memcpy(sector, &new_high, sizeof(new_high));
        if (!ata_write(hsec, sector))
            return 0;
    }

    memset(e, 0, sizeof(*e));
    memcpy(e->name, name, strlen(name));
    e->lba = lba;
    e->size = size;
    if (!dir_store_entry(dir_lba, e))
        return 0;
    ata_flush();
    printf("f64_disk_save: %s, %u bytes at LBA %u\n", name, (unsigned)size, lba);
    return 1;
}
