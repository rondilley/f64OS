( fibonacci sequence )
: FIBONACCI ( n -- )
    DUP 2 - 0< IF ." Iteration count must be > 2" CR QUIT THEN
    2 -
    1 1 2DUP . CR . CR
    ROT
    BEGIN
        DUP 0>
    WHILE
        -ROT
        2DUP +
        DUP . CR
        -ROT DROP
        ROT
        1-
    REPEAT
    2DROP DROP
;

83 FIBONACCI
