( f64 BASIC V2 - basic.f: loader, helpers and memory map )
( Load with: CD basic  INCLUDE basic.f   Then type: BASIC )
( The files load in a chain. Each file INCLUDEs the next one on its last line: )
( basic.f bnative.f bfloat.f bscreen.f btoken.f beval.f bstmt.f bio.f bmain.f )
DECIMAL

HERE @ LATEST @
CONSTANT B-ORIG-LATEST
CONSTANT B-ORIG-HERE

( Interpret-mode tick: XT' FOO gives the execution token of FOO )
: XT' ( "name" -- xt ) WORD FIND >CFA ;

( CODE name starts a machine-code word. M, adds hex bytes to it. )
( The machine code goes into its own memory, not into the dictionary. QEMU )
( runs code slowly when data that changes is in the same page as the code. )
83886080 CONSTANT CODEMEM      ( 80 MiB )
CODEMEM VALUE CODE-HERE
: CB, ( byte -- ) CODE-HERE C! CODE-HERE 1+ TO CODE-HERE ;
: HEXDIG ( c -- n ) DUP 58 < IF 48 - ELSE 55 - THEN ;
: M, ( "hex" -- )
    WORD
    DUP 0> IF
        0 DO
            DUP I + C@ HEXDIG 16 *
            OVER I + 1+ C@ HEXDIG + CB,
        2 +LOOP
    ELSE
        DROP
    THEN
    DROP
;
: CODE ( "name" -- ) WORD CREATE CODE-HERE , ;

( Memory map. BASIC uses RAM from 64 MiB to 81 MiB. QEMU must have -m 128M. )
67108864 CONSTANT MEM          ( 64 KiB C64 address space, $0000-$FFFF )
67174400 CONSTANT SHEAP-A      ( string heap, half A: 512 KiB )
67698688 CONSTANT SHEAP-B      ( string heap, half B: 512 KiB )
524288   CONSTANT SHEAP-SIZE
68222976 CONSTANT TMPSTR       ( temporary strings: 256 KiB )
262144   CONSTANT TMPSTR-SIZE
68485120 CONSTANT VARTAB-A     ( simple variables: 2886 slots of 16 bytes )
68550656 CONSTANT ARRTAB-A     ( array pointers: 2886 cells )
68616192 CONSTANT FNTAB-A      ( DEF FN table: 962 entries of 16 bytes )
68681728 CONSTANT CHARROM      ( 4 KiB character generator )
68685824 CONSTANT VGASAVE      ( saved text mode: font, screen, palette )
69206016 CONSTANT ARRHEAP      ( array data: 8 MiB )
8388608  CONSTANT ARRHEAP-SIZE
77594624 CONSTANT CHANBUF      ( file channel buffers: 16 x 256 KiB )
262144   CONSTANT CHANBUF-SIZE
81788928 CONSTANT LOADBUF      ( LOAD and SAVE buffer: 1 MiB )
1048576  CONSTANT LOADBUF-SIZE

( C64 memory access )
: M@ ( c64addr -- byte ) MEM + C@ ;
: M! ( byte c64addr -- ) MEM + C! ;
: MW@ ( c64addr -- u16 ) MEM + W@ ;
: MW! ( u16 c64addr -- ) MEM + W! ;

( BASIC error numbers. THROW with one of these stops the program. )
1  CONSTANT E-FILES      2  CONSTANT E-FOPEN      3  CONSTANT E-FNOPEN
4  CONSTANT E-FNFOUND    5  CONSTANT E-DEVICE     6  CONSTANT E-NOTIN
7  CONSTANT E-NOTOUT     8  CONSTANT E-NONAME     9  CONSTANT E-ILLDEV
10 CONSTANT E-NEXT       11 CONSTANT E-SYNTAX     12 CONSTANT E-RETURN
13 CONSTANT E-DATA       14 CONSTANT E-ILLQ       15 CONSTANT E-OVER
16 CONSTANT E-MEM        17 CONSTANT E-UNDEF      18 CONSTANT E-SUBS
19 CONSTANT E-REDIM      20 CONSTANT E-DIV0       21 CONSTANT E-DIRECT
22 CONSTANT E-TYPE       23 CONSTANT E-LONG       24 CONSTANT E-FDATA
25 CONSTANT E-COMPLEX    26 CONSTANT E-CONT       27 CONSTANT E-UNDFN
28 CONSTANT E-VERIFY     29 CONSTANT E-LOAD       30 CONSTANT E-BREAK
( Codes above 30 are not errors: they stop the program without a message )
99 CONSTANT E-END

: ERR ( n -- ) THROW ;
: SYNERR ( -- ) E-SYNTAX THROW ;
: ILLQ ( -- ) E-ILLQ THROW ;
: ABS ( n -- u ) DUP 0< IF NEGATE THEN ;

INCLUDE bnative.f
