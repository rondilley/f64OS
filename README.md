# f64OS
A 64-bit, bootable, preemptively multitasking kernel that loads and runs my 64-bit Forth implementation on a VGA console.
<center>
<kbd>
<img src="https://github.com/tliston/f64OS/blob/main/images/f64OS.png" border=3 bordercolor="white">
<br>Computing up to the 90th Fibonacci number.
</kbd>
</center>

## Overview
* Runs under QEMU.
* Preemptively multitasking (w/Yield_task to allow for smoother operation...).
* Status bar (implemented as a second task) shows stack depth and clock ticks.
* Provides a minimal filesystem with directories and subdirectories.
  * LS / CD / MKDIR/ RM / CREATE-FILE / INCLUDE.
* Has a minimal screen-based text editor, written in Forth (edit.f), with the ability to drop back to the Forth interpreter to test code.
* The text editor now keeps track of indentation level (TAB) and saves the current file with the HOME key.
* Forth is implemented with a minimal set of bootstrapping words in x64 assembly. The remainder of the language is written in Forth itself.
* You can edit any of the files and easily rebuild the os.bin filesystem.
* You can edit the editor (edit.f) inside itself and redeploy immediately to see your changes.
* Runs DOOM as a native 64-bit binary, loaded from the filesystem by Forth. See [doom/README.md](doom/README.md).
* Includes a Forth-based 64-bit x86-64 assembler (`asm.f`), loadable via `INCLUDE`, capable of assembling inline native words or standalone flat binaries executed via `CALL-NATIVE`.
* Includes f64 BASIC V2, a Commodore 64 BASIC V2 interpreter written in Forth, with a C64 screen in VGA mode 13h. It runs the Thatcher program (`thatcher_c64.txt`). See [BASIC.md](BASIC.md).
