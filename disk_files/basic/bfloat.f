( f64 BASIC V2 - bfloat.f: number conversion, parse and print )
( A number is an IEEE double in one cell. See bnative.f for F+ F- F* F/ etc. )
DECIMAL

0 S>F  CONSTANT F0
1 S>F  CONSTANT F1
10 S>F CONSTANT F10
F1 2 S>F F/ CONSTANT FHALF
5179139571476070400 CONSTANT FMAXBITS   ( 1.70141183E+38, the C64 limit )
4030721666501106018 CONSTANT FMINBITS   ( 2.93873588E-39 )

: F0= ( f -- flag ) 1 LSHIFT 0= ;
: F0< ( f -- flag ) DUP F0= IF DROP 0 ELSE 0< THEN ;
: F= ( a b -- flag ) FCMP 0= ;
: F< ( a b -- flag ) FCMP 0< ;
: F> ( a b -- flag ) FCMP 0> ;
( Sign of f as -1, 0 or 1 )
: FSGN ( f -- n ) DUP F0= IF DROP 0 ELSE 0< IF -1 ELSE 1 THEN THEN ;

( Check a result: overflow gives ?OVERFLOW ERROR, very small numbers give 0 )
: FCHK ( f -- f )
    DUP FABS DUP FMAXBITS > IF E-OVER THROW THEN
    FMINBITS < IF DROP F0 THEN
;

( Floor to an integer cell. Large values give ?ILLEGAL QUANTITY. )
: F>INT ( f -- n )
    FFLOOR DUP FABS 4877398396442247168 > IF ILLQ THEN   ( 2^60 )
    FROUND>S
;
( Integer in -32768..32767, as for AND OR NOT and integer variables )
: F>I16 ( f -- n ) F>INT DUP -32768 32768 WITHIN 0= IF ILLQ THEN ;
( Address 0..65535 and byte 0..255 )
: F>ADDR ( f -- n ) F>INT DUP 0 65536 WITHIN 0= IF ILLQ THEN ;
: F>BYTE ( f -- n ) F>INT DUP 0 256 WITHIN 0= IF ILLQ THEN ;

( Powers of ten. 10^0 .. 10^22 are exact. )
23 CELLS ALLOT CONSTANT P10TAB
: INIT-P10 ( -- ) F1 23 0 DO DUP P10TAB I CELLS + ! F10 F* LOOP DROP ;
INIT-P10
: P10 ( n -- f ) DUP 0 23 WITHIN IF CELLS P10TAB + @ ELSE F10^ THEN ;
( f * 10^n )
: FSCALE10 ( f n -- f )
    DUP 0< IF NEGATE P10 F/ ELSE P10 F* THEN
;

( ---- Parse a number. The parser reads from PP; PE is the end. ---- )
( Spaces are skipped, as the C64 does. The tokens for + and - are accepted. )
0 VALUE PP
0 VALUE PE
: PC ( -- c )
    BEGIN
        PP PE < IF PP C@ 32 = ELSE 0 THEN
    WHILE
        PP 1+ TO PP
    REPEAT
    PP PE < IF PP C@ ELSE 0 THEN
;
: PADV ( -- ) PP 1+ TO PP ;
: DIGIT? ( c -- flag ) 48 58 WITHIN ;
: MINUS? ( c -- flag ) DUP 45 = SWAP 171 = OR ;
: PLUS? ( c -- flag ) DUP 43 = SWAP 170 = OR ;

0 VALUE FN-MANT
0 VALUE FN-NDIG
0 VALUE FN-EXP
0 VALUE FN-NEG
: FN-DIGIT ( d -- )   ( add one digit to the mantissa )
    FN-NDIG 18 < IF
        FN-MANT 10 * + TO FN-MANT
        FN-MANT 0<> IF FN-NDIG 1+ TO FN-NDIG THEN
    ELSE
        DROP FN-EXP 1+ TO FN-EXP
    THEN
;
( Parse a number at PP. Gives 0 if there are no digits. )
: FIN ( -- f )
    0 TO FN-MANT 0 TO FN-NDIG 0 TO FN-EXP 0 TO FN-NEG
    PC MINUS? IF PADV 1 TO FN-NEG ELSE PC PLUS? IF PADV THEN THEN
    BEGIN PC DIGIT? WHILE PC 48 - FN-DIGIT PADV REPEAT
    PC 46 = IF
        PADV
        BEGIN
            PC DIGIT?
        WHILE
            FN-NDIG 18 < IF PC 48 - FN-DIGIT FN-EXP 1- TO FN-EXP THEN
            PADV
        REPEAT
    THEN
    PC 69 = IF
        PADV
        0 PC MINUS? IF PADV DROP 1 ELSE PC PLUS? IF PADV THEN THEN
        0 BEGIN PC DIGIT? WHILE 10 * PC 48 - + 999 MIN PADV REPEAT
        SWAP IF NEGATE THEN
        FN-EXP + TO FN-EXP
    THEN
    FN-MANT S>F
    FN-MANT 0<> IF FN-EXP FSCALE10 THEN
    FN-NEG IF FNEGATE THEN
    FCHK
;
( Parse a number from a string. Gives the number and the count of characters used. )
: STR>F ( addr len -- f used )
    OVER + TO PE DUP TO PP FIN SWAP PP SWAP -
;

( ---- Print a number in C64 format ---- )
( Leading space or minus sign. 9 digits. Scientific outside 0.01 .. 999999999 )
32 ALLOT CONSTANT NBUF
0 VALUE NB-LEN
16 ALLOT CONSTANT NDIG
0 VALUE ND-LEN
0 VALUE FO-E
: NB-C ( c -- ) NBUF NB-LEN + C! NB-LEN 1+ TO NB-LEN ;
( Put the digits of n, 9 digits with zeros at the left, into NDIG )
: NDIG9 ( n -- )
    9 0 DO 10 /MOD SWAP 48 + NDIG 8 I - + C! LOOP DROP
    9 TO ND-LEN
    BEGIN ND-LEN 1 > IF NDIG ND-LEN 1- + C@ 48 = ELSE 0 THEN
    WHILE ND-LEN 1- TO ND-LEN REPEAT
;
: ND@ ( i -- c ) DUP ND-LEN < IF NDIG + C@ ELSE DROP 48 THEN ;
( Positive non-zero f: set FO-E and NDIG )
: FO-DIGITS ( f -- )
    DUP FLOG10 FFLOOR FROUND>S TO FO-E
    DUP 8 FO-E - FSCALE10 FROUND>S
    DUP 1000000000 >= IF
        DROP FO-E 1+ TO FO-E DUP 8 FO-E - FSCALE10 FROUND>S
    THEN
    DUP 100000000 < IF
        DROP FO-E 1- TO FO-E DUP 8 FO-E - FSCALE10 FROUND>S
    THEN
    DUP 1000000000 >= IF 10 / FO-E 1+ TO FO-E THEN
    NIP NDIG9
;
: FO-FIXED ( -- )
    FO-E 0< IF
        46 NB-C
        FO-E NEGATE 1- ?DUP IF 0 DO 48 NB-C LOOP THEN
        ND-LEN 0 DO I ND@ NB-C LOOP
    ELSE
        FO-E 1+ 0 DO I ND@ NB-C LOOP
        ND-LEN FO-E 1+ > IF
            46 NB-C
            ND-LEN FO-E 1+ DO I ND@ NB-C LOOP
        THEN
    THEN
;
: FO-SCI ( -- )
    0 ND@ NB-C
    ND-LEN 1 > IF 46 NB-C ND-LEN 1 DO I ND@ NB-C LOOP THEN
    69 NB-C
    FO-E 0< IF 45 NB-C ELSE 43 NB-C THEN
    FO-E ABS 10 /MOD 48 + NB-C 48 + NB-C
;
( Number to string: leading space or minus, no trailing space )
: FOUT ( f -- addr len )
    0 TO NB-LEN
    DUP F0< IF 45 NB-C FABS ELSE 32 NB-C THEN
    DUP F0= IF
        DROP 48 NB-C
    ELSE
        FO-DIGITS
        FO-E -2 9 WITHIN IF FO-FIXED ELSE FO-SCI THEN
    THEN
    NBUF NB-LEN
;

INCLUDE bscreen.f
