( f64 BASIC V2 - bio.f: devices, file channels, LOAD SAVE VERIFY )
DECIMAL

( ---- String helpers ---- )
: /STRING ( addr len n -- addr+n len-n ) ROT OVER + -ROT - ;
: SKIPSP ( addr len -- addr len )
    BEGIN DUP 0> IF OVER C@ 32 = ELSE 0 THEN WHILE 1 /STRING REPEAT
;
( Position of character c, or -1 )
: SCAN-CHAR ( addr len c -- idx )
    >R
    DUP 0> IF
        0 DO DUP I + C@ R@ = IF DROP I UNLOOP RDROP EXIT THEN LOOP
    ELSE
        DROP
    THEN
    DROP RDROP -1
;
( Next word, up to a space )
: TOK ( addr len -- addr len taddr tlen )
    SKIPSP OVER >R 0 >R
    BEGIN DUP 0> IF OVER C@ 32 <> ELSE 0 THEN WHILE 1 /STRING R> 1+ >R REPEAT
    R> R> SWAP
;
( Compare n bytes without regard to case )
: CI= ( a1 a2 n -- flag )
    0 DO OVER I + C@ UPPER OVER I + C@ UPPER <> IF 2DROP UNLOOP 0 EXIT THEN LOOP
    2DROP 1
;

( ---- File names: PETSCII to f64OS names. Unshifted letters become lower case. ---- )
40 ALLOT CONSTANT FNBUF
0 VALUE FN-LEN
0 VALUE FN-MODE                 ( 0, or 82 R, 87 W, 65 A, from ",S,W" and so on )
: PET>FNC ( c -- c )
    DUP 65 91 WITHIN IF 32 + EXIT THEN
    DUP 193 219 WITHIN IF 128 - EXIT THEN
    DUP 32 127 WITHIN 0= IF DROP 95 THEN
;
( Remove @ and the drive number with its colon. Copy the name up to a comma. )
: FN-PARSE ( addr len -- )
    0 TO FN-LEN 0 TO FN-MODE
    DUP 0> IF OVER C@ 64 = IF 1 /STRING THEN THEN
    2DUP 58 SCAN-CHAR DUP 0 3 WITHIN IF 1+ /STRING ELSE DROP THEN
    BEGIN
        DUP 0> IF OVER C@ 44 <> ELSE 0 THEN
    WHILE
        OVER C@ PET>FNC
        FN-LEN 16 < IF FNBUF FN-LEN + C! FN-LEN 1+ TO FN-LEN ELSE DROP THEN
        1 /STRING
    REPEAT
    BEGIN
        DUP 1 >
    WHILE
        OVER C@ 44 = IF
            OVER 1+ C@ DUP 82 = OVER 87 = OR OVER 65 = OR IF TO FN-MODE ELSE DROP THEN
        THEN
        1 /STRING
    REPEAT
    2DROP
;
: FN-DOLLAR? ( -- flag ) FN-LEN 1 = FNBUF C@ 36 = AND ;

( ---- f64OS file system access. The words come from kernel/f64.f. ---- )
0 VALUE BR-BUF
0 VALUE BR-MAX
0 VALUE BR-LBA
0 VALUE BR-SIZE
( Read a file of the current directory. Gives the size, -1 if not found, -2 if too big. )
: BREAD ( naddr nlen buf max -- size )
    TO BR-MAX TO BR-BUF
    FIND-ENTRY ?DUP 0= IF -1 EXIT THEN
    DUP DE-DIR? IF DROP -1 EXIT THEN
    DUP DE-LBA TO BR-LBA DE-SIZE TO BR-SIZE
    BR-SIZE BR-MAX > IF -2 EXIT THEN
    BR-SIZE 511 + 512 / ?DUP IF
        0 DO BR-LBA I + BR-BUF I 512 * + SECTOR@ LOOP
    THEN
    BR-SIZE
;
( Write a file into the current directory. An old file with the same name is replaced. )
: BWRITE ( buf len naddr nlen -- )
    16 MIN TO MK-LEN
    MK-NAME-BUF MK-LEN CMOVE
    TO WF-SIZE TO WF-ADDR
    MK-NAME-BUF MK-LEN FIND-ENTRY ?DUP IF
        DUP DE-DIR? IF DROP E-FOPEN THROW THEN
        32 ZERO-MEM SAVE-DIR
    THEN
    WF-SIZE 511 + 512 / DUP 0= IF DROP 1 THEN
    DUP TO WF-SECTORS ALLOC-SECTORS TO WF-LBA
    FREE-ENTRY ?DUP 0= IF E-MEM THROW THEN TO WF-DE
    WF-SECTORS 0 DO
        SEC-BUF 512 0 FILL
        WF-SIZE I 512 * - 512 MIN
        DUP 0> IF WF-ADDR I 512 * + SEC-BUF ROT CMOVE ELSE DROP THEN
        WF-LBA I + SEC-BUF SECTOR!
    LOOP
    MK-NAME-BUF MK-LEN WF-DE DE-SET-NAME
    WF-LBA WF-DE 16 + !
    WF-SIZE WF-DE 24 + !
    SAVE-DIR
;
( Delete a file. Gives 1 if the file was there. )
: BDELETE ( naddr nlen -- flag )
    FIND-ENTRY ?DUP 0= IF 0 EXIT THEN
    DUP DE-DIR? IF DROP 0 EXIT THEN
    32 ZERO-MEM SAVE-DIR 1
;
( Rename a file. Gives 1 if the file was there. )
0 VALUE RN-LBA
0 VALUE RN-SIZE
: BRENAME ( naddr nlen oaddr olen -- flag )
    FIND-ENTRY ?DUP 0= IF 2DROP 0 EXIT THEN
    DUP DE-DIR? IF DROP 2DROP 0 EXIT THEN
    DUP DE-LBA TO RN-LBA DUP DE-SIZE TO RN-SIZE
    >R 16 MIN R@ DE-SET-NAME
    RN-LBA R@ 16 + ! RN-SIZE R> 24 + !
    SAVE-DIR 1
;

( ---- Channels, as made by OPEN lfn,dev,sa,"name" ---- )
10 CONSTANT NCHAN
96 CONSTANT CH-SIZE
NCHAN CH-SIZE * ALLOT CONSTANT CHANS
: CH ( i -- ch ) CH-SIZE * CHANS + ;
: CH-INDEX ( ch -- i ) CHANS - CH-SIZE / ;
: >DEV 8 + ;   : >SA 16 + ;   : >MODE 24 + ;  : >BUF 32 + ;
: >LEN 40 + ;  : >POS 48 + ;  : >NAME 56 + ;  : >NLEN 72 + ;
: >COL 80 + ;  : >CMDLEN 88 + ;
( Mode: 0 read, 1 write, 2 disk command channel )
0 VALUE OUTCH                   ( 0: the screen. Else the channel for output. )
: CH-INIT ( -- ) NCHAN 0 DO -1 I CH ! LOOP 0 TO OUTCH ;
CH-INIT
: FIND-CH ( lfn -- ch | 0 )
    NCHAN 0 DO I CH @ OVER = IF DROP I CH UNLOOP EXIT THEN LOOP DROP 0
;
: DISK-DEV? ( dev -- flag ) DUP 1 = SWAP 8 12 WITHIN OR ;

( Disk status that the command channel gives )
: CH-STATUS ( addr len ch -- )
    >R DUP R@ >LEN ! 0 R@ >POS ! R> >BUF @ SWAP CMOVE
;
: STATUS-OK ( ch -- ) >R S" 00, OK,00,00" R> CH-STATUS ;
( The argument of a disk command: the text after the colon )
: CMD-ARG ( addr len -- addr len )
    2DUP 58 SCAN-CHAR DUP 0< IF DROP 1 /STRING ELSE 1+ /STRING THEN
;
40 ALLOT CONSTANT FNBUF2
0 VALUE FN2-LEN
( R0:NEW=OLD )
: DISK-RENAME ( addr len -- )
    CMD-ARG 2DUP 61 SCAN-CHAR DUP 0< IF DROP 2DROP EXIT THEN
    >R OVER R@ FN-PARSE
    FNBUF FNBUF2 FN-LEN CMOVE FN-LEN TO FN2-LEN
    R> 1+ /STRING FN-PARSE
    FNBUF2 FN2-LEN FNBUF FN-LEN BRENAME DROP
;
( Run a disk command: S scratch, R rename. Other commands do nothing. )
: DISK-CMD ( addr len ch -- )
    >R
    DUP 0= IF 2DROP R> STATUS-OK EXIT THEN
    OVER C@ 83 = IF
        CMD-ARG FN-PARSE FNBUF FN-LEN BDELETE DROP
        S" 01, FILES SCRATCHED,01,00" R> CH-STATUS EXIT
    THEN
    OVER C@ 82 = IF DISK-RENAME R> STATUS-OK EXIT THEN
    2DROP R> STATUS-OK
;

0 VALUE OP-LFN  0 VALUE OP-DEV  0 VALUE OP-SA
0 VALUE OP-NA   0 VALUE OP-NL   0 VALUE OP-CH
: CH-OPEN ( lfn dev sa naddr nlen -- )
    TO OP-NL TO OP-NA TO OP-SA TO OP-DEV TO OP-LFN
    OP-LFN FIND-CH IF E-FOPEN THROW THEN
    -1 FIND-CH DUP 0= IF E-FILES THROW THEN TO OP-CH
    OP-DEV OP-CH >DEV !  OP-SA OP-CH >SA !
    0 OP-CH >LEN !  0 OP-CH >POS !  0 OP-CH >COL !
    0 OP-CH >NLEN !  0 OP-CH >CMDLEN !  0 OP-CH >MODE !
    OP-CH CH-INDEX CHANBUF-SIZE * CHANBUF + OP-CH >BUF !
    OP-DEV DUP 0= OVER 3 = OR SWAP 4 = OR IF
        OP-DEV 4 = IF 1 OP-CH >MODE ! THEN
    ELSE
        OP-DEV DISK-DEV? 0= IF E-DEVICE THROW THEN
        OP-SA 15 = IF
            2 OP-CH >MODE !
            OP-NA OP-NL OP-CH DISK-CMD
        ELSE
            OP-NL 0= IF E-NONAME THROW THEN
            OP-NA OP-NL FN-PARSE
            FN-LEN 0= IF E-NONAME THROW THEN
            FNBUF OP-CH >NAME FN-LEN CMOVE FN-LEN OP-CH >NLEN !
            OP-SA 0= IF 82 ELSE OP-SA 1 = IF 87 ELSE FN-MODE ?DUP 0= IF 82 THEN THEN THEN
            CASE
                87 OF 1 OP-CH >MODE ! ENDOF
                65 OF
                    FNBUF FN-LEN OP-CH >BUF @ CHANBUF-SIZE 512 - BREAD
                    0 MAX OP-CH >LEN !  1 OP-CH >MODE !
                ENDOF
                FNBUF FN-LEN OP-CH >BUF @ CHANBUF-SIZE 512 - BREAD
                DUP -1 = IF E-FNFOUND THROW THEN
                DUP -2 = IF E-MEM THROW THEN
                OP-CH >LEN !
            ENDCASE
        THEN
    THEN
    OP-LFN OP-CH !
;
: CH-CLOSE ( ch -- )
    DUP >MODE @ 1 = OVER >DEV @ DISK-DEV? AND IF
        DUP >BUF @ OVER >LEN @ 2 PICK >NAME 3 PICK >NLEN @ BWRITE
    THEN
    DUP OUTCH = IF 0 TO OUTCH THEN
    -1 SWAP !
;

( ---- Output to the current channel ---- )
: CH-PUT ( c ch -- )
    DUP >DEV @ 3 = IF DROP CHROUT EXIT THEN
    DUP >DEV @ 4 = IF DROP SER-OUT EXIT THEN
    DUP >DEV @ 0= IF E-NOTOUT THROW THEN
    DUP >MODE @ 2 = IF
        OVER 13 = IF
            NIP DUP >BUF @ 1024 + OVER >CMDLEN @ ROT DUP >R DISK-CMD 0 R> >CMDLEN !
            EXIT
        THEN
        DUP >CMDLEN @ 80 < IF
            DUP >BUF @ 1024 + OVER >CMDLEN @ + ROT SWAP C! 1 SWAP >CMDLEN +!
        ELSE
            2DROP
        THEN
        EXIT
    THEN
    DUP >MODE @ 1 <> IF E-NOTOUT THROW THEN
    OVER 13 = IF 0 OVER >COL ! ELSE 1 OVER >COL +! THEN
    DUP >LEN @ CHANBUF-SIZE 512 - >= IF E-MEM THROW THEN
    DUP >BUF @ OVER >LEN @ + ROT SWAP C!
    1 SWAP >LEN +!
;
: BOUT ( c -- ) OUTCH ?DUP IF CH-PUT ELSE CHROUT THEN ;
: BTYPE ( addr len -- ) DUP 0> IF 0 DO DUP I + C@ BOUT LOOP ELSE DROP THEN DROP ;
( Column of the output: the logical line on the screen, or the count for a file )
: OUT-COL ( -- n )
    OUTCH ?DUP IF >COL @ ELSE CY CY LINE-START - 40 * CX + THEN
;
( The screen moves the cursor right. Files get a space. )
: OUT-RIGHT ( -- ) OUTCH IF 32 ELSE 29 THEN BOUT ;

( ---- Input from a channel. Gives -1 at the end of the data. ---- )
: CH-GET ( ch -- c )
    DUP >DEV @ DUP 0= SWAP 3 = OR IF DROP GETKEY EXIT THEN
    DUP >DEV @ 4 = IF E-NOTIN THROW THEN
    DUP >MODE @ 1 = IF E-NOTIN THROW THEN
    DUP >POS @ OVER >LEN @ >= IF DROP 66 TO STATUS -1 EXIT THEN
    DUP >BUF @ OVER >POS @ + C@ SWAP
    1 OVER >POS +!
    DUP >POS @ SWAP >LEN @ >= IF 64 TO STATUS THEN
;

( ---- Program as text. Control characters are written as {NAME}. ---- )
256 CELLS ALLOT CONSTANT ESC-A
256 ALLOT CONSTANT ESC-L
: ESC-SRC ( -- addr len )
    S" 5 WHT 17 DOWN 18 RVON 19 HOME 20 DEL 28 RED 29 RGHT 30 GRN 31 BLU 129 ORNG 144 BLK 145 UP 146 RVOF 147 CLR 148 INST 149 BRN 150 LRED 151 GRY1 152 GRY2 153 LGRN 154 LBLU 155 GRY3 156 PUR 157 LEFT 158 YEL 159 CYN 255 PI 14 SWLC 142 SWUC"
;
: INIT-ESC ( -- )
    ESC-L 256 0 FILL
    ESC-SRC
    BEGIN
        SKIPSP DUP 0>
    WHILE
        TOK STR>F DROP FROUND>S >R
        TOK R@ ESC-L + C! R> CELLS ESC-A + !
    REPEAT
    2DROP
;
INIT-ESC

0 VALUE LB-PTR
: LB, ( c -- ) LB-PTR C! LB-PTR 1+ TO LB-PTR ;
: LB-STR ( addr len -- ) DUP 0> IF 0 DO DUP I + C@ LB, LOOP ELSE DROP THEN DROP ;
: LB-NUM ( u -- ) 10 /MOD ?DUP IF RECURSE THEN 48 + LB, ;
: LB-PET ( c -- )
    DUP 32 96 WITHIN IF LB, EXIT THEN
    DUP 193 219 WITHIN IF 96 - LB, EXIT THEN
    123 LB,
    DUP ESC-L + C@ ?DUP IF OVER CELLS ESC-A + @ SWAP LB-STR DROP ELSE LB-NUM THEN
    125 LB,
;
: LB-LINE ( c64 -- )
    DUP 2 + MW@ LB-NUM 32 LB,
    4 + MEM + 0 SWAP
    BEGIN
        DUP C@
    WHILE
        DUP C@
        DUP 34 = IF ROT 0= -ROT THEN
        DUP 128 204 WITHIN 3 PICK 0= AND IF KW-TEXT LB-STR ELSE LB-PET THEN
        1+
    REPEAT
    2DROP
    10 LB,
;
( Write the program as text at addr. Gives the length. )
: PROG>TEXT ( addr -- len )
    DUP TO LB-PTR
    TXTTAB BEGIN DUP MW@ WHILE DUP LB-LINE MW@ REPEAT DROP
    LB-PTR SWAP -
;

( Text to program. The case that has more letters in the file is unshifted. )
( Thus SAVE files (upper case) and petcat files (lower case) both load. )
256 ALLOT CONSTANT LT-BUF
0 VALUE LT-LEN
0 VALUE LT-IB
0 VALUE LC-SHIFTED
: SCAN-CASE ( addr len -- )
    0 TO LT-IB 0 >R
    DUP 0> IF
        0 DO
            DUP I + C@
            DUP 123 = IF 1 TO LT-IB THEN
            DUP 125 = IF 0 TO LT-IB THEN
            LT-IB IF DROP ELSE
                DUP 65 91 WITHIN IF R> 1+ >R THEN
                97 123 WITHIN IF R> 1- >R THEN
            THEN
        LOOP
    ELSE
        DROP
    THEN
    DROP R> 0>= TO LC-SHIFTED
;
: TXT>PET ( c -- c | -1 )
    DUP 97 123 WITHIN IF LC-SHIFTED IF 96 + ELSE 32 - THEN EXIT THEN
    DUP 65 91 WITHIN IF LC-SHIFTED 0= IF 128 + THEN EXIT THEN
    DUP 9 = IF DROP 32 EXIT THEN
    DUP 32 96 WITHIN IF EXIT THEN
    DROP -1
;
: LT, ( c -- ) LT-LEN 250 < IF LT-BUF LT-LEN + C! LT-LEN 1+ TO LT-LEN ELSE DROP THEN ;
: ESC-LOOKUP ( addr len -- code | -1 )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ DIGIT? IF STR>F DROP FROUND>S 255 AND EXIT THEN
    256 0 DO
        I ESC-L + C@ OVER = IF
            OVER I CELLS ESC-A + @ 2 PICK CI= IF 2DROP I UNLOOP EXIT THEN
        THEN
    LOOP
    2DROP -1
;
: LT-CONVERT ( addr len -- )
    0 TO LT-LEN
    BEGIN
        DUP 0>
    WHILE
        OVER C@ 123 = IF
            OVER 1+ OVER 1- 125 SCAN-CHAR
            DUP 0< IF
                DROP 1 /STRING
            ELSE
                DUP >R 2 PICK 1+ SWAP ESC-LOOKUP
                DUP 0< IF DROP ELSE LT, THEN
                R> 2 + /STRING
            THEN
        ELSE
            OVER C@ TXT>PET DUP 0< IF DROP ELSE LT, THEN
            1 /STRING
        THEN
    REPEAT
    2DROP
;
( Add the line in TBUF at the end of the program. Only the new link changes. )
: APPEND-LINE ( n -- )
    VARTAB@ 2 -
    DUP 6 + TB-LEN + 40960 > IF E-MEM THROW THEN
    TUCK 2 + MW!
    TBUF OVER 4 + MEM + TB-LEN CMOVE
    DUP 4 + TB-LEN +
    0 OVER MW! TUCK SWAP MW!
    2 + VARTAB!
;
( Lines in order go to the end. Other lines go through STORE-LINE. )
-1 VALUE LT-LAST
: LOAD-STORE ( n -- )
    DUP LT-LAST > TB-LEN 1 > AND IF DUP TO LT-LAST APPEND-LINE ELSE STORE-LINE THEN
;
( LT-BUF holds one line: number and text )
: LT-LINE ( -- )
    LT-BUF LT-LEN SKIPSP
    DUP 0= IF 2DROP EXIT THEN
    OVER C@ DIGIT? 0= IF 2DROP EXIT THEN
    0 >R
    BEGIN
        DUP 0> IF OVER C@ DIGIT? ELSE 0 THEN
    WHILE
        R> 10 * 2 PICK C@ 48 - + >R 1 /STRING
    REPEAT
    SKIPSP CRUNCH
    R> DUP 63999 > IF DROP EXIT THEN
    LOAD-STORE
;
: LOAD-TEXT ( addr len -- )
    -1 TO LT-LAST
    2DUP SCAN-CASE
    BEGIN
        DUP 0>
    WHILE
        2DUP 10 SCAN-CHAR DUP 0< IF DROP DUP THEN
        >R OVER R@
        DUP 0> IF 2DUP + 1- C@ 13 = IF 1- THEN THEN
        LT-CONVERT LT-LINE
        R> 1+ /STRING
    REPEAT
    2DROP
;

( ---- PRG files: two bytes of load address, then the data ---- )
0 VALUE LP-ADDR
: LOAD-PRG ( addr len sa -- )
    >R OVER W@ R> 0= IF DROP 2049 THEN TO LP-ADDR
    2 /STRING
    LP-ADDR OVER + 65536 > IF E-MEM THROW THEN
    TUCK LP-ADDR MEM + SWAP CMOVE
    LP-ADDR 2049 = IF
        2049 + DUP 2 - MW@ IF 0 OVER MW! 2 + THEN VARTAB! RELINK
    ELSE
        DROP VIC-UPDATE
    THEN
;

( ---- Directory as a program: LOAD "$" ---- )
: TB-STR ( addr len -- ) DUP 0> IF 0 DO DUP I + C@ TB, LOOP ELSE DROP THEN DROP ;
: ASC>PET ( c -- c ) DUP 97 123 WITHIN IF 32 - THEN ;
: DIR-PROG ( -- )
    NEW-PROG
    0 TO TB-LEN 18 TB, 34 TB, S" F64OS DISK      " TB-STR 34 TB, S"  64 2A" TB-STR 0 TB,
    0 APPEND-LINE
    LOAD-DIR
    64 0 DO
        DIR-BUF I 32 * + DUP C@ IF
            0 TO TB-LEN
            DUP DE-SIZE 253 + 254 / OVER DE-DIR? IF DROP 0 THEN
            DUP 10 < IF 32 TB, THEN DUP 100 < IF 32 TB, THEN 32 TB,
            34 TB,
            OVER DE-LEN 0 DO OVER I + C@ I 0= IF 127 AND THEN ASC>PET TB, LOOP
            34 TB,
            16 2 PICK DE-LEN - 0 MAX 1+ 0 DO 32 TB, LOOP
            OVER DE-DIR? IF S" DIR" ELSE S" PRG" THEN TB-STR 0 TB,
            APPEND-LINE
        THEN
        DROP
    LOOP
    0 TO TB-LEN S" BLOCKS FREE." TB-STR 0 TB, 664 APPEND-LINE
    LOAD-DIR
;

( ---- LOAD, SAVE, VERIFY of programs ---- )
: PRG-DATA? ( addr len -- flag )
    1 > IF C@ DUP 32 < OVER 9 <> AND OVER 10 <> AND SWAP 13 <> AND ELSE DROP 0 THEN
;
: READ-PROG-FILE ( -- addr len )
    FNBUF FN-LEN LOADBUF LOADBUF-SIZE 2 / BREAD
    DUP -1 = IF E-FNFOUND THROW THEN
    DUP -2 = IF E-MEM THROW THEN
    LOADBUF SWAP
;
( FN-PARSE must be done first )
: DO-LOAD ( sa -- )
    FN-DOLLAR? IF DROP DIR-PROG EXIT THEN
    >R READ-PROG-FILE
    2DUP PRG-DATA? IF R> LOAD-PRG ELSE RDROP NEW-PROG LOAD-TEXT THEN
;
: DO-SAVE ( -- )
    LOADBUF PROG>TEXT LOADBUF SWAP FNBUF FN-LEN BWRITE
;
: DO-VERIFY ( -- )
    READ-PROG-FILE
    2DUP PRG-DATA? IF
        2 /STRING DUP VARTAB@ 2049 - <> IF E-VERIFY THROW THEN
        2049 MEM + SWAP
    ELSE
        LOADBUF LOADBUF-SIZE 2 / + DUP PROG>TEXT ROT OVER <> IF E-VERIFY THROW THEN
    THEN
    ?DUP IF 0 DO OVER I + C@ OVER I + C@ <> IF E-VERIFY THROW THEN LOOP THEN
    2DROP
;

INCLUDE bstmt.f
