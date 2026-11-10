\ predicate: is n prime?
\ stack effect: ( n -- ? )
: prime?
  3 ( n iterator )
  begin
    2dup dup * >=       \ check if iterator^2 <= n
  while
    2dup mod 0= if 2drop 0 exit then
    2 +                 \ increment iterator by 2 (skip evens)
  repeat
  2drop -1              \ clean stack and return true (-1)
;

\ driver: print primes up to limit
\ stack effect: ( limit -- )
: primes
  2 . cr
  1+ 3 do               \ loop from 2 to limit (inclusive)
    i prime? if i . cr then
  2 +loop 
;

10000 primes
