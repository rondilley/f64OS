( f64OS Full-Screen Text Editor - edit.f )
DECIMAL

HERE @ LATEST @
CONSTANT ED-ORIG-LATEST
CONSTANT ED-ORIG-HERE

512   CONSTANT ED-LINES
80    CONSTANT ED-COLS
40960 CONSTANT ED-MAX

ED-MAX ALLOT CONSTANT ED-BUF
ED-MAX ALLOT CONSTANT ED-PACK-BUF
16     ALLOT CONSTANT ED-FNAME

0 VALUE ED-FLEN
0 VALUE ED-CX
0 VALUE ED-CY
0 VALUE ED-TOP
0 VALUE ED-DIRTY
0 VALUE ED-MSG-A
0 VALUE ED-MSG-N

: BLANK-MEM ( addr len -- )
    DUP 0> IF 0 DO 32 OVER I + C! LOOP THEN DROP
;

: ED-MSG ( addr len -- ) TO ED-MSG-N TO ED-MSG-A ;
: ED-LINE ( y -- addr ) ED-COLS * ED-BUF + ;
: ED-ADDR ( x y -- addr ) ED-LINE + ;

: ED-CLEAR ( -- )
    ED-BUF ED-MAX BLANK-MEM
    0 TO ED-CX  0 TO ED-CY  0 TO ED-TOP  0 TO ED-DIRTY
    S" " ED-MSG
;

( Length of line y excluding trailing spaces )
: ED-LLEN ( y -- len )
    ED-LINE ED-COLS
    BEGIN
        DUP 0> IF 2DUP 1- + C@ 32 = ELSE FALSE THEN
    WHILE
        1-
    REPEAT
    NIP
;

( Inverse-video status bar helpers on Row 24: 0xB8000 + 24*160 = 757504 )
0 VALUE SB-X

: SB-EMIT ( c -- )
    SB-X 80 < IF
        757504 SB-X 2 * + C!
        112 757505 SB-X 2 * + C!
        SB-X 1+ TO SB-X
    ELSE
        DROP
    THEN
;

: SB-TYPE ( addr len -- )
    DUP 0> IF 0 DO DUP I + C@ SB-EMIT LOOP THEN DROP
;

: SB-NUM ( u -- )
    10 /MOD ?DUP IF RECURSE THEN 48 + SB-EMIT
;

: ED-DRAW-STATUS ( -- )
    0 TO SB-X
    S"  f64Edit: " SB-TYPE
    ED-FLEN 0> IF ED-FNAME ED-FLEN SB-TYPE ELSE S" [No Name]" SB-TYPE THEN
    ED-DIRTY IF S"  * " SB-TYPE ELSE S"    " SB-TYPE THEN
    S" L:" SB-TYPE ED-CY 1+ SB-NUM
    S"  C:" SB-TYPE ED-CX 1+ SB-NUM
    ED-MSG-N 0> IF S"   " SB-TYPE ED-MSG-A ED-MSG-N SB-TYPE THEN
    BEGIN SB-X 58 < WHILE 32 SB-EMIT REPEAT
    S" TAB:Save  ESC:Forth " SB-TYPE
    BEGIN SB-X 80 < WHILE 32 SB-EMIT REPEAT
;

( Render 23 viewport rows to VGA Rows 1..23: 0xB8000 + 160 = 753824 )
: ED-DRAW ( -- )
    23 0 DO
        ED-TOP I + ED-LINE
        753824 I 160 * +
        80 0 DO
            OVER I + C@  OVER I 2 * + C!
            15 OVER I 2 * + 1+ C!
        LOOP
        2DROP
    LOOP
    ED-DRAW-STATUS
    ED-CX ED-CY ED-TOP - 1+ AT-XY
;

: ED-CLAMP-SCROLL ( -- )
    ED-CY ED-TOP < IF ED-CY TO ED-TOP THEN
    ED-CY ED-TOP 22 + > IF ED-CY 22 - TO ED-TOP THEN
;

( Shift lines y+1..ED-LINES-2 down to y+2..ED-LINES-1 )
: ED-SHIFT-DOWN ( y -- )
    ED-LINES 2 - SWAP -
    DUP 0> IF
        0 DO
            ED-LINES 2 - I - ED-LINE
            ED-LINES 1- I - ED-LINE
            ED-COLS CMOVE
        LOOP
    ELSE
        DROP
    THEN
;

( Shift lines y+1..ED-LINES-1 up into y..ED-LINES-2 )
: ED-SHIFT-UP ( y -- )
    DUP ED-LINES 1- < IF
        ED-LINES 1- SWAP DO
            I 1+ ED-LINE I ED-LINE ED-COLS CMOVE
        LOOP
    ELSE
        DROP
    THEN
    ED-LINES 1- ED-LINE ED-COLS BLANK-MEM
;

: ED-INS-CH ( c -- )
    79 ED-CX > IF
        79 ED-CX - 0 DO
            78 I - ED-CY ED-ADDR C@
            79 I - ED-CY ED-ADDR C!
        LOOP
    THEN
    ED-CX ED-CY ED-ADDR C!
    1 TO ED-DIRTY
    ED-CX 79 < IF ED-CX 1+ TO ED-CX THEN
;

0 VALUE BS-PLEN

: ED-BACKSPACE ( -- )
    ED-CX 0> IF
        ED-CX 1- TO ED-CX
        79 ED-CX > IF
            79 ED-CX - 0 DO
                ED-CX I + 1+ ED-CY ED-ADDR C@
                ED-CX I + ED-CY ED-ADDR C!
            LOOP
        THEN
        32 79 ED-CY ED-ADDR C!
        1 TO ED-DIRTY
    ELSE
        ED-CY 0> IF
            ED-CY 1- ED-LLEN TO BS-PLEN
            ED-COLS BS-PLEN - 0> IF
                ED-CY ED-LINE
                BS-PLEN ED-CY 1- ED-ADDR
                ED-COLS BS-PLEN - CMOVE
            THEN
            ED-CY ED-SHIFT-UP
            ED-CY 1- TO ED-CY
            BS-PLEN 79 > IF 79 ELSE BS-PLEN THEN TO ED-CX
            ED-CLAMP-SCROLL
            1 TO ED-DIRTY
        THEN
    THEN
;

: ED-ENTER ( -- )
    ED-CY ED-LINES 1- < IF
        ED-CY ED-SHIFT-DOWN
        ED-CY 1+ ED-LINE ED-COLS BLANK-MEM
        ED-COLS ED-CX - 0> IF
            ED-CX ED-CY ED-ADDR  ED-CY 1+ ED-LINE  ED-COLS ED-CX - CMOVE
            ED-CX ED-CY ED-ADDR  ED-COLS ED-CX - BLANK-MEM
        THEN
        0 TO ED-CX
        ED-CY 1+ TO ED-CY
        ED-CLAMP-SCROLL
        1 TO ED-DIRTY
    THEN
;

( Load file ED-FNAME / ED-FLEN from ForthFS into ED-BUF )
0 VALUE LD-LBA   0 VALUE LD-SIZE   0 VALUE LD-X   0 VALUE LD-Y

: ED-LOAD ( -- )
    ED-CLEAR
    ED-FLEN 0= IF EXIT THEN
    ED-FNAME ED-FLEN FIND-ENTRY
    ?DUP 0= IF S" [New File]" ED-MSG EXIT THEN
    DUP DE-DIR? IF DROP S" [Is a Dir]" ED-MSG EXIT THEN
    DUP DE-LBA TO LD-LBA
    DE-SIZE TO LD-SIZE
    0 TO LD-X  0 TO LD-Y
    LD-SIZE 0> IF
        LD-SIZE 0 DO
            I 512 /MOD
            OVER 0= IF LD-LBA + SEC-BUF SECTOR@ ELSE DROP THEN
            SEC-BUF + C@
            DUP 10 = IF
                DROP  0 TO LD-X
                LD-Y ED-LINES 1- < IF LD-Y 1+ TO LD-Y THEN
            ELSE DUP 13 = IF
                DROP
            ELSE
                LD-X ED-COLS < IF
                    LD-X LD-Y ED-ADDR C!
                    LD-X 1+ TO LD-X
                ELSE
                    DROP
                THEN
            THEN THEN
        LOOP
    THEN
    S" [Loaded]" ED-MSG
;

( Pack ED-BUF into ED-PACK-BUF and write to ForthFS )
0 VALUE SV-LAST   0 VALUE SV-LEN   0 VALUE SV-LL
0 VALUE SV-SECS   0 VALUE SV-LBA   0 VALUE SV-DE

: ED-SAVE ( -- )
    ED-FLEN 0= IF S" [No Filename!]" ED-MSG EXIT THEN
    0 TO SV-LAST
    ED-LINES 0 DO I ED-LLEN 0> IF I 1+ TO SV-LAST THEN LOOP
    0 TO SV-LEN
    SV-LAST 0> IF
        SV-LAST 0 DO
            I ED-LLEN TO SV-LL
            SV-LL 0> IF
                I ED-LINE ED-PACK-BUF SV-LEN + SV-LL CMOVE
                SV-LEN SV-LL + TO SV-LEN
            THEN
            10 ED-PACK-BUF SV-LEN + C!
            SV-LEN 1+ TO SV-LEN
        LOOP
    THEN
    ED-FNAME ED-FLEN FIND-ENTRY ?DUP IF
        DUP DE-DIR? IF DROP S" [Err: Is Dir]" ED-MSG EXIT THEN
        32 ZERO-MEM  SAVE-DIR
    THEN
    SV-LEN 511 + 512 /  DUP 0= IF DROP 1 THEN
    DUP TO SV-SECS  ALLOC-SECTORS TO SV-LBA
    FREE-ENTRY ?DUP 0= IF S" [Dir Full!]" ED-MSG EXIT THEN
    TO SV-DE
    SV-SECS 0 DO
        SEC-BUF 512 ZERO-MEM
        SV-LEN I 512 * -  DUP 512 > IF DROP 512 THEN
        DUP 0> IF
            ED-PACK-BUF I 512 * +  SEC-BUF  ROT  CMOVE
        ELSE
            DROP
        THEN
        SV-LBA I + SEC-BUF SECTOR!
    LOOP
    ED-FNAME ED-FLEN SV-DE DE-SET-NAME
    SV-LBA SV-DE 16 + !
    SV-LEN SV-DE 24 + !
    SAVE-DIR
    0 TO ED-DIRTY
    S" [Saved]" ED-MSG
;

: SAVE ( -- ) ED-SAVE ." Saved " ED-FNAME ED-FLEN TELL CR ;

: ED-UNLOAD ( -- )
    ED-ORIG-LATEST LATEST !
    ED-ORIG-HERE   HERE !
    ." f64Edit unloaded (" UNUSED . ." cells free)" CR
;

( Main Full-Screen Editor Loop )
: FE ( -- )
    BEGIN
        ED-DRAW
        KEY-RAW
        S" " ED-MSG
        DUP 27 = IF
            DROP CLS
            ." Exited. FE:resume SAVE:save ED-UNLOAD:unload" CR
            EXIT
        THEN
        DUP 9 = OVER 19 = OR IF
            DROP ED-SAVE
        ELSE DUP 128 = IF
            DROP ED-CY 0> IF ED-CY 1- TO ED-CY ED-CLAMP-SCROLL THEN
        ELSE DUP 129 = IF
            DROP ED-CY ED-LINES 1- < IF ED-CY 1+ TO ED-CY ED-CLAMP-SCROLL THEN
        ELSE DUP 130 = IF
            DROP
            ED-CX 0> IF
                ED-CX 1- TO ED-CX
            ELSE ED-CY 0> IF
                ED-CY 1- TO ED-CY
                ED-CY ED-LLEN DUP 79 > IF DROP 79 THEN TO ED-CX
                ED-CLAMP-SCROLL
            THEN THEN
        ELSE DUP 131 = IF
            DROP
            ED-CX 79 < IF
                ED-CX 1+ TO ED-CX
            ELSE ED-CY ED-LINES 1- < IF
                0 TO ED-CX  ED-CY 1+ TO ED-CY  ED-CLAMP-SCROLL
            THEN THEN
        ELSE DUP 132 = IF
            DROP ED-CY 22 > IF ED-CY 22 - TO ED-CY ELSE 0 TO ED-CY
            THEN ED-CLAMP-SCROLL
        ELSE DUP 133 = IF
            DROP ED-CY 22 + DUP ED-LINES 1- > IF DROP ED-LINES 1-
            THEN TO ED-CY ED-CLAMP-SCROLL
        ELSE DUP 8 = OVER 127 = OR IF
            DROP ED-BACKSPACE
        ELSE DUP 10 = OVER 13 = OR IF
            DROP ED-ENTER
        ELSE DUP 32 127 WITHIN IF
            ED-INS-CH
        ELSE
            DROP
        THEN THEN THEN THEN THEN THEN THEN THEN THEN THEN
    AGAIN
;

: EDIT ( "filename" -- )
    WORD
    DUP 16 > IF DROP 16 THEN
    TO ED-FLEN
    ED-FNAME ED-FLEN CMOVE
    ED-LOAD
    FE
;
