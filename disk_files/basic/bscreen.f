( f64 BASIC V2 - bscreen.f: VGA mode 13h, C64 screen, keyboard, screen editor )
DECIMAL

( ---- VGA registers. Ports: 3C0 960, 3C2 962, 3C4 964, 3C7 967, 3CE 974, 3D4 980, 3DA 986 ---- )
: SEQ!  ( v i -- ) 964 OUTB 965 OUTB ;
: SEQ@  ( i -- v ) 964 OUTB 965 INB ;
: GCR!  ( v i -- ) 974 OUTB 975 OUTB ;
: GCR@  ( i -- v ) 974 OUTB 975 INB ;
: CRTC! ( v i -- ) 980 OUTB 981 OUTB ;
: CRTC@ ( i -- v ) 980 OUTB 981 INB ;
: AC-RESET ( -- ) 986 INB DROP ;

( Register block: misc 0, seq 1-5, crtc 6-30, gc 31-39, ac 40-60 )
: VREGS-READ ( buf -- )
    972 INB OVER C!
    5 0 DO I SEQ@ OVER 1+ I + C! LOOP
    25 0 DO I CRTC@ OVER 6 + I + C! LOOP
    9 0 DO I GCR@ OVER 31 + I + C! LOOP
    21 0 DO AC-RESET I 960 OUTB 961 INB OVER 40 + I + C! LOOP
    AC-RESET 32 960 OUTB
    DROP
;
: VREGS-WRITE ( buf -- )
    DUP C@ 962 OUTB
    5 0 DO DUP 1+ I + C@ I SEQ! LOOP
    3 CRTC@ 128 OR 3 CRTC!
    17 CRTC@ 127 AND 17 CRTC!
    25 0 DO
        DUP 6 + I + C@
        I 3 = IF 128 OR THEN
        I 17 = IF 127 AND THEN
        I CRTC!
    LOOP
    9 0 DO DUP 31 + I + C@ I GCR! LOOP
    21 0 DO AC-RESET I 960 OUTB DUP 40 + I + C@ 960 OUTB LOOP
    AC-RESET 32 960 OUTB
    DROP
;

( Standard mode 13h register values, from doom/f64/doomgeneric_f64.c )
0 VALUE MODE13
HERE @ TO MODE13
HEX
63 C, 03 C, 01 C, 0F C, 00 C, 0E C,
5F C, 4F C, 50 C, 82 C, 54 C, 80 C, BF C, 1F C, 00 C, 41 C, 00 C, 00 C,
00 C, 00 C, 00 C, 00 C, 9C C, 0E C, 8F C, 28 C, 40 C, 96 C, B9 C, A3 C, FF C,
00 C, 00 C, 00 C, 00 C, 00 C, 40 C, 05 C, 0F C, FF C,
00 C, 01 C, 02 C, 03 C, 04 C, 05 C, 06 C, 07 C, 08 C, 09 C, 0A C, 0B C,
0C C, 0D C, 0E C, 0F C, 41 C, 00 C, 0F C, 00 C, 00 C,
DECIMAL
ALIGN

655360 CONSTANT VGAMEM        ( A0000 )
753664 CONSTANT TEXTMEM       ( B8000 )
VGASAVE        CONSTANT VS-REGS
VGASAVE 64 +   CONSTANT VS-DAC
VGASAVE 1024 + CONSTANT VS-TEXT
VGASAVE 8192 + CONSTANT VS-FONT

( Flat access to plane 2, where text mode keeps the font )
: PLANE2 ( -- ) 4 2 SEQ! 7 4 SEQ! 2 4 GCR! 0 5 GCR! 4 6 GCR! ;
: PLANE-RESTORE ( regs -- )
    DUP 3 + C@ 2 SEQ!  DUP 5 + C@ 4 SEQ!
    DUP 35 + C@ 4 GCR!  DUP 36 + C@ 5 GCR!  37 + C@ 6 GCR!
;
: SAVE-TEXT-MODE ( -- )
    VS-REGS VREGS-READ
    TEXTMEM VS-TEXT 4000 CMOVE
    0 967 OUTB 768 0 DO 969 INB VS-DAC I + C! LOOP
    PLANE2 VGAMEM VS-FONT 8192 CMOVE VS-REGS PLANE-RESTORE
;
: RESTORE-TEXT-MODE ( -- )
    VS-REGS VREGS-WRITE
    PLANE2 VS-FONT VGAMEM 8192 CMOVE VS-REGS PLANE-RESTORE
    0 968 OUTB 768 0 DO VS-DAC I + C@ 969 OUTB LOOP
    VS-TEXT TEXTMEM 4000 CMOVE
;

( C64 colours as 8-bit R G B )
0 VALUE PAL
HERE @ TO PAL
HEX
00 C, 00 C, 00 C,  FF C, FF C, FF C,  68 C, 37 C, 2B C,  70 C, A4 C, B2 C,
6F C, 3D C, 86 C,  58 C, 8D C, 43 C,  35 C, 28 C, 79 C,  B8 C, C7 C, 6F C,
6F C, 4F C, 25 C,  43 C, 39 C, 00 C,  9A C, 67 C, 59 C,  44 C, 44 C, 44 C,
6C C, 6C C, 6C C,  9A C, D2 C, 84 C,  6C C, 5E C, B5 C,  95 C, 95 C, 95 C,
DECIMAL
ALIGN
: SET-PALETTE ( -- )
    0 968 OUTB
    48 0 DO PAL I + C@ 2 RSHIFT 969 OUTB LOOP
;
( Border colour goes to the VGA overscan register )
: SET-BORDER ( c -- ) 15 AND AC-RESET 49 960 OUTB 960 OUTB AC-RESET 32 960 OUTB ;

( ---- Character generator ---- )
( The letters come from the 8x8 font of the VGA BIOS. If there is no such font, )
( the 8x16 text-mode font is made smaller. The graphics characters are below. )
0 VALUE FONT8
: FIND-FONT8 ( -- )
    0 TO FONT8
    851968 786432 DO
        I @ 57646281388750896 = IF I 520 - TO FONT8 LEAVE THEN
    LOOP
;
8 ALLOT CONSTANT GTMP
( 8x8 glyph of code-page-437 character c )
: GLYPH8 ( c -- addr )
    FONT8 IF 8 * FONT8 + EXIT THEN
    32 * VS-FONT +
    8 0 DO DUP I 2 * + C@ OVER I 2 * + 1+ C@ OR GTMP I + C! LOOP
    DROP GTMP
;

512 ALLOT CONSTANT GFX        ( glyphs for screen codes 64-127 )
64 ALLOT CONSTANT GMAP        ( 0, or 1 + a code-page-437 character )
GMAP 64 0 FILL
24 ALLOT CONSTANT LGFX        ( lower case set: screen codes 94, 95, 122 )
: G! ( b0 .. b7 sc -- ) 64 - 8 * GFX + 7 + 8 0 DO TUCK C! 1- LOOP DROP ;
: G437! ( cp sc -- ) 64 - GMAP + SWAP 1+ SWAP C! ;
: LG! ( b0 .. b7 n -- ) 8 * LGFX + 7 + 8 0 DO TUCK C! 1- LOOP DROP ;

HEX
00 00 00 FF 00 00 00 00 40 G!   06 41 G437!
08 08 08 08 08 08 08 08 42 G!   00 00 00 00 FF 00 00 00 43 G!
00 00 FF 00 00 00 00 00 44 G!   00 FF 00 00 00 00 00 00 45 G!
00 00 00 00 00 FF 00 00 46 G!   40 40 40 40 40 40 40 40 47 G!
02 02 02 02 02 02 02 02 48 G!   00 00 00 C0 20 10 10 10 49 G!
10 10 10 08 07 00 00 00 4A G!   10 10 10 20 C0 00 00 00 4B G!
80 80 80 80 80 80 80 FF 4C G!   80 40 20 10 08 04 02 01 4D G!
01 02 04 08 10 20 40 80 4E G!   FF 80 80 80 80 80 80 80 4F G!
FF 01 01 01 01 01 01 01 50 G!   00 3C 7E 7E 7E 7E 3C 00 51 G!
00 00 00 00 00 00 FF 00 52 G!   03 53 G437!
20 20 20 20 20 20 20 20 54 G!   00 00 00 07 08 10 10 10 55 G!
81 42 24 18 18 24 42 81 56 G!   00 3C 42 42 42 42 3C 00 57 G!
05 58 G437!                     04 04 04 04 04 04 04 04 59 G!
04 5A G437!                     10 10 10 FF 10 10 10 10 5B G!
A0 50 A0 50 A0 50 A0 50 5C G!   10 10 10 10 10 10 10 10 5D G!
E3 5E G437!                     FF 7F 3F 1F 0F 07 03 01 5F G!
00 00 00 00 00 00 00 00 60 G!   F0 F0 F0 F0 F0 F0 F0 F0 61 G!
00 00 00 00 FF FF FF FF 62 G!   FF 00 00 00 00 00 00 00 63 G!
00 00 00 00 00 00 00 FF 64 G!   80 80 80 80 80 80 80 80 65 G!
CC CC 33 33 CC CC 33 33 66 G!   01 01 01 01 01 01 01 01 67 G!
00 00 00 00 CC CC 33 33 68 G!   FF FE FC F8 F0 E0 C0 80 69 G!
03 03 03 03 03 03 03 03 6A G!   10 10 10 1F 10 10 10 10 6B G!
00 00 00 00 0F 0F 0F 0F 6C G!   10 10 10 1F 00 00 00 00 6D G!
00 00 00 F0 10 10 10 10 6E G!   00 00 00 00 00 00 FF FF 6F G!
00 00 00 1F 10 10 10 10 70 G!   10 10 10 FF 00 00 00 00 71 G!
00 00 00 FF 10 10 10 10 72 G!   10 10 10 F0 10 10 10 10 73 G!
C0 C0 C0 C0 C0 C0 C0 C0 74 G!   E0 E0 E0 E0 E0 E0 E0 E0 75 G!
07 07 07 07 07 07 07 07 76 G!   FF FF 00 00 00 00 00 00 77 G!
FF FF FF 00 00 00 00 00 78 G!   00 00 00 00 00 FF FF FF 79 G!
01 01 01 01 01 01 01 FF 7A G!   00 00 00 00 F0 F0 F0 F0 7B G!
0F 0F 0F 0F 00 00 00 00 7C G!   10 10 10 F0 00 00 00 00 7D G!
F0 F0 F0 F0 00 00 00 00 7E G!   F0 F0 F0 F0 0F 0F 0F 0F 7F G!
CC CC 33 33 CC CC 33 33 0 LG!   33 99 CC 66 33 99 CC 66 1 LG!
00 01 03 06 8C D8 70 00 2 LG!
DECIMAL

: ROM-AT ( set sc -- addr ) 8 * SWAP 2048 * + CHARROM + ;
: ROM! ( src set sc -- ) ROM-AT 8 CMOVE ;
: GFX-GLYPH ( sc -- addr )
    DUP 64 - GMAP + C@ ?DUP IF NIP 1- GLYPH8 ELSE 64 - 8 * GFX + THEN
;
( code-page-437 character for screen codes 0-31 of the upper case set )
: SC>ASCII ( sc -- c )
    DUP 0= IF DROP 64 EXIT THEN
    DUP 27 < IF 64 + EXIT THEN
    CASE 27 OF 91 ENDOF 28 OF 156 ENDOF 29 OF 93 ENDOF 30 OF 24 ENDOF 31 OF 27 ENDOF ENDCASE
;
: BUILD-ROM ( -- )
    FIND-FONT8
    32 0 DO I SC>ASCII GLYPH8 0 I ROM! LOOP
    64 32 DO I GLYPH8 0 I ROM! LOOP
    128 64 DO I GFX-GLYPH 0 I ROM! LOOP
    ( lower case set: copy, then change a-z, A-Z and three graphics )
    CHARROM CHARROM 2048 + 1024 CMOVE
    27 1 DO I 96 + GLYPH8 1 I ROM! LOOP
    91 65 DO I GLYPH8 1 I ROM! LOOP
    LGFX 1 94 ROM!  LGFX 8 + 1 95 ROM!  LGFX 16 + 1 122 ROM!
    ( reversed characters 128-255 of each set )
    2 0 DO
        1024 0 DO
            CHARROM J 2048 * + I + C@ 255 XOR
            CHARROM J 2048 * + I + 1024 + C!
        LOOP
    LOOP
;

( ---- The C64 screen ---- )
0 VALUE CX     0 VALUE CY        ( cursor column and row )
0 VALUE RVS    0 VALUE QUOTE     ( reverse mode, quote mode )
0 VALUE DIRTY  0 VALUE GFX-ON
0 VALUE VSCR   0 VALUE CBASE     ( shown screen: C64 address; glyphs: real address )
1 VALUE SERIAL-ECHO              ( 1: copy screen output to COM1 )
25 ALLOT CONSTANT LINK           ( 1 if the row continues the row above it )
ALIGN

: SCRBASE ( -- c64 ) 648 M@ 256 * ;
: VICBANK ( -- c64 ) 3 56576 M@ 3 AND - 16384 * ;
: VIC-UPDATE ( -- )
    VICBANK 53272 M@ 240 AND 64 * + TO VSCR
    VICBANK 53272 M@ 14 AND 1024 * +
    DUP VICBANK - DUP 4096 >= SWAP 8192 < AND
    VICBANK 32767 AND 0= AND IF
        2048 AND CHARROM +
    ELSE
        MEM +
    THEN
    TO CBASE
    1 TO DIRTY
;
: BGCOL ( -- c ) 53281 M@ 15 AND ;
: CELL-DRAW ( col row -- )
    2DUP 2560 * SWAP 8 * + VGAMEM + >R
    40 * +
    DUP VSCR + M@ 8 * CBASE +
    SWAP 55296 + M@ 15 AND
    BGCOL R> DRAW-CELL
;
: CURSOR-SHOW ( flag -- )
    GFX-ON 0= IF DROP EXIT THEN
    IF
        CX CY 40 * + DUP VSCR + M@ 128 XOR 8 * CBASE +
        SWAP 55296 + M@ 15 AND BGCOL
        CY 2560 * CX 8 * + VGAMEM + DRAW-CELL
    ELSE
        CX CY CELL-DRAW
    THEN
;
: REDRAW ( -- )
    0 TO DIRTY
    GFX-ON 0= IF EXIT THEN
    25 0 DO 40 0 DO I J CELL-DRAW LOOP LOOP
;
: PUT ( sc col row -- )
    40 * + DUP >R SCRBASE + M!
    646 M@ R@ 55296 + M!
    GFX-ON IF SCRBASE VSCR = IF R@ 40 /MOD CELL-DRAW THEN THEN
    RDROP
;
: SCROLL-UP ( -- )
    SCRBASE MEM + DUP 40 + SWAP 960 CMOVE
    SCRBASE MEM + 960 + 40 32 FILL
    55336 MEM + 55296 MEM + 960 CMOVE
    56256 MEM + 40 646 M@ FILL
    LINK 1+ LINK 24 CMOVE
    0 LINK 24 + C!  0 LINK C!
    REDRAW
;
: CLEAR-SCREEN ( -- )
    SCRBASE MEM + 1000 32 FILL
    55296 MEM + 1000 BGCOL FILL
    LINK 25 0 FILL
    0 TO CX 0 TO CY
    REDRAW
;
: NEWLINE-ROW ( -- ) CY 24 < IF CY 1+ TO CY ELSE SCROLL-UP THEN ;
: CR-OUT ( -- )
    0 TO QUOTE 0 TO RVS 0 TO CX
    NEWLINE-ROW
    BEGIN CY LINK + C@ WHILE NEWLINE-ROW REPEAT
;
: ADVANCE ( -- )
    CX 1+ TO CX
    CX 40 = IF
        0 TO CX
        CY LINK + C@ 0=
        NEWLINE-ROW
        CY LINK + C!
    THEN
;
: PUT-SC ( sc -- ) CX CY PUT ADVANCE ;

( Logical lines: one row, or two rows that are linked )
: LINE-START ( row -- row0 )
    BEGIN DUP 0> IF DUP LINK + C@ ELSE 0 THEN WHILE 1- REPEAT
;
: LINE-LEN ( row0 -- n )
    DUP 24 < IF 1+ LINK + C@ IF 80 ELSE 40 THEN ELSE DROP 40 THEN
;
: DRAW-ROWS ( row0 n -- )
    40 / 0 DO 40 0 DO I OVER J + CELL-DRAW LOOP LOOP DROP
;
( Line edit: R0 first row, POS cursor offset, N length, BASE screen, CBASE2 colour )
0 VALUE ED-R0  0 VALUE ED-POS  0 VALUE ED-N  0 VALUE ED-BASE  0 VALUE ED-COL
: ED-SETUP ( -- )
    CY LINE-START TO ED-R0
    CY ED-R0 - 40 * CX + TO ED-POS
    ED-R0 LINE-LEN TO ED-N
    ED-R0 40 * SCRBASE + MEM + TO ED-BASE
    ED-R0 40 * 55296 + MEM + TO ED-COL
;
( Delete the character to the left of the cursor )
: DEL-CHAR ( -- )
    ED-SETUP
    ED-POS 0= IF EXIT THEN
    ED-BASE ED-POS + DUP 1- ED-N ED-POS - CMOVE
    ED-COL ED-POS + DUP 1- ED-N ED-POS - CMOVE
    32 ED-BASE ED-N + 1- C!
    ED-POS 1- 40 /MOD ED-R0 + TO CY TO CX
    ED-R0 ED-N DRAW-ROWS
;
( Insert a space at the cursor )
: INS-CHAR ( -- )
    ED-SETUP
    ED-N ED-POS - 1- DUP 0> IF
        DUP ED-BASE ED-POS + DUP 1+ ROT CMOVE>
        ED-COL ED-POS + DUP 1+ ROT CMOVE>
    ELSE
        DROP
    THEN
    32 ED-BASE ED-POS + C!
    ED-R0 ED-N DRAW-ROWS
;

( ---- PETSCII output to the screen ---- )
: PET>SC ( c -- sc )
    DUP 64 < IF EXIT THEN
    DUP 96 < IF 64 - EXIT THEN
    DUP 128 < IF 32 - EXIT THEN
    DUP 255 = IF DROP 94 EXIT THEN
    DUP 192 < IF 64 - EXIT THEN
    128 -
;
: SER-OUT ( c -- )
    DUP 13 = IF DROP 13 1016 OUTB 10 1016 OUTB EXIT THEN
    DUP 29 = IF DROP 32 1016 OUTB EXIT THEN
    DUP 32 96 WITHIN IF 1016 OUTB EXIT THEN
    DUP 193 219 WITHIN IF 96 - 1016 OUTB EXIT THEN
    DROP
;
( PETSCII colour code to colour number, or -1 )
: COLOR-CODE ( c -- n )
    CASE
        144 OF 0 ENDOF   5 OF 1 ENDOF   28 OF 2 ENDOF  159 OF 3 ENDOF
        156 OF 4 ENDOF  30 OF 5 ENDOF   31 OF 6 ENDOF  158 OF 7 ENDOF
        129 OF 8 ENDOF 149 OF 9 ENDOF  150 OF 10 ENDOF 151 OF 11 ENDOF
        152 OF 12 ENDOF 153 OF 13 ENDOF 154 OF 14 ENDOF 155 OF 15 ENDOF
        -1 SWAP
    ENDCASE
;
: CTRL-OUT ( c -- )
    DUP COLOR-CODE DUP 0>= IF 646 M! DROP EXIT THEN DROP
    CASE
        147 OF CLEAR-SCREEN ENDOF
        19  OF 0 TO CX 0 TO CY ENDOF
        17  OF NEWLINE-ROW ENDOF
        145 OF CY 0> IF CY 1- TO CY THEN ENDOF
        29  OF CX 39 < IF CX 1+ TO CX ELSE 0 TO CX NEWLINE-ROW THEN ENDOF
        157 OF CX 0> IF CX 1- TO CX ELSE CY 0> IF 39 TO CX CY 1- TO CY THEN THEN ENDOF
        18  OF 1 TO RVS ENDOF
        146 OF 0 TO RVS ENDOF
        20  OF DEL-CHAR ENDOF
        148 OF INS-CHAR ENDOF
        14  OF 53272 M@ 2 OR 53272 M! VIC-UPDATE REDRAW ENDOF
        142 OF 53272 M@ 253 AND 53272 M! VIC-UPDATE REDRAW ENDOF
    ENDCASE
;
( Write one PETSCII character to the screen, as the KERNAL CHROUT does )
: CHROUT ( c -- )
    SERIAL-ECHO IF DUP SER-OUT THEN
    DUP 13 = OVER 141 = OR IF DROP CR-OUT EXIT THEN
    DUP 127 AND 32 < IF
        QUOTE IF
            DUP 128 < IF 128 OR ELSE 64 + THEN PUT-SC EXIT
        THEN
        CTRL-OUT EXIT
    THEN
    DUP 34 = IF QUOTE 0= TO QUOTE THEN
    PET>SC RVS IF 128 OR THEN PUT-SC
;
: PTYPE ( addr len -- )
    DUP 0> IF 0 DO DUP I + C@ CHROUT LOOP ELSE DROP THEN DROP
;

( ---- Keyboard. The C64 keyboard buffer is at 631, the count at 198. ---- )
KSERVICES 32 + @ CONSTANT KB-WPOS
KSERVICES 40 + @ CONSTANT KB-RPOS
KSERVICES 8 + @ CONSTANT TICKS-ADDR
: TICKS ( -- n ) TICKS-ADDR @ ;
: KEY? ( -- flag ) KB-WPOS C@ KB-RPOS C@ <> ;
0 VALUE STOPFLAG
( PC key to PETSCII. Esc is RUN/STOP, PgUp is CLR, PgDn is INST. )
: KEY>PET ( c -- pet | 0 )
    DUP 97 123 WITHIN IF 32 - EXIT THEN
    DUP 65 91 WITHIN IF 128 + EXIT THEN
    DUP 32 64 WITHIN IF EXIT THEN
    CASE
        10  OF 13 ENDOF   8   OF 20 ENDOF   27  OF 3 ENDOF
        19  OF 19 ENDOF   128 OF 145 ENDOF  129 OF 17 ENDOF
        130 OF 157 ENDOF  131 OF 29 ENDOF   132 OF 147 ENDOF
        133 OF 148 ENDOF  64  OF 64 ENDOF   91  OF 91 ENDOF
        93  OF 93 ENDOF   92  OF 92 ENDOF   94  OF 94 ENDOF
        95  OF 95 ENDOF   126 OF 255 ENDOF
        0 SWAP
    ENDCASE
;
: KBD-POLL ( -- )
    BEGIN
        KEY?
    WHILE
        KEY-RAW KEY>PET ?DUP IF
            DUP 3 = IF
                DROP 1 TO STOPFLAG
            ELSE
                198 M@ 10 < IF DUP 631 198 M@ + M! 198 M@ 1+ 198 M! THEN
                DROP
            THEN
        THEN
    REPEAT
;
( Next key from the buffer, or 0 )
: GETKEY ( -- pet | 0 )
    KBD-POLL
    198 M@ IF
        631 M@
        632 MEM + 631 MEM + 9 CMOVE
        198 M@ 1- 198 M!
    ELSE
        0
    THEN
;
0 VALUE BLINK-ON
0 VALUE BLINK-T
( Wait for a key with a blinking cursor. RUN/STOP gives 3. )
: WAITKEY ( -- pet )
    0 TO BLINK-ON TICKS TO BLINK-T
    BEGIN
        GETKEY
        DUP 0= IF STOPFLAG IF DROP 3 0 TO STOPFLAG THEN THEN
        DUP 0=
    WHILE
        DROP
        DIRTY IF REDRAW BLINK-ON CURSOR-SHOW THEN
        TICKS BLINK-T - 6 >= IF
            BLINK-ON 0= TO BLINK-ON TICKS TO BLINK-T BLINK-ON CURSOR-SHOW
        THEN
        HALT
    REPEAT
    BLINK-ON IF 0 CURSOR-SHOW THEN
;

( ---- Screen editor input ---- )
( RETURN reads the logical line under the cursor from screen memory. )
88 ALLOT CONSTANT IBUF
0 VALUE IBUF-LEN
0 VALUE IN-ROW   0 VALUE IN-COL   0 VALUE IN-MODE
: SC>PET ( sc -- c )
    DUP 128 AND IF
        127 AND
        DUP 32 < IF EXIT THEN
        DUP 64 96 WITHIN IF 64 + EXIT THEN
    THEN
    DUP 32 < IF 64 + EXIT THEN
    DUP 64 < IF EXIT THEN
    DUP 96 < IF 32 + EXIT THEN
    64 +
;
: GRAB-LINE ( -- addr len )
    CY LINE-START >R
    0 IN-MODE IF IN-ROW LINE-START R@ = IF DROP IN-ROW R@ - 40 * IN-COL + THEN THEN
    R@ LINE-LEN                         ( start n )
    0 TO IBUF-LEN
    2DUP < IF
        SWAP DO
            R@ 40 * I + SCRBASE + M@ SC>PET
            IBUF IBUF-LEN + C! IBUF-LEN 1+ TO IBUF-LEN
        LOOP
    ELSE
        2DROP
    THEN
    BEGIN IBUF-LEN 0> IF IBUF IBUF-LEN + 1- C@ 32 = ELSE 0 THEN
    WHILE IBUF-LEN 1- TO IBUF-LEN REPEAT
    ( put the cursor on the last row of the logical line )
    R@ LINE-LEN 40 / 1- R> + TO CY
    IBUF IBUF-LEN
;
( Read one line with the screen editor. IN-MODE 1: INPUT statement. )
: READ-LINE ( -- addr len )
    CY TO IN-ROW CX TO IN-COL
    BEGIN
        WAITKEY DUP 13 <>
    WHILE
        CASE
            20  OF DEL-CHAR ENDOF
            148 OF INS-CHAR ENDOF
            3   OF IN-MODE IF 0 TO IN-MODE E-BREAK THROW THEN ENDOF
            DUP CHROUT
        ENDCASE
    REPEAT
    DROP
    GRAB-LINE
    13 CHROUT
;

( ---- Graphics mode on and off ---- )
0 VALUE ROM-BUILT
: GFX-ENTER ( -- )
    GFX-ON IF EXIT THEN
    SAVE-TEXT-MODE
    MODE13 VREGS-WRITE
    VGAMEM 64000 0 FILL
    SET-PALETTE
    53280 M@ SET-BORDER
    ROM-BUILT 0= IF BUILD-ROM 1 TO ROM-BUILT THEN
    1 TO GFX-ON
    VIC-UPDATE REDRAW
;
: GFX-EXIT ( -- )
    GFX-ON IF RESTORE-TEXT-MODE 0 TO GFX-ON THEN
;

INCLUDE btoken.f
