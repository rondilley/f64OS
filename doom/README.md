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

Get Freedoom from <https://freedoom.github.io>. Freedoom has a BSD
license. Do not add WAD files to git. The `.gitignore` file excludes them.

## Controls

| Key | Function |
| --- | --- |
| Up and down arrows, or W and S | Move forward and back |
| Left and right arrows | Turn |
| A and D | Strafe left and right |
| Ctrl | Fire |
| Space bar | Use (open doors, push switches) |
| Shift | Run |
| Alt | Strafe |
| 1 to 7 | Select weapon |
| Tab | Automap |
| Esc | Menu |

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
| C library | `f64/libc.c`, `f64/include/` | Memory allocator, strings, `printf`, `sscanf`, files in RAM |
| DOOM | `doomgeneric/` | Upstream doomgeneric source (GPL-2.0) |

### Memory map

| Address | Contents |
| --- | --- |
| `0x1000000` to `0x1BFFFFF` | `doom.bin` code, data and BSS |
| `0x1C00000` to `0x1FFFFFF` | DOOM stack (4 MiB) |
| `0x2000000` | IWAD file |
| After the IWAD, to `0x6FFFFFF` | Heap for `malloc` |

### Kernel changes

- `kernel.nasm` sets the SSE bits in CR0 and CR4, because the gcc code uses
  SSE instructions. The task switcher does not save XMM0 to XMM15. Thus, only
  the Forth task can use SSE.
- `kernel.nasm` has a kernel service table. The Forth word `KSERVICES`
  gives its address.
- `isr.nasm` writes each raw scancode into a 256-byte ring. DOOM reads key
  press and key release data from this ring.
- `isr.nasm` shows the RIP for faults on the screen and sends it to COM1.
  In graphics mode, use `-serial stdio` in QEMU to see these messages.
- `f64_baremetal.nasm` has the new words `KSERVICES` and `CALL-NATIVE`.

`CALL-NATIVE ( arg entry stack-top -- result )` starts native code on a new
stack. It puts `arg` in `rcx` and in `rdi`. Thus, the Microsoft x64 ABI and the
System V ABI get it as the first argument.

## Limits

- There is no sound and no music.
- There is no mouse.
- Saved games and `default.cfg` are files in RAM. DOOM does not keep them
  after it stops.
- DOOM output goes to COM1. Before DOOM sets the graphics mode, the output
  also goes to the text screen.

## License

The `doomgeneric/` directory has the GNU General Public License, version 2.
Refer to `doomgeneric/LICENSE`. The files in `f64/` are new for f64OS.
