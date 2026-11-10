#! /usr/bin/env python
import os
from struct import pack

input_filename = 'os.bin'
dirs = []
files = []
id = 0
de_info = []

def walk_dfs(path: str, parent_id: int = 0) -> None:
    """Depth-first recursive traversal rooted at path."""
    global id, dirs, files
    for name in sorted(os.listdir(path)):
        child = os.path.join(path, name)
        if os.path.isdir(child) and not os.path.islink(child):
            id += 1
            dirs.append([os.path.basename(child), parent_id, id])
            walk_dfs(child, id)
        else:
            files.append([os.path.basename(child), parent_id, child])

walk_dfs("disk_files")

def create_dir_entry(f, d, maxlba):
    c = 0
    for e in d[3]:
        b = bytearray(e[0], 'utf-8')
        if e[5] != 0:
            b[0] = b[0] | 0x80
        de = pack('16sQQ', b, e[3], e[1])
        f.write(de)
        c = c + 1
    while c < 64:
        de = b'\0' * 32
        f.write(de)
        c =c + 1
    # we've created the directory entry
    for e in d[3]:
        # this is a file, need to create it
        if e[5] == 0:
            if e[6] == 'FOO':
                tfe = pack('Q', maxlba)
                fe = pack('512s', tfe)
            else:
                with open(e[6], 'rb') as fsfile:
                    data = fsfile.read()
                    fe = pack('%is' % (512 * e[2]), data)
            f.write(fe)


with open(input_filename, 'r+b') as infile:
    length = len(infile.read())
    assert length <= 65536, f"os.bin ({length} bytes) exceeds 64 KiB!"
    infile.write(b'\0'*(65536 - length))
    i = 0
    lba = 128

    while i <= id:
        print('Creating Directory Entry %i (%i - %i)' % (i, lba, lba + 3))
        d_low = lba
        d_high = lba + 3
        lba += 4
        name = ''
        if i > 0:
            for d in dirs:
                if d[2] == i:
                    name = d[0]
        de = []
        if i > 0:
            for d in dirs:
                if d[2] == i:
                    name = d[0]
                    parent_id = d[1]
                    # Add '..' pointing back to parent directory (e[5] = -1 so line 29 marks it as a dir)
                    de.append(['..', 2048, 4, de_info[parent_id][1], de_info[parent_id][2], -1, ''])
        for f in files:
            if f[1] == i:
                size = os.path.getsize(f[2])
                sectors = int(size / 512)
                if size % 512:
                    sectors += 1
                print('FILE:%s - Size: %i / %i (%i - %i)' % (f[0], size, sectors, lba, lba + (sectors - 1)))
                de.append([f[0], size, sectors, lba, lba + (sectors - 1), 0, f[2]])
                lba += sectors
        for d in dirs:
            if d[1] == i:
                print('DIR:%s (%i)' % (d[0], d[2]))
                de.append([d[0], 2048, 4, 0, 0, d[2], ''])
        if i == 0:
            print('FILE:.HIGH_LBA - Size: 8 / 1 (%i - %i)' % (lba, lba))
            de.append(['.HIGH_LBA', 8, 1, lba, lba, 0, 'FOO'])
            lba += 1
        de_info.append([name, d_low, d_high, de])
        print()
        i += 1
    for d in de_info:
        for e in d[3]:
            if e[5] > 0:
                e[3] = de_info[e[5]][1]
                e[4] = de_info[e[5]][2]
    c = 0
    for d in de_info:
        # print("Creating directory entry %i..." % (c))
        # print(d)
        create_dir_entry(infile, d, lba)
        c += 1
    # Pad image with 256 free sectors (128 KiB) for creating new files/dirs in Forth
    infile.write(b'\0' * (256 * 512))