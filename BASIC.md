# f64 BASIC V2

f64 BASIC V2 is a Commodore 64 BASIC V2 interpreter for f64OS. The source code is Forth. It runs native on f64OS, with a small number of machine-code words for floating-point arithmetic.

The interpreter shows a 40 x 25 character screen in VGA mode 13h (320 x 200 pixels), the same size as the C64 screen. It has the 16 C64 colours, the two C64 character sets, and a C64 screen editor.

## 1. Start BASIC

QEMU must have 128 MiB of RAM (`-m 128M`). The run scripts set this value.

At the Forth prompt, type these lines:

```forth
CD basic
INCLUDE basic.f
BASIC
```

The BASIC screen comes on. To run the Thatcher program, type these lines:

```basic
LOAD "THATCHER.BAS"
RUN
```

Push **Esc** (RUN/STOP) to stop the program. The text on the screen uses the new character set of the program. Type `SYS 64738` to reset BASIC.

To go back to Forth, type `BYE`. The program and the variables stay in memory. Type `BASIC` to go back to BASIC. Type `BASIC-UNLOAD` to remove all BASIC words from the Forth dictionary.

## 2. Keyboard

| PC key | C64 key |
| --- | --- |
| Letters | Unshifted letters (upper case in the default character set) |
| Shift + letter | Shifted letters (graphics characters in the default character set) |
| Enter | RETURN |
| Backspace | INST/DEL (delete) |
| Page Down | INST (insert) |
| Home | CLR/HOME (home) |
| Page Up | CLR (clear the screen) |
| Arrow keys | Cursor keys |
| Esc | RUN/STOP |
| `~` | π |
| `\` | £ |
| `^` | ↑ |
| `_` | ← |

Type keywords without Shift, as on a C64. Shift + letter gives a graphics character.

The screen editor is the C64 screen editor. Move the cursor to a line on the screen, change the line, and push Enter. BASIC reads the full logical line (up to 80 characters) from the screen. Quote mode and reverse mode operate as on a C64.

## 3. Language

The interpreter has all the BASIC V2 statements, functions and operators.

| Group | Words |
| --- | --- |
| Statements | `CLR CMD CLOSE CONT DATA DEF DIM END FOR GET GET# GOSUB GOTO GO TO IF INPUT INPUT# LET LIST LOAD NEW NEXT ON OPEN POKE PRINT PRINT# READ REM RESTORE RETURN RUN SAVE STOP SYS VERIFY WAIT` |
| Numeric functions | `ABS ATN COS EXP FN FRE INT LOG PEEK POS RND SGN SIN SQR TAN USR` |
| String functions | `ASC CHR$ LEFT$ LEN MID$ RIGHT$ STR$ VAL` |
| Print functions | `SPC( TAB(` |
| Operators | `+ - * / ^ = < > <= >= <> AND OR NOT` |
| Special variables | `TI TI$ ST`, and the constant π |

The interpreter uses the C64 rules:

- BASIC uses only the first two characters of a variable name. `$` gives a string variable and `%` gives an integer variable.
- An array that you do not DIM gets the indexes 0 to 10.
- Strings have a maximum length of 255 characters.
- Integers have the range -32768 to 32767.
- Numbers print with 9 digits, as on a C64. The interpreter uses 64-bit floating-point numbers, thus the precision is better than on a C64. The range is the C64 range (±1.70141183E+38).
- The tokenizer is the C64 tokenizer. It finds keywords in variable names (`TOTAL` becomes `TO TAL`).
- Error messages have the C64 text, for example `?SYNTAX  ERROR IN 10`.
- `FRE(0)` gives a negative number when the free memory is more than 32767 bytes.

The program is in the emulated C64 memory, in the C64 format, at $0801. The maximum size of a program is approximately 38 KiB.

## 4. C64 memory and hardware

BASIC has a 64 KiB C64 memory. `PEEK` and `POKE` use this memory. These addresses operate as on a C64:

| Address | Function |
| --- | --- |
| 1024-2023 | Screen memory. A `POKE` shows the character immediately. |
| 55296-56295 | Colour memory |
| 53280, 53281 | Border colour and background colour |
| 53272 | Screen and character set addresses. The value 12 in bits 1 to 3 selects a character set in RAM at 12288. |
| 56576 | VIC bank |
| 648 | Screen page for the screen editor |
| 646 | Text colour |
| 211, 214 | Cursor column and cursor row |
| 198, 631-640 | Keyboard buffer |
| 160-162 | Jiffy clock (`TI`) |
| 1 | Processor port. If bit 2 is 0, 53248-57343 shows the character generator. |
| 54299 | Random numbers |

`SYS 64738` resets BASIC. `SYS 58692` clears the screen. `SYS 65490` writes the character in address 780 to the screen. Other `SYS` addresses have no effect.

These parts of the C64 are not in the emulation:

- Bitmap mode, multicolour mode, extended colour mode and sprites
- Sound (the SID registers keep their values, but there is no sound)
- 6502 machine code (`USR` gives `?ILLEGAL QUANTITY  ERROR`)
- The keyboard matrix (`PEEK(197)` always gives 64) and the joysticks

The character generator is not the C64 character ROM. The letters, the digits and the punctuation come from the 8 x 8 font of the VGA BIOS. The graphics characters are new designs.

## 5. Files and devices

| Device | Function |
| --- | --- |
| 0 | Keyboard |
| 1, 8, 9, 10, 11 | Files in the current f64OS directory |
| 3 | Screen |
| 4 | Printer. The output goes to the serial port COM1. |

`LOAD` and `SAVE` use the current f64OS directory. `CD` to a directory before you start BASIC.

- `SAVE "NAME"` writes the program as a text file (a listing). Unshifted letters become upper-case letters. Control characters in strings become names in braces, for example `{CLR}` and `{RED}`.
- `LOAD "NAME"` reads a text file or a C64 PRG file. In a text file, the case with more letters is the unshifted case. Thus SAVE files and petcat files load correctly. `LOAD "NAME",8,1` loads a PRG file to the address in the file.
- `LOAD "$"` loads the directory as a program. Type `LIST` to see it.
- `VERIFY "NAME"` compares the program with the file.
- A `LOAD` in a program that runs loads the new program and runs it from the start. The variables stay.

`OPEN` gives sequential files:

```basic
10 OPEN 2,8,2,"DATA.SEQ,S,W"
20 PRINT#2,"HELLO"
30 CLOSE 2
40 OPEN 2,8,2,"DATA.SEQ,S,R"
50 INPUT#2,A$:PRINT A$,ST
60 CLOSE 2
```

- Secondary address 0 reads and secondary address 1 writes. For other secondary addresses, the mode in the name (`R`, `W` or `A`) selects the operation.
- `ST` is 64 after the last byte of a file.
- The command channel (secondary address 15) accepts `S:NAME` (delete a file) and `R:NEW=OLD` (rename a file).
- A file opened to write goes to the disk when you close it. `CLR`, `RUN` and `NEW` close all files and do not write them, as on a C64.

## 6. Files of the interpreter

The files load in a chain. Each file loads the next file with `INCLUDE` on its last line. The kernel can load a file of 32 KiB or less with `INCLUDE`, thus the interpreter has more than one file.

| File | Contents |
| --- | --- |
| `disk_files/basic/basic.f` | Loader, `CODE` and `M,`, memory map, error numbers |
| `disk_files/basic/bnative.f` | Machine-code words. `basic/gen_native.py` makes this file. |
| `disk_files/basic/bfloat.f` | Number parser and number printer |
| `disk_files/basic/bscreen.f` | VGA mode 13h, character generator, screen, keyboard, screen editor |
| `disk_files/basic/btoken.f` | Keywords, tokenizer, program lines, `LIST` |
| `disk_files/basic/beval.f` | Variables, arrays, strings, `PEEK`, `POKE`, expressions |
| `disk_files/basic/bio.f` | Devices, channels, `LOAD`, `SAVE`, `VERIFY` |
| `disk_files/basic/bstmt.f` | Statements and the run loop |
| `disk_files/basic/bmain.f` | Error messages, the READY loop, `BASIC` |
| `disk_files/basic/thatcher.bas` | The Thatcher program (a copy of `thatcher_c64.txt`) |

To change a machine-code word, edit `basic/gen_native.py`. Then run this command from the root of the repository. NASM is necessary.

```
python basic/gen_native.py
```

### 6.1 Memory map

BASIC uses RAM from 64 MiB to 81 MiB.

| Address | Size | Contents |
| --- | --- | --- |
| 0x4000000 | 64 KiB | C64 memory |
| 0x4010000 | 1 MiB | String heap, two halves of 512 KiB |
| 0x4110000 | 256 KiB | Temporary strings |
| 0x4150000 | 192 KiB | Variables, array pointers, `DEF FN` table |
| 0x4180000 | 20 KiB | Character generator and the saved text mode |
| 0x4200000 | 8 MiB | Arrays |
| 0x4A00000 | 4 MiB | File channel buffers |
| 0x4E00000 | 1 MiB | `LOAD` and `SAVE` buffer |
| 0x5000000 | 4 KiB | Machine code of the `CODE` words |

### 6.2 Numbers and strings

A number is a 64-bit IEEE floating-point number in one Forth cell. The machine-code words use the x87 FPU.

A string is an address and a length. The expression parser makes temporary strings. BASIC deletes them at the start of each statement. A string variable has a copy of its string in the string heap. When the heap is full, the garbage collector copies the strings of all string variables and string arrays to the other half of the heap.

## 7. Kernel changes

In QEMU, Forth on f64OS was slow. The cause is the TCG engine of QEMU. When the guest writes data into a 4 KiB page that also has code, QEMU does a slow check for changed code. There were two causes of these writes:

- `NEXT` writes `cur_dsp` for each Forth word. `cur_dsp` was in a page with kernel code.
- The Forth data stack was below 0x7C00, in the same page as the stage 1 boot code.

Two changes correct this:

- `kernel/f64_baremetal.nasm`: `cur_dsp` is at the start of a new page, before the return stack.
- `kernel/kernel.nasm`: the task stacks start at 0x7000 (Forth: 0x6000-0x6FFF, status bar: 0x5000-0x5FFF).

Because of this, `basic.f` puts the machine code of the `CODE` words in a different memory area (0x5000000), not in the dictionary.

| Benchmark (QEMU) | Before | After |
| --- | --- | --- |
| 1,000,000 empty `DO LOOP` iterations | 1.6 s | less than 0.06 s |
| BASIC: 1000 x `A=A+1` in a `FOR` loop | 4.1 s | 0.05 s |
| BASIC: Thatcher program | 2 of 11 rows after 8 s | full picture in less than 2 s |

DOOM starts and runs with the changed kernel.
