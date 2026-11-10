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
* Forth is implemented with a minimal set of bootstrapping words in x64 assembly. The remainder of the language is written in Forth itself.
* You can edit any files and easily rebuild the os.bin filesystem.
* You can edit the editor (edit.f) inside itself and redeploy immediately to see your changes.
