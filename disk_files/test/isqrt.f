: isqrt ( u -- u )
    dup 0= if exit then    \ handle 0 edge case quickly
    0 >r                   \ r: root accumulator
    \ start with the highest power of 4 that fits in a 64-bit cell.
    \ value is 1 << 62 (hex: 4000000000000000)
    4611686018427387904    \ stack: rem bit
    begin
        dup 0<>            \ loop while bit != 0
    while
        2dup r@ + >= if    \ if (rem >= root + bit)
            2dup r@ + -    \ stack: rem bit new-rem
            rot drop       \ stack: bit new-rem (drops old rem)
            swap           \ stack: new-rem bit
            r> 2 /         \ root = root / 2
            over + >r      \ root = root + bit. push back to r stack.
        else
            r> 2 / >r      \ root = root / 2
        then
        4 /                \ bit = bit / 4
    repeat
    drop drop              \ clean up rem and bit
    r>                     \ return result
;

141742885093678969 isqrt . cr
