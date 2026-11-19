#! /usr/bin/env python
"""Copy DOOM savegames/configs and the 'work' directory tree out of os.bin.

The build makes os.bin again from disk_files/, so files that the OS
wrote into the disk image would otherwise be lost. Run this script
before the build:
  - Copies *.dsg and *.cfg files from the "doom" directory of os.bin
    into disk_files/doom/.
  - Recursively copies all files and subdirectories from the "work"
    directory of os.bin into disk_files/work/.

The disk image is the master copy: a file in the image replaces the file
with the same name in disk_files/.

Disk format (see kernel/f64.f): the root directory is at LBA 128. A
directory is 4 sectors of 64 entries. An entry is a 16-byte name (bit 7
of byte 0 set for a directory), the start LBA and the size (8 bytes each).
"""
import os
import struct
import sys

IMAGE = 'os.bin'
DIR_NAMES = ['doom', 'work']
ROOT_LBA = 128
SUFFIXES = ('.dsg', '.cfg')
SKIP = ('temp.dsg',)


def read_dir(img, lba):
    data = img[lba * 512:(lba + 4) * 512]
    entries = []
    for i in range(64):
        name, start, size = struct.unpack_from('<16sQQ', data, i * 32)
        if not name or name[0] == 0:
            continue
        is_dir = bool(name[0] & 0x80)
        name = bytes([name[0] & 0x7F]) + name[1:]
        entries.append((name.rstrip(b'\0').decode('latin-1'), start, size, is_dir))
    return entries


def extract_dir(img, lba, out_dir, root_name, visited):
    if lba in visited:
        return
    visited.add(lba)
    if (lba + 4) * 512 > len(img):
        return
    os.makedirs(out_dir, exist_ok=True)
    for name, start, size, is_dir in read_dir(img, lba):
        if '/' in name or '\\' in name or name in ('.', '..'):
            continue
        path = os.path.join(out_dir, name)
        if is_dir:
            if root_name != 'doom':
                extract_dir(img, start, path, root_name, visited)
            continue
        low = name.lower()
        if root_name == 'doom' and (not low.endswith(SUFFIXES) or low in SKIP):
            continue
        data = img[start * 512:start * 512 + size]
        if len(data) != size:
            print('bootfile_extract: %s is outside the image, skipped' % path)
            continue
        if os.path.exists(path) and open(path, 'rb').read() == data:
            continue
        open(path, 'wb').write(data)
        print('bootfile_extract: %s (%d bytes)' % (path, size))


def main():
    if not os.path.exists(IMAGE):
        return 0
    img = open(IMAGE, 'rb').read()
    if len(img) < (ROOT_LBA + 4) * 512:
        return 0
    visited = {ROOT_LBA}
    for dir_name in DIR_NAMES:
        dir_info = [e for e in read_dir(img, ROOT_LBA) if e[3] and e[0].lower() == dir_name]
        if not dir_info:
            continue
        out_dir = os.path.join('disk_files', dir_name)
        extract_dir(img, dir_info[0][1], out_dir, dir_name, visited)
    return 0


if __name__ == '__main__':
    sys.exit(main())
