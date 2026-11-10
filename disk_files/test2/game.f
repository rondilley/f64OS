VARIABLE RVAL
VARIABLE COUNT

\ Get a random value - We grab a random byte from /dev/urandom and then scale it to 1 - max.
\ NOTE: This won't work for any max value > 256. It could be made to work fairly easily just by
\ grabbing more than a single byte from the urandom device, but it works for our purpose...
\ We expect an address into which we want to place the random value, and a maximum value on the stack.
: GetRandom ( addr max -- )
	DUP DUP 0 SWAP !
	S" /dev/urandom" R/O OPEN-FILE
	0= IF
		DUP ROT
		1
		ROT
		READ-FILE
		2DROP
		CLOSE-FILE
		DROP DUP ROT
		1 + 1000 * 
		SWAP @
		* 256000 / 1 + SWAP !
	THEN
;

\ A number guessing game. A proof of concept / example.
: GUESS ( -- )
	." Let's play a guessing game! I'm going to pick a number and you can try to guess it." CR
	CLEARSTACK
	\ Set our guess count to zero
	0 COUNT !
	\ Get a random value 1-100
	100 RVAL GetRandom
	\ The guessing loop...
	BEGIN
		DEPTH 0> IF
			\ If we get here, we've left two values on the stack to compare.
			\ They're NOT equal (or the game would have ended), so we figure out if the guess is too high or too low...
			< IF
				." Too low." CR
			ELSE
				." Too high." CR
			THEN
		THEN
   		." Enter a value between 1 and 100" CR
   		WORD
   		NUMBER
   		DROP DUP DUP
   		\ Check for invalid input...
   		0 <= SWAP 100 > OR IF	\ IF ( GUESS <= 0 ) OR ( GUESS > 100 ) 
   			." That isn't a valid value (1-100)" CR
   			CLEARSTACK
   			\ Leave one set of non-equal values on the stack...
   			0 999
   		ELSE
   			\ Add 1 to our count, pull RVAL onto the stack along with the guess.
   			\ We duplicate them so we can check if the guess is correct, too high or too low...
   			1 COUNT +!
	   		RVAL @
	   		2DUP
   		THEN
   		\ Does the guess equal RVAL?
   		\ If they are equal, we drop out of the loop, congratulate the user, and tell them how many guesses it took...
   		=
   	UNTIL
   	CLEARSTACK
   	." CORRECT! It took you " COUNT @ . ." guesses" CR 
   	." Type GUESS to play again!" CR
;

." Type GUESS to play." CR
