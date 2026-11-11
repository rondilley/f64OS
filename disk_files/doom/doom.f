( DOOM loader for f64OS                                                  )
( Usage:  CD doom   INCLUDE doom.f   DOOM                               )
( Needs:  doom.bin, an IWAD file in this directory, and QEMU -m 128M    )
(                                                                       )
( Memory map while DOOM runs:                                           )
(   1000000 - 1BFFFFF  doom.bin code, data, and BSS                     )
(   1C00000 - 1FFFFFF  DOOM stack, 4 MiB, grows down from 2000000       )
(   2000000 - ...      IWAD file                                        )
(   after IWAD - 6FFFFFF  heap for malloc                               )
(   F00000 - F03FFF    Sound Blaster DMA buffer, below 16 MiB           )

HEX
1000000 CONSTANT DOOM-BASE
1C00000 CONSTANT DOOM-LIMIT
2000000 CONSTANT DOOM-STACK
2000000 CONSTANT WAD-BASE
7000000 CONSTANT HEAP-END
F00000 CONSTANT DMA-BASE
DECIMAL

( Boot block for doom.bin: 10 cells. See doom/f64/include/f64.h )
10 CELLS ALLOT CONSTANT DOOM-BOOT
: BOOT! ( value index -- ) CELLS DOOM-BOOT + ! ;

0 VALUE LD-LBA
0 VALUE LD-ADDR

( Read the file of directory entry de to addr. Shows one dot per 1 MiB. )
: LOAD-DE ( de addr -- size )
    TO LD-ADDR
    DUP DE-LBA TO LD-LBA
    DE-SIZE DUP 511 + 512 /
    DUP 0> IF
        0 DO
            LD-LBA I +  LD-ADDR I 512 * +  SECTOR@
            I 2047 AND 0= IF '.' EMIT THEN
        LOOP
    ELSE
        DROP
    THEN
;

0 VALUE WAD-DE
0 VALUE WAD-NAME
0 VALUE WAD-LEN
0 VALUE WAD-SIZE

( Use the IWAD addr len if it is in this directory and no IWAD is found yet )
: TRY-WAD ( addr len -- )
    WAD-DE IF 2DROP EXIT THEN
    2DUP FIND-ENTRY ?DUP IF
        TO WAD-DE TO WAD-LEN TO WAD-NAME
    ELSE
        2DROP
    THEN
;

: FIND-WAD ( -- )
    0 TO WAD-DE
    S" doom1.wad" TRY-WAD
    S" doom.wad" TRY-WAD
    S" doomu.wad" TRY-WAD
    S" doom2.wad" TRY-WAD
    S" plutonia.wad" TRY-WAD
    S" tnt.wad" TRY-WAD
    S" freedoom1.wad" TRY-WAD
    S" freedoom2.wad" TRY-WAD
    S" freedm.wad" TRY-WAD
;

: DOOM ( -- )
    FIND-WAD
    WAD-DE 0= IF
        ." No IWAD found. Put doom1.wad or freedoom1.wad in this directory." CR
        EXIT
    THEN
    S" doom.bin" FIND-ENTRY ?DUP 0= IF
        ." doom.bin not found. Build it with: make -C doom" CR
        EXIT
    THEN
    ." Loading doom.bin " DOOM-BASE LOAD-DE DROP CR
    ." Loading " WAD-NAME WAD-LEN TELL SPACE
    WAD-DE WAD-BASE LOAD-DE TO WAD-SIZE CR

    1                  0 BOOT!
    KSERVICES          1 BOOT!
    WAD-BASE           2 BOOT!
    WAD-SIZE           3 BOOT!
    WAD-NAME           4 BOOT!
    WAD-LEN            5 BOOT!
    WAD-BASE WAD-SIZE + 1048575 + 1048575 INVERT AND
                       6 BOOT!
    HEAP-END           7 BOOT!
    DOOM-LIMIT         8 BOOT!
    DMA-BASE           9 BOOT!

    DOOM-BOOT DOOM-BASE DOOM-STACK CALL-NATIVE
    ?DUP IF
        ." DOOM error: " DUP STRLEN TELL CR
    THEN
;

." DOOM loader ready. Type DOOM to play." CR
