# DOOM for f64OS

This directory holds a port of DOOM to f64OS. The port uses
[doomgeneric](https://github.com/ozkl/doomgeneric) (commit `e257a09`).
DOOM runs as a native 64-bit binary. The Forth system loads it from the
f64OS file system and starts it with the `CALL-NATIVE` word.

## Run DOOM

1. Put an IWAD file in `disk_files/doom/`. Use `doom1.wad` (shareware),
   `doom.wad`, `doom2.wad` or `freedoom1.wad`.
2. Build the disk image and start QEMU:
   - Windows: `.\run.ps1`
   - Linux: `make && ./run.sh`
3. At the Forth prompt, type these lines:

   ```
   CD doom
   INCLUDE doom.f
   DOOM
   ```

4. To stop DOOM, select **Quit Game** in the menu and push **Y**. The
   ENDOOM screen comes on. Push a key to go back to the Forth prompt.

QEMU must have 128 MiB of RAM (`-m 128M`). The run scripts set this value.
For sound, QEMU must also have the `sb16` and `adlib` devices. Refer to
[Sound](#sound).

Get Freedoom from <https://freedoom.github.io>. Freedoom has a BSD
license. Do not add WAD files to git. The `.gitignore` file excludes them.

## Controls

| Key | Function |
| --- | --- |
| Up and down arrows, or W and S | Move forward and back |
| Left and right arrows, or mouse left and right | Turn |
| A and D | Strafe left and right |
| Ctrl, or left mouse button | Fire |
| Right mouse button | Strafe (with mouse movement) |
| Middle mouse button | Move forward |
| Space bar | Use (open doors, push switches) |
| Shift | Run |
| Alt | Strafe |
| 1 to 7 | Select weapon |
| Tab | Automap |
| Esc | Menu |

The mouse turns only. It does not move you forward and back. Most players
turn with the mouse and move with the keys. In the QEMU window, click to
give the mouse to the guest. Push **Ctrl+Alt+G** to release it. Use
**Options**, **Mouse sensitivity** in the DOOM menu to change the speed.

## Savegames and configuration

DOOM writes savegames (`doomsav0.dsg` to `doomsav5.dsg`) and its
configuration files (`default.cfg`, `extra.cfg`) to the f64OS file system. The files go into
the directory that you start DOOM from, at the time DOOM saves them. Use
`LS` to see them.

The build makes `os.bin` again from `disk_files/`. Thus, before each
build, `bootfile_extract.py` copies the `.dsg` and `.cfg` files from the
`doom` directory of the previous `os.bin` into `disk_files/doom/`. The new
image then has them. `run.ps1` and the top-level Makefile do this step.

- The disk image is the master copy. A file in the image replaces the
  file with the same name in `disk_files/doom/`.
- Do not delete `os.bin` before a build. If you do, the build cannot
  copy the saves that are not in `disk_files/doom/`.
- The image has 16 MiB of free space for new files. A save that does not
  fit in the sectors of the previous file gets new sectors. The build makes
  the free space new again.
- The `.gitignore` file excludes the `.dsg` and `.cfg` files.

## Sound

DOOM plays sound effects on a Sound Blaster 16 and music on an OPL2 FM
synthesizer (AdLib), as on DOS. The run scripts add these QEMU parameters:

```
-audiodev dsound,id=snd0 -device sb16,audiodev=snd0 -device adlib,audiodev=snd0
```

- `run.ps1` uses the `dsound` audio driver and the SDL window
  (`-display sdl`). On Windows, the default GTK window shows a black screen
  in graphics mode while the `sb16` DMA runs. QEMU makes the frames
  correctly, but the GTK window does not show them. The SDL window shows
  them.
- `run.sh` uses the driver in the `AUDIO` variable. The default is `pa`
  (PulseAudio). Example: `AUDIO=pipewire ./run.sh`.

If QEMU has no `sb16` or no `adlib` device, DOOM runs without sound
effects or without music. Use the DOOM menu (**Options**, **Sound Volume**)
to change the volume.

| Part | Data |
| --- | --- |
| Sound effects | 8-bit stereo at 22050 Hz, up to 16 sounds at the same time, DMA 1, IRQ 5 |
| Music | OPL2 at port 0x388, 9 voices, instruments from the `GENMIDI` lump |
| Music formats | MIDI, and MUS (DOOM IWADs) through `mus2mid` |

The sound effects use a 16 KiB ring buffer at `0xF00000`, because ISA DMA
cannot use memory above 16 MiB. The SB16 gives IRQ 5 after each half of
the ring. A small IRQ handler writes zero-level audio into the finished half.
Thus, when DOOM loads a level, the card plays no sound. It does not play
the previous audio again. DOOM puts back the IRQ 5 vector and the PIC mask when it stops.

## Build requirements

These tools are necessary: GNU make, gcc for x86-64, and GNU binutils
(`ld`, `objcopy`).

- Linux: use the native gcc. The build makes an ELF file and then a flat
  binary. We did not do a test of this path.
- Windows: use MSYS2 gcc. The build makes a PE file and then a flat
  binary. The Makefile changes the gcc include path into a Windows path.
  Thus, Git Bash and PowerShell can start the build.

The command `make -C doom` writes `disk_files/doom/doom.bin`. The top-level
Makefile and `run.ps1` do this step before they make `os.bin`. If the DOOM
build fails, they make `os.bin` without DOOM.

## How the port works

| Part | File | Function |
| --- | --- | --- |
| Loader | `disk_files/doom/doom.f` | Reads `doom.bin` and the IWAD into RAM, fills the boot block, and starts DOOM with `CALL-NATIVE` |
| Entry | `f64/f64_entry.c` | Clears the BSS, starts DOOM, and catches `exit()` |
| Platform | `f64/doomgeneric_f64.c` | VGA mode 13h, PIT at 1000 Hz, keyboard scancodes, ENDOOM |
| Sound effects | `f64/sound_f64.c` | Sound Blaster 16 driver, mixer, IRQ 5 handler |
| Music | `f64/music_f64.c` | MIDI player for the OPL2 with `GENMIDI` instruments |
| Disk files | `f64/disk_f64.c` | ATA PIO and the f64OS directory format, for savegames and configuration files |
| C library | `f64/libc.c`, `f64/include/` | Memory allocator, strings, `printf`, `sscanf`, files in RAM |
| DOOM | `doomgeneric/` | Upstream doomgeneric source (GPL-2.0) |

### Memory map

| Address | Contents |
| --- | --- |
| `0x1000000` to `0x1BFFFFF` | `doom.bin` code, data and BSS |
| `0x1C00000` to `0x1FFFFFF` | DOOM stack (4 MiB) |
| `0x2000000` | IWAD file |
| After the IWAD, to `0x6FFFFFF` | Heap for `malloc` |
| `0xF00000` to `0xF03FFF` | Sound Blaster DMA buffer (16 KiB) |

### Kernel changes

- `kernel.nasm` sets the SSE bits in CR0 and CR4, because the gcc code uses
  SSE instructions. The task switcher does not save XMM0 to XMM15. Thus, only
  the Forth task can use SSE.
- `kernel.nasm` has a kernel service table, version 2. The Forth word
  `KSERVICES` gives its address. Version 2 adds the mouse ring.
- `isr.nasm` writes each raw scancode into a 256-byte ring. DOOM reads key
  press and key release data from this ring.
- `isr.nasm` has an IRQ 12 handler for the PS/2 mouse. It writes each mouse
  byte into a second 256-byte ring. The keyboard handler also sends mouse
  bytes to this ring, because the controller can send them with IRQ 1. The kernel does
  not turn on the mouse. DOOM turns it on when it starts and turns it off
  when it stops.
- `kernel.nasm` unmasks IRQ 2 (cascade) and IRQ 12 at the PIC.
- `isr.nasm` shows the RIP for faults on the screen and sends it to COM1.
  In graphics mode, use `-serial stdio` in QEMU to see these messages.
- `f64_baremetal.nasm` has the new words `KSERVICES` and `CALL-NATIVE`.

`CALL-NATIVE ( arg entry stack-top -- result )` starts native code on a new
stack. It puts `arg` in `rcx` and in `rdi`. Thus, the Microsoft x64 ABI and the
System V ABI get it as the first argument.

## Limits

- DOOM output goes to COM1. Before DOOM sets the graphics mode, the output
  also goes to the text screen.

## License

The `doomgeneric/` directory has the GNU General Public License, version 2.
Refer to `doomgeneric/LICENSE`. The files in `f64/` are new for f64OS.
