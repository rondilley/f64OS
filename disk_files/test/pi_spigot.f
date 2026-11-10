: ARRAY ( size -- )
    CELLS ALLOT ( allocate "size" cells of memory, push the pointer)
                ( to this memory )
    WORD CREATE ( make the dictionary entry ( the name follows ARRAY ) )
    DOCOL ,     ( append DOCOL (the codeword field of this word) )
    ' LIT ,     ( append the codeword LIT )
    ,           ( append the pointer to the new memory )
    ' EXIT ,    ( append the codeword EXIT )
;

1000 CONSTANT DIGITS
3350 CONSTANT ARRAY_SIZE

VARIABLE PREDIGIT
VARIABLE NINES

ARRAY_SIZE ARRAY PI

: PRINT-PREDIGIT ( n -- )
    DUP 10 =                ( Overflow case )
    IF
        DROP
        PREDIGIT @ 1+ .     ( Print incremented predigit )
        NINES @ 0 >         ( If we're "holding" nines, )
                            ( they now become zeros )
        IF
            NINES @ 0 DO 
                0 .         ( Print our nines as zeros )
            LOOP
        THEN
        0 PREDIGIT !
        0 NINES !
    ELSE
        DUP 9 =             ( Nine case - we "hold" these )
        IF
            DROP
            1 NINES +!      ( Increment NINES )
        ELSE                ( Normal case )
            PREDIGIT @ .    ( Print the digit )
            NINES @ 0 >     ( Print out any "held" nines )
            IF
                NINES @ 0 
                    DO 9 . 
                LOOP
            THEN    
            PREDIGIT !      ( Store the incoming value )
            0 NINES !       ( Reset NINES )
        THEN 
    THEN
;

: COMPUTE-PI ( -- )
    PI ARRAY_SIZE CELLS + PI ( Initialize our array )
    DO
        2 I !
    1 CELLS +LOOP
    0 NINES !
    0 PREDIGIT !
    DIGITS 0 DO
        0                       ( Initial carry )
        ARRAY_SIZE 0 DO 
            ARRAY_SIZE I 1 + -  ( Calculate our array offset j )
            DUP                 ( Keep a copy for later )
            CELLS PI +          ( Offset to PI[j] )
            @ 10 *              ( 10 * PI[j] )
            ROT
            +                   ( Add carry )
            SWAP
            DUP
            0<> 
            IF
                DUP
                2 * 1 +
                ROT
                SWAP
                /MOD
                ROT
                DUP
                -ROT
                *
                -ROT
                CELLS PI + !    ( store remainder back into PI[j] )
            ELSE                ( we're at the beginning of the array, )
                                ( time to chunk out a digit of pi )
                SWAP
                10 /MOD         ( we want the tens digit - and a remainder )
                SWAP
                PI !            ( store the remainder back in PI[0] )
                SWAP
                DROP
                J 0<>
                IF
                    PRINT-PREDIGIT
                ELSE
                    PREDIGIT !  ( store the value as PREDIGIT )
                THEN
            THEN
        LOOP
    LOOP
    1 PRINT-PREDIGIT    ( print out the hanging value )
                        ( note, this won't always work correctly )
                        ( we might need a backtrack )
    CR
;

COMPUTE-PI
