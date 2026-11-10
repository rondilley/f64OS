\ Count to 1,000,000,000
\ This is ~14x slower than a similarly hand-coded
\ assembly language version. This is caused by having
\ to deal with the stack-based nature of Forth. We have
\ to duplicate our value in order to do the comparison,
\ so there's pops and pushes happening in Forth, where
\ there isn't in straight-up assembler. There is also a
\ lot of overhead due to the threaded interpretive nature
\ of Forth, jumping around through the defined words. I'm
\ actually pleasantly surprised it's only 14 times slower.

: COUNT
	1000000000
	BEGIN
		1-
		DUP
		0=
	UNTIL
;

COUNT
." Done!" CR
