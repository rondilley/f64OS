( f64 BASIC V2 - btoken.f: keywords, tokenizer, program lines, LIST )
DECIMAL

( The 76 keywords. Token = 128 + position in this list. )
: KW-SRC ( -- addr len )
    S" END FOR NEXT DATA INPUT# INPUT DIM READ LET GOTO RUN IF RESTORE GOSUB RETURN REM STOP ON WAIT LOAD SAVE VERIFY DEF POKE PRINT# PRINT CONT LIST CLR CMD SYS OPEN CLOSE GET NEW TAB( TO FN SPC( THEN NOT STEP + - * / ^ AND OR > = < SGN INT ABS USR FRE POS SQR RND LOG EXP COS SIN TAN ATN PEEK LEN STR$ VAL ASC CHR$ LEFT$ RIGHT$ MID$ GO"
;
76 CONSTANT NKW
NKW CELLS ALLOT CONSTANT KW-ADDR
NKW CELLS ALLOT CONSTANT KW-LENS
0 VALUE KWN
: INIT-KW ( -- )
    0 TO KWN
    KW-SRC 0 DO
        DUP I + C@ 32 <> IF
            I 0= IF 1 ELSE DUP I + 1- C@ 32 = THEN
            IF
                DUP I + KWN CELLS KW-ADDR + !
                0 KWN CELLS KW-LENS + !
                KWN 1+ TO KWN
            THEN
            1 KWN 1- CELLS KW-LENS + +!
        THEN
    LOOP
    DROP
;
INIT-KW
( Text of the keyword for token t, 128..203 )
: KW-TEXT ( t -- addr len ) 128 - CELLS DUP KW-ADDR + @ SWAP KW-LENS + @ ;

( ---- Tokenizer (CRUNCH). Input: PETSCII line. Output: TBUF, with a 0 at the end. ---- )
256 ALLOT CONSTANT TBUF
0 VALUE TB-LEN
0 VALUE CR-P   0 VALUE CR-REM   0 VALUE CR-DATA
: TB, ( c -- ) TB-LEN 250 < IF TBUF TB-LEN + C! TB-LEN 1+ TO TB-LEN ELSE DROP THEN ;
: CR-ADV ( n -- ) DUP CR-P + TO CR-P CR-REM SWAP - TO CR-REM ;
: CR-COPY ( -- ) CR-P C@ TB, 1 CR-ADV ;
( Does the input at CR-P start with keyword k? )
: KW? ( k -- flag )
    DUP CELLS KW-ADDR + @ C@ CR-P C@ <> IF DROP 0 EXIT THEN
    DUP CELLS KW-LENS + @ DUP CR-REM > IF 2DROP 0 EXIT THEN
    SWAP CELLS KW-ADDR + @
    SWAP 0 DO
        DUP I + C@ CR-P I + C@ <> IF DROP UNLOOP 0 EXIT THEN
    LOOP
    DROP 1
;
: KW-FIND ( -- k | -1 )
    NKW 0 DO I KW? IF I UNLOOP EXIT THEN LOOP -1
;
: CR-QUOTED ( -- )
    CR-COPY
    BEGIN CR-REM 0> IF CR-P C@ 34 <> ELSE 0 THEN WHILE CR-COPY REPEAT
    CR-REM 0> IF CR-COPY THEN
;
: CR-STEP ( -- )
    CR-P C@
    DUP 34 = IF DROP CR-QUOTED EXIT THEN
    CR-DATA IF 58 = IF 0 TO CR-DATA THEN CR-COPY EXIT THEN
    DUP 32 = IF DROP CR-COPY EXIT THEN
    DUP 63 = IF DROP 153 TB, 1 CR-ADV EXIT THEN
    DUP 128 >= SWAP 48 60 WITHIN OR IF CR-COPY EXIT THEN
    KW-FIND DUP 0< IF DROP CR-COPY EXIT THEN
    DUP 128 + TB,
    DUP CELLS KW-LENS + @ CR-ADV
    DUP 15 = IF BEGIN CR-REM 0> WHILE CR-COPY REPEAT THEN
    3 = IF 1 TO CR-DATA THEN
;
: CRUNCH ( addr len -- )
    TO CR-REM TO CR-P 0 TO TB-LEN 0 TO CR-DATA
    BEGIN CR-REM 0> WHILE CR-STEP REPEAT
    0 TB,
;

( ---- Program text: C64 format at $0801. Each line: link, number, tokens, 0 ---- )
( The program ends with a link of 0. VARTAB [45/46] is the first byte after it. )
2049 CONSTANT TXTTAB
: VARTAB@ ( -- c64 ) 45 MW@ ;
: VARTAB! ( c64 -- ) 45 MW! ;
: NEW-PROG ( -- ) 0 2048 M! 0 2049 M! 0 2050 M! 2051 VARTAB! ;
( First line with number >= n. found = 1 if its number is n. )
: FIND-LINE ( n -- c64 found )
    TXTTAB
    BEGIN
        DUP MW@
    WHILE
        DUP 2 + MW@ 2 PICK >= IF DUP 2 + MW@ ROT = EXIT THEN
        MW@
    REPEAT
    NIP 0
;
: RELINK ( -- )
    TXTTAB
    BEGIN
        DUP MW@
    WHILE
        DUP 4 + BEGIN DUP M@ WHILE 1+ REPEAT 1+
        TUCK SWAP MW!
    REPEAT
    DROP
;
0 VALUE PL-A
0 VALUE PL-SIZE
: DELETE-LINE ( c64 -- )
    TO PL-A
    PL-A MW@ PL-A - TO PL-SIZE
    PL-A PL-SIZE + MEM +  PL-A MEM +  VARTAB@ PL-A - PL-SIZE -  CMOVE
    VARTAB@ PL-SIZE - VARTAB!
    RELINK
;
( Put the line in TBUF into the program as line n, at address c64 )
: INSERT-LINE ( n c64 -- )
    TO PL-A
    TB-LEN 4 + TO PL-SIZE
    VARTAB@ PL-SIZE + 40960 > IF E-MEM THROW THEN
    PL-A MEM + DUP PL-SIZE + VARTAB@ PL-A - CMOVE>
    1 PL-A MW!
    PL-A 2 + MW!
    TBUF PL-A 4 + MEM + TB-LEN CMOVE
    VARTAB@ PL-SIZE + VARTAB!
    RELINK
;
( Store TBUF as line n. An empty line deletes line n. )
: STORE-LINE ( n -- )
    DUP FIND-LINE IF DUP DELETE-LINE THEN
    TB-LEN 1 > IF INSERT-LINE ELSE 2DROP THEN
;

( ---- LIST. LOUT is CHROUT until bio.f sets it to BOUT. ---- )
: PNUM ( u -- ) 10 /MOD ?DUP IF RECURSE THEN 48 + CHROUT ;
VARIABLE 'LOUT
XT' CHROUT 'LOUT !
: LOUT ( c -- ) 'LOUT @ EXECUTE ;
: LNUM ( u -- ) 10 /MOD ?DUP IF RECURSE THEN 48 + LOUT ;
: LTYPE ( addr len -- ) DUP 0> IF 0 DO DUP I + C@ LOUT LOOP ELSE DROP THEN DROP ;
: LIST-LINE ( c64 -- )
    DUP 2 + MW@ LNUM 32 LOUT
    4 + MEM +
    0 SWAP                         ( inquote addr )
    BEGIN
        DUP C@
    WHILE
        DUP C@
        DUP 34 = IF ROT 0= -ROT THEN
        DUP 128 204 WITHIN 3 PICK 0= AND IF
            KW-TEXT LTYPE
        ELSE
            LOUT
        THEN
        1+
    REPEAT
    2DROP
    13 LOUT
;

( ---- Text pointer. TXTPTR is a real address in the program or the direct line. ---- )
0 VALUE TXTPTR
: PEEKC ( -- c ) BEGIN TXTPTR C@ 32 = WHILE TXTPTR 1+ TO TXTPTR REPEAT TXTPTR C@ ;
: NEXTC ( -- ) TXTPTR 1+ TO TXTPTR ;
: GETC ( -- c ) PEEKC NEXTC ;
: EXPECT ( c -- ) PEEKC = IF NEXTC ELSE SYNERR THEN ;
: LETTER? ( c -- flag ) 65 91 WITHIN ;
: ALNUM? ( c -- flag ) DUP DIGIT? SWAP LETTER? OR ;
( Line number. No digits gives 0. )
: LINGET ( -- n )
    0
    BEGIN
        PEEKC DIGIT?
    WHILE
        10 * PEEKC 48 - + NEXTC
        DUP 63999 > IF SYNERR THEN
    REPEAT
;
( End of statement: 0 or colon )
: EOS? ( -- flag ) PEEKC DUP 0= SWAP 58 = OR ;
( Move TXTPTR to the end of the statement, past strings )
: SKIP-STMT ( -- )
    0
    BEGIN
        TXTPTR C@ DUP 0<>
    WHILE
        DUP 34 = IF DROP 0= ELSE 58 = OVER 0= AND IF DROP EXIT THEN THEN
        NEXTC
    REPEAT
    2DROP
;
( Move TXTPTR to the 0 at the end of the line )
: SKIP-LINE ( -- ) BEGIN TXTPTR C@ WHILE NEXTC REPEAT ;

INCLUDE beval.f
