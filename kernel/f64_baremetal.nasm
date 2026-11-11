BITS 64 ; 64 bits.
CPU X64 ; Target the x86_64 family of CPUs.

; This will be a pretty straightforward translation of JonesForth assembly (x86) into x64 assembly.
; I'll follow the code itself and unabashedly steal some of the comments from Richard W.M. Jones'
; <rich@annexia.org> version. If that's an issue, he shouldn't have made it Public Domain. ;-)

%assign F64_VERSION 1

%define RETURN_STACK_SIZE 8192	         ; return stack depth
%define ITERATOR_STACK_SIZE 8192         ; return stack depth
%define BUFFER_SIZE 4096	         ; input buffer size

F64_DATA_START equ 0x200000
F64_DATA_END   equ 0x400000

cur_dsp dq 0

; The NEXT Word as a macro
%macro NEXT 0
        mov [cur_dsp], rsp
        mov rax, [rsi]
        add rsi, 8
        jmp [rax]
%endmacro

; Macros to deal with the return stack.
%macro PUSHRSP 1
        lea rbp, [rbp-8]
        mov [rbp], %1
%endmacro

%macro POPRSP 1
        mov %1, [rbp]
        lea rbp, [rbp+8]
%endmacro

; Macros to deal with the iterator stack.
%macro PUSHITR 1
        lea r15, [r15-8]
        mov [r15], %1
%endmacro

%macro POPITR 1
        mov %1, [r15]
        lea r15, [r15+8]
%endmacro

;	And with that we can now talk about the interpreter.
;
;	In FORTH the interpreter function is often called DOCOL (I think it means "DO COLON" because
;	all FORTH definitions start with a colon, as in : DOUBLE DUP + ;
;
;	The "interpreter" (it's not really "interpreting") just needs to push the old %rsi on the
;	stack and set %rsi to the first word in the definition.  Remember that we jumped to the
;	function using JMP [%rax]?  Well a consequence of that is that conveniently %rax contains
;	the address of this codeword, so just by adding 8 to it we get the address of the first
;	data word.  Finally after setting up %rsi, it just does NEXT which causes that first word
;	to run.

DOCOL:
        PUSHRSP rsi
        add rax, 8
        mov rsi, rax
        NEXT

f64_start:
        cld                             ; Clear direction flag
        mov [var_S0], rsp
        mov rbp, return_stack_top       ; Initialize the return stack
        mov r15, iterator_stack_top     ; Initialize the iterator stack
        call set_up_data_segment
        mov rsi, cold_start
        NEXT                            ; Launch Forth!

exit_with_grace_and_beauty:
        call _FLUSH_EMIT
.halt:
        hlt
        jmp .halt

cold_start:
        dq QUIT
f64_source:     
        db "/usr/include/f64/f64.fs"
f64_source_end: 
        db 0h
loadf64_fail_msg: 
        db "ERROR Could not open '"
loadf64_fail_msg_end:
loadf64_fail_msg2: 
        db "'."
        db `\n`
loadf64_fail_msg_end2:

; Various flags for the dictionary word header
%define F_IMMED   0x80
%define F_HIDDEN  0x20
%define F_LENMASK 0x1f

; Holds previously defined word
; Starts as null/zero
%define link 0

; Macro for defining forth word
;
;     defword name, label, flag
;
%macro defword 2-3 0
        %strlen name_len %1

        ; dictionary word header
        align 8, db 0
        name_%2:
                dq link
                db name_len + %3
                db %1

        ; update link to point to this word's header
        %define link name_%2

        ; word definitions, starts with DOCOL
        align 8, db 0
        %2:
                dq DOCOL
%endmacro


; Macro for defining native word
;
;     defcode name, label, flag
;
%macro defcode 2-3 0
        %strlen name_len %1

        ; dictionary word header
        align 8, db 0
        name_%2:
                dq link
                db name_len + %3
                db %1

        ; update link to point to this word's header
        %define link name_%2

        ; word definition, link to the native code
        align 8, db 0
        $%2:
                dq code_%2

        ; native code
        align 8, db 0
        code_%2:
%endmacro

defcode "DROP", DROP ; drop top of stack
        pop rax
        NEXT

defcode "SWAP", SWAP; swap the top two stack elements
        mov rax, [rsp]
        mov rbx, [rsp+8]
        mov [rsp], rbx
        mov [rsp+8], rax
        NEXT

defcode "DUP", DUP ; duplicate top of stack
        mov rax, [rsp]
        push rax
        NEXT

defcode "OVER", OVER ; get the 2nd element from stack and push it onto the top
        mov rax, [rsp+8]
        push rax
        NEXT

defcode "ROT", ROT ; rotate the stack: a, b, c => c, a, b
        mov rax, [rsp]
        mov rbx, [rsp+8]
        mov rcx, [rsp+16]
        mov [rsp+16], rbx
        mov [rsp+8], rax
        mov [rsp], rcx
        NEXT

defcode "-ROT", NROT ; negate a stack ROT: c, a, b => a, b, c 
        mov rax, [rsp]
        mov rbx, [rsp+8]
        mov rcx, [rsp+16]
        mov [rsp+16], rax
        mov [rsp+8], rcx
        mov [rsp], rbx
        NEXT

defcode "2DROP", TWODROP ; drop top two elements of stack
        add rsp, 16
        NEXT

defcode "2DUP", TWODUP ; duplicate top two elements of stack
        mov rax, [rsp]
        mov rbx, [rsp+8]
        push rbx
        push rax
        NEXT

defcode "2SWAP", TWOSWAP ; swap top two pairs of elements of stack
        mov rax, [rsp]
        mov rbx, [rsp+8]
        mov rcx, [rsp+16]
        mov rdx, [rsp+24]
        mov [rsp], rcx
        mov [rsp+8], rdx
        mov [rsp+16], rax
        mov [rsp+24], rbx
        NEXT

defcode "?DUP", QDUP ; duplicate top of stack if non-zero
        mov rax, [rsp]
        test rax, rax
        jz .next
        push rax
.next   NEXT

defcode "1+", INCR ; increment top of stack
        inc qword [rsp]
        NEXT

defcode "1-", DECR ; decrement top of stack
        dec qword [rsp]
        NEXT

defcode "8+", INCR8 ; add 8 to the top of the stack
        add qword [rsp], 8
        NEXT

defcode "8-", DECR8 ; subtract 8 from the top of the stack
        sub qword [rsp], 8
        NEXT

defcode "+", ADD ; get the top of the stack and add it to the next value on the stack
        pop rax
        add [rsp], rax
        NEXT

defcode "-", SUB ; get the top of the stack and subtract if from the next value on the stack
        pop rax
        sub [rsp], rax
        NEXT

defcode "*", MUL ; get the top of the stack and multiply it by the next value on the stack (ignore overflow)
        pop rax
        imul rax, [rsp]
        mov [rsp], rax
        NEXT

;	In this FORTH, only /MOD is primitive.  Later we will define the / and MOD words in
;	terms of the primitive /MOD.  The design of the x64 assembly instruction idiv which
;	leaves both quotient and remainder makes this the obvious choice.

defcode "/MOD", DIVMOD
        pop rbx
        pop rax
        cqo
        idiv rbx
        push rdx
        push rax
        NEXT

; All of the comparisons are special cases of this same idiom, just changing the "set" version
; so we can just use a new macro...

%macro defcmp 3
        defcode %1, %2
                pop rax
                cmp [rsp], rax
                set%+3 al
                movzx rax, al
                mov [rsp], rax
                NEXT
%endmacro

defcmp "=",  EQU, e
defcmp "<>", NEQ, ne
defcmp "<",  LT,  l
defcmp ">",  GT,  g
defcmp "<=", LE,  le
defcmp ">=", GE,  ge

; We can do the same "new macro" trick for tests...

%macro deftest 3
        defcode %1, %2
                cmp qword [rsp], 0
                set%+3 al
                movzx rax, al
                mov [rsp], rax
                NEXT
%endmacro

deftest "0=",  ZEQU,  z
deftest "0<>", ZNEQU, nz
deftest "0<",  ZLT,   l
deftest "0>",  ZGT,   g
deftest "0<=", ZLE,   le
deftest "0>=", ZGE,   ge

; bitwise AND, OR, XOR, and NOT

defcode "AND", AND
        pop rax
        and [rsp], rax
        NEXT

defcode "OR", OR
        pop rax
        or [rsp], rax
        NEXT

defcode "XOR", XOR
        pop rax
        xor [rsp], rax
        NEXT

defcode "INVERT", INVERT
        not qword [rsp]
        NEXT

; Exiting from a Word

defcode "EXIT", EXIT
        POPRSP rsi
        NEXT

; Literal - this is how we can have literal values in Forth code

defcode "LIT", LIT
        lodsq
        push rax
        NEXT

; Memory manipulation Words

defcode "!", STORE
        pop rbx
        pop rax
        mov [rbx], rax
        NEXT

defcode "@", FETCH
        pop rbx
        mov rax, [rbx]
        push rax
        NEXT

defcode "+!", ADDSTORE
        pop rbx
        pop rax
        add [rbx], rax
        NEXT

defcode "-!", SUBSTORE
        pop rbx
        pop rax
        sub [rbx], rax
        NEXT

;	! and @ (STORE and FETCH) store 64-bit words.  It's also useful to be able to read and write bytes
;	so we also define standard words C@ and C!.

defcode "C!", STOREBYTE
        pop rbx
        pop rax
        mov [rbx], al
        NEXT

defcode "C@", FETCHBYTE
        pop rbx
        xor rax, rax
        mov al, [rbx]
        push rax
        NEXT

; C@C! is a useful byte copy primitive.

defcode "C@C!", CCOPY
        mov rbx, [rsp+8]
        mov al, [rbx]
        pop rdi
        stosb
        push rdi
        inc qword [rsp+8]
        NEXT

; and CMOVE is a block copy operation.

defcode "CMOVE", CMOVE
        mov rdx, rsi
        pop rcx
        pop rdi
        pop rsi
        rep movsb
        mov rsi, rdx
        NEXT

; Now... we need a way to specify built-in variables. This macro handles that and also allows initialization

%macro defvar 2-4 0, 0
        defcode %1, %2, %4
                push var_%2
                NEXT

        ;; data storage
        align 8, db 0
        var_%2:
                dq %3
%endmacro

defvar "STATE", STATE
defvar "HERE", HERE
defvar "LATEST", LATEST, name_GET_BRK
defvar "S0", S0
defvar "BASE", BASE, 10

; and we need a way to create constants...

%macro defconst 3-4 0
        defcode %1, %2, %4
                push %3
                NEXT
%endmacro

defconst "VERSION", VERSION, F64_VERSION
defconst "R0", R0, return_stack_top
defconst "DOCOL", __DOCOL, DOCOL

defconst "F_IMMED",   __F_IMMED,   F_IMMED
defconst "F_HIDDEN",  __F_HIDDEN,  F_HIDDEN
defconst "F_LENMASK", __F_LENMASK, F_LENMASK

; Words for manipulating the RETURN stack

defcode ">R", TOR
        pop rax
        PUSHRSP rax
        NEXT

defcode "R>", FROMR
        POPRSP rax
        push rax
        NEXT

defcode "R@", RFETCH
        mov rax, [rbp]
        push rax
        NEXT

defcode "RSP@", RSPFETCH
        push rbp
        NEXT

defcode "RSP!", RSPSTORE
        pop rbp
        NEXT

defcode "RDROP", RDROP
        add rbp, 8
        NEXT

; Words for manipulating the ITERATOR stack

defcode ">ITR", TOITR
        pop rax
        PUSHITR rax
        NEXT

defcode "ITR>", FROMITR
        POPITR rax
        push rax
        NEXT

defcode "ITR@", ITRFETCH
        mov rax, [r15]
        push rax
        NEXT

defcode "ITRSP@", ITRSPFETCH
        push r15
        NEXT

defcode "ITRRSP!", ITRSPSTORE
        pop r15
        NEXT

defcode "ITRDROP", ITRDROP
        add r15, 8
        NEXT


; Words for manipulating the PARAMETER (DATA) stack

defcode "DSP@", DSPFETCH
        mov rax, rsp
        push rax
        NEXT

defcode "DSP!", DSPSTORE
        pop rsp
        NEXT

; Input and Output Words (KEY and EMIT)

;	The FORTH word KEY reads the next byte from stdin (and pushes it on the parameter stack).
;	So if KEY is called and someone hits the space key, then the number 32 (ASCII code of space)
;	is pushed on the stack.
;
;	In FORTH there is no distinction between reading code and reading input.  We might be reading
;	and compiling code, we might be reading words to execute, we might be asking for the user
;	to type their name -- ultimately it all comes in through KEY.
;
;	The implementation of KEY uses an input buffer of a certain size (defined at the end of this
;	file).  It calls the Linux read(2) system call to fill this buffer and tracks its position
;	in the buffer using a couple of variables, and if it runs out of input buffer then it refills
;	it automatically.  The other thing that KEY does is if it detects that stdin has closed, it
;	exits the program, which is why when you hit ^D the FORTH system cleanly exits.

defcode "KEY", KEY
        call _KEY
        push rax
        NEXT
_KEY:
        mov rbx, [currkey]
        cmp rbx, [bufftop]
        jge .full
        xor rax, rax
        mov al, [rbx]
        inc rbx
        mov [currkey], rbx
        ret
.full:
        push rsi                        ; save rsi temporarily
        push rdi                        ; rdi
        push rax                        ; and rax
        mov rdi, buffer
.more_input:
        call kbd_get_char
        cmp al, 0x08
        jne .store_char
        ; deal with backspace
        cmp rdi, buffer
        je .more_input          ; At start of line buffer: ignore backspace completely
        dec rdi                 ; Remove last char from buffer
        call vga_print_chr      ; Erase last char on screen
        jmp .more_input
.store_char:
        test al, 0x80           ; Ignore non-ASCII keys (arrows 0x80..0x83) in line-input mode
        jnz .more_input
        mov ah, 0x0F
        call vga_print_chr
        mov [rdi], al
        inc rdi
        cmp al, 0x0A
        jne .more_input
        mov qword [currkey], buffer
        mov [bufftop], rdi
        pop rax
        pop rdi                         ; restore
        pop rsi                         ; and restore
        jmp _KEY

align 8, db 0
currkey: dq f64_bootstrap_start
bufftop: dq f64_bootstrap_end

;	By contrast, output is much simpler.  The FORTH word EMIT writes out a single byte.
;	We just point it at our existing vga_print_chr function.

defcode "EMIT", EMIT
        pop rax
        call _EMIT
        NEXT
_EMIT:
        mov ah, 0x0F
        call vga_print_chr
        ret

_FLUSH_EMIT:
        ret

defcode "FLUSH", FLUSH
        call _FLUSH_EMIT
        NEXT

defcode "CLS", CLS
        mov rax, 0x0f200f200f200f20 ; Set background color to black (0), foreground
                                ; color to white (15/f) and the character to blank space (20).
        call vga_CLS
        NEXT

align 8, db 0
emit_ptr: dq emit_buffer

;	Back to input, WORD is a FORTH word which reads the next full word of input.
;
;	What it does in detail is that it first skips any blanks (spaces, tabs, newlines and so on).
;	Then it calls KEY to read characters into an internal buffer until it hits a blank.  Then it
;	calculates the length of the word it read and returns the address and the length as
;	two words on the stack (with the length at the top of stack).
;
;	Notice that WORD has a single internal buffer which it overwrites each time (rather like
;	a static C string).  Also notice that WORD's internal buffer is just 32 bytes long and
;	there is NO checking for overflow.  31 bytes happens to be the maximum length of a
;	FORTH word that we support, and that is what WORD is used for: to read FORTH words when
;	we are compiling and executing code.  The returned strings are not NUL-terminated.
;
;	Start address+length is the normal way to represent strings in FORTH (not ending in an
;	ASCII NUL character as in C), and so FORTH strings can contain any character including NULs
;	and can be any length.
;
;	WORD is not suitable for just reading strings (eg. user input) because of all the above
;	peculiarities and limitations.

;	Note that when executing, you'll see:
;	WORD FOO
;	which puts "FOO" and length 3 on the stack, but when compiling:
;	: BAR WORD FOO ;
;	is an error (or at least it doesn't do what you might expect).  Later we'll talk about compiling
;	and immediate mode, and you'll understand why.

defcode "WORD", WORD
        call _WORD
        push rdi
        push rcx
        NEXT

_WORD:
.ws:
        call _KEY
        cmp al, '\'
        je .comment
        cmp al, ' '
        jbe .ws

        mov rdi, word_buffer
.word:
; --- START CASE INSENSITIVITY MOD ---
        cmp al, 'a'         ; Check if character is below 'a'
        jb .skip_convert
        cmp al, 'z'         ; Check if character is above 'z'
        ja .skip_convert
        sub al, 0x20        ; Subtract 32 to convert lowercase to uppercase
.skip_convert:
; --- END CASE INSENSITIVITY MOD ---
        stosb
        call _KEY
        cmp al, ' '
        ja .word

        sub rdi, word_buffer
        mov rcx, rdi
        mov rdi, word_buffer
        ret

.comment:
        call _KEY
        cmp al, 0x0A
        jne .comment
        jmp .ws

word_buffer: times 32 db 0

;	As well as reading in words we'll need to read in numbers and for that we are using a function
;	called NUMBER.  This parses a numeric string such as one returned by WORD and pushes the
;	number on the parameter stack.
;
;	The function uses the variable BASE as the base (radix) for conversion, so for example if
;	BASE is 2 then we expect a binary number.  Normally BASE is 10.
;
;	If the word starts with a '-' character then the returned value is negative.
;
;	If the string can't be parsed as a number (or contains characters outside the current BASE)
;	then we need to return an error indication.  So NUMBER actually returns two items on the stack.
;	At the top of stack we return the number of unconverted characters (ie. if 0 then all characters
;	were converted, so there is no error).  Second from top of stack is the parsed number or a
;	partial value if there was an error.

defcode "NUMBER", NUMBER
        pop rcx
        pop rdi
        call _NUMBER
        push rax
        push rcx
        NEXT

_NUMBER:
        xor rax, rax
        xor rbx, rbx
        xor r8, r8          ; r8 = sign flag (0 = positive, 1 = negative)

        test rcx, rcx ; trying to parse zero-length string is an error, but will return 0.
        jz .ret

        mov rdx, [var_BASE] ; get BASE (in dl)
        mov bl, [rdi]       ; bl = first character in string
        inc rdi
        cmp bl, '-'         ; negative number?
        jnz .convert
        inc r8              ; mark negative
        dec rcx
        jnz .loop
        mov rcx, 1
        ret

        ; Loop reading digits.
.loop:
        imul rax, rdx       ; rax *= BASE
        mov bl, [rdi]       ; bl = next character in string
        inc rdi

.convert:
        sub bl, '0'         ; < '0'?
        jb .finish
        cmp bl, 10          ; <= '9'?
        jb .numeric
        sub bl, 17          ; < 'A'? (17 is 'A'-'0')
        jb .finish
        add bl, 10

.numeric:
        cmp bl, dl          ; >= BASE?
        jge .finish

        ; OK, so add it to rax and loop
        add rax, rbx
        dec rcx
        jnz .loop

        ; Negate the result if the first character was '-'
.finish:
        test r8, r8
        jz .ret
        neg rax

.ret:
        ret

;	We're building up to our prelude on how FORTH code is compiled, but first we need yet more infrastructure.
;
;	The FORTH word FIND takes a string (a word as parsed by WORD -- see above) and looks it up in the
;	dictionary.  What it actually returns is the address of the dictionary header, if it finds it,
;	or 0 if it didn't.
;
;	So if DOUBLE is defined in the dictionary, then WORD DOUBLE FIND returns the following pointer:
;
 ;   pointer to this
;	|
;	|
;	V
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;
;	See also >CFA and >DFA.
;
;	FIND doesn't find dictionary entries which are flagged as HIDDEN.  See below for why.

defcode "FIND", FIND
        pop rcx
        pop rdi
        call _FIND
        push rax
        NEXT

_FIND:
        push rsi              ; save rsi so that we can use it in string comparison

        ; now we start searching the dictionary for this word
        mov rdx, [var_LATEST] ; LATEST points to name header of the latest word in the dictionary
.loop:
        test rdx, rdx         ; NULL pointer?
        je .notfound

        ; Compare the length expected and the length of the word.
        ; Note that if the F_HIDDEN flag is set on the word, then by a bit of trickery
        ; this won't pick the word (the length will appear to be wrong).
        xor rax,rax
        mov al, [rdx+8]              ; al = flags+length field
        and al, F_HIDDEN | F_LENMASK ; al = name length
        cmp al, cl                   ; Length is the same?
        jne .next

        ; Quick 1st character check
        mov bl, [rdx+9]
        cmp bl, [rdi]
        jne .next

        ; Compare the strings in detail.
        push rcx         ; Save the length
        push rdi         ; Save the address (repe cmpsb will move this pointer)
        lea rsi, [rdx+9] ; Dictionary string we are checking against.
        repe cmpsb       ; Compare the strings.
        pop rdi
        pop rcx
        jne .next        ; Not the same.

        ; The strings are the same - return the header pointer in rax
        pop rsi
        mov rax, rdx
        ret

.next:
        mov rdx, [rdx] ; Move back through the link field to the previous word
        jmp .loop      ; .. and loop.

.notfound:
        pop rsi
        xor rax,rax ; Return zero to indicate not found.
        ret

;	FIND returns the dictionary pointer, but when compiling we need the codeword pointer (recall
;	that FORTH definitions are compiled into lists of codeword pointers).  The standard FORTH
;	word >CFA turns a dictionary pointer into a codeword pointer.
;
;	The example below shows the result of:
;
;		WORD DOUBLE FIND >CFA
;
;	FIND returns a pointer to this
;	|				>CFA converts it to a pointer to this
;	|					   |
;	V					   V
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;						   codeword
;
;	Notes:
;
;	Because names vary in length, this isn't just a simple increment.
;
;	In this FORTH you cannot easily turn a codeword pointer back into a dictionary entry pointer, but
;	that is not true in most FORTH implementations where they store a back pointer in the definition
;	(with an obvious memory/complexity cost).  The reason they do this is that it is useful to be
;	able to go backwards (codeword -> dictionary entry) in order to decompile FORTH definitions
;	quickly.
;
;	What does CFA stand for?  My best guess is "Code Field Address".

defcode ">CFA", TCFA
        pop rdi
        call _TCFA
        push rdi
        NEXT

_TCFA:
        xor rax, rax
        add rdi, 8        ; skip link pointer
        mov al, [rdi]     ; load flags+len into al
        inc rdi           ; skip flags+len byte
        and al, F_LENMASK ; just the length, not the flags
        add rdi, rax      ; skip the name
        add rdi, 0b111    ; the codeword is 8-byte aligned
        and rdi, ~0b111
        ret

;	Related to >CFA is >DFA which takes a dictionary entry address as returned by FIND and
;	returns a pointer to the first data field.
;
;	FIND returns a pointer to this
;	|				>CFA converts it to a pointer to this
;	|					   |
;	|					   |	>DFA converts it to a pointer to this
;	|					   |		 |
;	V					   V		 V
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;						   codeword
;
;	(Note to those following the source of FIG-FORTH / ciforth: My >DFA definition is
;	different from theirs, because they have an extra indirection).
;
;	You can see that >DFA is easily defined in FORTH just by adding 8 to the result of >CFA.

defword ">DFA", TDFA
        dq TCFA
        dq INCR8
        dq EXIT

;	COMPILING ----------------------------------------------------------------------
;
;	Now we'll talk about how FORTH compiles words.  Recall that a word definition looks like this:
;
;		: DOUBLE DUP + ;
;
;	and we have to turn this into:
;
;	  pointer to previous word
;	   ^
;	   |
;	+--|------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
;	+---------+---+---+---+---+---+---+---+---+------------+--|---------+------------+------------+
;          ^       len                         pad  codeword      |
;	   |							  V
;	  LATEST points here				points to codeword of DUP
;
;	There are several problems to solve.  Where to put the new word?  How do we read words?  How
;	do we define the words : (COLON) and ; (SEMICOLON)?
;
;	FORTH solves this rather elegantly and as you might expect in a very low-level way which
;	allows you to change how the compiler works on your own code.
;
;	FORTH has an INTERPRET function (a true interpreter this time, not DOCOL) which runs in a
;	loop, reading words (using WORD), looking them up (using FIND), turning them into codeword
;	pointers (using >CFA) and deciding what to do with them.
;
;	What it does depends on the mode of the interpreter (in variable STATE).
;
;	When STATE is zero, the interpreter just runs each word as it looks them up.  This is known as
;	immediate mode.
;
;	The interesting stuff happens when STATE is non-zero -- compiling mode.  In this mode the
;	interpreter appends the codeword pointer to user memory (the HERE variable points to the next
;	free byte of user memory -- see DATA SEGMENT section below).
;
;	So you may be able to see how we could define : (COLON).  The general plan is:
;
;	(1) Use WORD to read the name of the function being defined.
;
;	(2) Construct the dictionary entry -- just the header part -- in user memory:
;
;    pointer to previous word (from LATEST)			+-- Afterwards, HERE points here, where
;	   ^							|   the interpreter will start appending
;	   |							V   codewords.
;	+--|------+---+---+---+---+---+---+---+---+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      |
;	+---------+---+---+---+---+---+---+---+---+------------+
;                   len                         pad  codeword
;
;	(3) Set LATEST to point to the newly defined word, ...
;
;	(4) .. and most importantly leave HERE pointing just after the new codeword.  This is where
;	    the interpreter will append codewords.
;
;	(5) Set STATE to 1.  This goes into compile mode so the interpreter starts appending codewords to
;	    our partially-formed header.
;
;	After : has run, our input is here:
;
;	: DOUBLE DUP + ;
;	         ^
;		 |
;		Next byte returned by KEY will be the 'D' character of DUP
;
;	so the interpreter (now it's in compile mode, so I guess it's really the compiler) reads "DUP",
;	looks it up in the dictionary, gets its codeword pointer, and appends it:
;
;									     +-- HERE updated to point here.
;									     |
;									     V
;	+---------+---+---+---+---+---+---+---+---+------------+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        |
;	+---------+---+---+---+---+---+---+---+---+------------+------------+
;                  len                         pad  codeword
;
;	Next we read +, get the codeword pointer, and append it:
;
;											  +-- HERE updated to point here.
;											  |
;											  V
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          |
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+
;                  len                         pad  codeword
;
;	The issue is what happens next.  Obviously what we _don't_ want to happen is that we
;	read ";" and compile it and go on compiling everything afterwards.
;
;	At this point, FORTH uses a trick.  Remember the length byte in the dictionary definition
;	isn't just a plain length byte, but can also contain flags.  One flag is called the
;	IMMEDIATE flag (F_IMMED in this code).  If a word in the dictionary is flagged as
;	IMMEDIATE then the interpreter runs it immediately _even if it's in compile mode_.
;
;	This is how the word ; (SEMICOLON) works -- as a word flagged in the dictionary as IMMEDIATE.
;
;	And all it does is append the codeword for EXIT on to the current definition and switch
;	back to immediate mode (set STATE back to 0).  Shortly we'll see the actual definition
;	of ; and we'll see that it's really a very simple definition, declared IMMEDIATE.
;
;	After the interpreter reads ; and executes it 'immediately', we get this:
;
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
;	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
;                  len                         pad  codeword					       ^
;												       |
;												    
;	STATE is set to 0.
;
;	And that's it, job done, our new definition is compiled, and we're back in immediate mode
;	just reading and executing words, perhaps including a call to test our new word DOUBLE.
;
;	The only last wrinkle in this is that while our word was being compiled, it was in a
;	half-finished state.  We certainly wouldn't want DOUBLE to be called somehow during
;	this time.  There are several ways to stop this from happening, but in FORTH what we
;	do is flag the word with the HIDDEN flag (F_HIDDEN in this code) just while it is
;	being compiled.  This prevents FIND from finding it, and thus in theory stops any
;	chance of it being called.
;
;	The above explains how compiling, : (COLON) and ; (SEMICOLON) works and in a moment I'm
;	going to define them.  The : (COLON) function can be made a little bit more general by writing
;	it in two parts.  The first part, called CREATE, makes just the header:
;
;						   +-- Afterwards, HERE points here.
;						   |
;						   V
;	+---------+---+---+---+---+---+---+---+---+
;	| LINK    | 6 | D | O | U | B | L | E | 0 |
;	+---------+---+---+---+---+---+---+---+---+
;                  len                         pad
;
;	and the second part, the actual definition of : (COLON), calls CREATE and appends the
;	DOCOL codeword, so leaving:
;
;								+-- Afterwards, HERE points here.
;								|
;								V
;	+---------+---+---+---+---+---+---+---+---+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      |
;	+---------+---+---+---+---+---+---+---+---+------------+
;                  len                         pad  codeword
;
;	CREATE is a standard FORTH word and the advantage of this split is that we can reuse it to
;	create other types of words (not just ones which contain code, but words which contain variables,
;	constants and other data).

defcode "CREATE", CREATE
        ; Get the name length and address.
        pop rcx                 ; rcx = length
        pop rbx                 ; rbx = address of name

        ; Link pointer.
        mov rdi, [var_HERE]     ; rdi is the address of the header
        mov rax, [var_LATEST]   ; Get link pointer
        stosq                   ; and store it in the header.

        ; Length byte and the word itself.
        mov al, cl              ; Get the length.
        stosb                   ; Store the length/flags byte.
        push rsi
        mov rsi, rbx            ; rsi = word
        rep movsb               ; Copy the word
        pop rsi
        add rdi, 0b111          ; Align to next 8 byte boundary.
        and rdi, ~0b111

        ; Update LATEST and HERE.
        mov rax, [var_HERE]
        mov [var_LATEST], rax
        mov [var_HERE], rdi
        NEXT

;	Because I want to define : (COLON) in FORTH, not assembler, we need a few more FORTH words
;	to use.
;
;	The first is , (COMMA) which is a standard FORTH word which appends a 64 bit integer to the user
;	memory pointed to by HERE, and adds 8 to HERE.  So the action of , (COMMA) is:
;
;							previous value of HERE
;								 |
;								 V
;	+---------+---+---+---+---+---+---+---+---+-- - - - - --+------------+
;	| LINK    | 6 | D | O | U | B | L | E | 0 |             |  <data>    |
;	+---------+---+---+---+---+---+---+---+---+-- - - - - --+------------+
;                  len                         pad		              ^
;									      |
;									new value of HERE
;
;	and <data> is whatever 64 bit integer was at the top of the stack.
;
;	, (COMMA) is quite a fundamental operation when compiling.  It is used to append codewords
;	to the current word that is being compiled.

defcode ",", COMMA
        pop rax
        call _COMMA
        NEXT

_COMMA:
        mov rdi, [var_HERE]     ; HERE
        stosq                   ; Store it.
        mov [var_HERE], rdi     ; Update HERE (incremented)
        ret

;	Our definitions of : (COLON) and ; (SEMICOLON) will need to switch to and from compile mode.
;
;	Immediate mode vs. compile mode is stored in the global variable STATE, and by updating this
;	variable we can switch between the two modes.
;
;	For various reasons which may become apparent later, FORTH defines two standard words called
;	[ and ] (LBRAC and RBRAC) which switch between modes:
;
;	Word	Assembler	Action		Effect
;	[	LBRAC		STATE := 0	Switch to immediate mode.
;	]	RBRAC		STATE := 1	Switch to compile mode.
;
;	[ (LBRAC) is an IMMEDIATE word.  The reason is as follows: If we are in compile mode and the
;	interpreter saw [ then it would compile it rather than running it.  We would never be able to
;	switch back to immediate mode!  So we flag the word as IMMEDIATE so that even in compile mode
;	the word runs immediately, switching us back to immediate mode.

defcode "[", LBRAC, F_IMMED
        xor rax, rax
        mov [var_STATE], rax
        NEXT

defcode "]", RBRAC
        mov qword [var_STATE], 1
        NEXT

;	Now we can define : (COLON) using CREATE.  It just calls CREATE, appends DOCOL (the codeword), sets
;	the word HIDDEN and goes into compile mode.

defword ":", COLON
        dq $WORD
        dq CREATE
        dq LIT, DOCOL, COMMA
        dq LATEST, FETCH, HIDDEN
        dq RBRAC
        dq EXIT

;	; (SEMICOLON) is also elegantly simple.  Notice the F_IMMED flag.

defword ";", SEMICOLON, F_IMMED
        dq LIT, EXIT, COMMA
        dq LATEST, FETCH, HIDDEN
        dq LBRAC
        dq EXIT

;	EXTENDING THE COMPILER ----------------------------------------------------------------------
;
;	Words flagged with IMMEDIATE (F_IMMED) aren't just for the FORTH compiler to use.  You can define
;	your own IMMEDIATE words too, and this is a crucial aspect when extending basic FORTH, because
;	it allows you in effect to extend the compiler itself.  Does gcc let you do that?
;
;	Standard FORTH words like IF, WHILE, ." and so on are all written as extensions to the basic
;	compiler, and are all IMMEDIATE words.
;
;	The IMMEDIATE word toggles the F_IMMED (IMMEDIATE flag) on the most recently defined word,
;	or on the current word if you call it in the middle of a definition.
;
;	Typical usage is:
;
;	: MYIMMEDWORD IMMEDIATE
;		...definition...
;	;
;
;	but some FORTH programmers write this instead:
;
;	: MYIMMEDWORD
;		...definition...
;	; IMMEDIATE
;
;	The two usages are equivalent, to a first approximation.

defcode "IMMEDIATE", IMMEDATE, F_IMMED
        mov rdi, [var_LATEST]
        add rdi, 8
        xor byte [rdi], F_IMMED
        NEXT

;	'addr HIDDEN' toggles the hidden flag (F_HIDDEN) of the word defined at addr.  To hide the
;	most recently defined word (used above in : and ; definitions) you would do:
;
;		LATEST @ HIDDEN
;
;	'HIDE word' toggles the flag on a named 'word'.
;
;	Setting this flag stops the word from being found by FIND, and so can be used to make 'private'
;	words.  For example, to break up a large word into smaller parts you might do:
;
;		: SUB1 ... subword ... ;
;		: SUB2 ... subword ... ;
;		: SUB3 ... subword ... ;
;		: MAIN ... defined in terms of SUB1, SUB2, SUB3 ... ;
;		HIDE SUB1
;		HIDE SUB2
;		HIDE SUB3
;
;	After this, only MAIN is 'exported' or seen by the rest of the program.

defcode "HIDDEN", HIDDEN
        pop rdi
        add rdi, 8
        xor byte [rdi], F_HIDDEN
        NEXT

defword "HIDE", HIDE
        dq $WORD
        dq FIND
        dq HIDDEN
        dq EXIT

;	' (TICK) is a standard FORTH word which returns the codeword pointer of the next word.
;
;	The common usage is:
;
;	' FOO ,
;
;	which appends the codeword of FOO to the current word we are defining (this only works in compiled code).
;
;	You tend to use ' in IMMEDIATE words.  For example an alternate (and rather useless) way to define
;	a literal 2 might be:
;
;	: LIT2 IMMEDIATE
;		' LIT ,		\ Appends LIT to the currently-being-defined word
;		2 ,		\ Appends the number 2 to the currently-being-defined word
;	;
;
;	So you could do:
;
;	: DOUBLE LIT2 * ;
;
;	(If you don't understand how LIT2 works, then you should review the material about compiling words
;	and immediate mode).
;
;	This definition of ' uses a cheat which I copied from buzzard92.  As a result it only works in
;	compiled code.  It is possible to write a version of ' based on WORD, FIND, >CFA which works in
;	immediate mode too.

defcode "'", TICK
        lodsq
        push rax
        NEXT

;	BRANCHING ----------------------------------------------------------------------
;
;	It turns out that all you need in order to define looping constructs, IF-statements, etc.
;	are two primitives.
;
;	BRANCH is an unconditional branch. 0BRANCH is a conditional branch (it only branches if the
;	top of stack is zero).
;
;	The diagram below shows how BRANCH works in some imaginary compiled word.  When BRANCH executes,
;	%rsi starts by pointing to the offset field (compare to LIT above):
;
;	+---------------------+-------+---- - - ---+------------+------------+---- - - - ----+------------+
;	| (Dictionary header) | DOCOL |            | BRANCH     | offset     | (skipped)     | word       |
;	+---------------------+-------+---- - - ---+------------+-----|------+---- - - - ----+------------+
;								   ^  |			      ^
;								   |  |			      |
;								   |  +-----------------------+
;								  %esi added to offset
;
;	The offset is added to %rsi to make the new %rsi, and the result is that when NEXT runs, execution
;	continues at the branch target.  Negative offsets work as expected.
;
;	0BRANCH is the same except the branch happens conditionally.
;
;	Now standard FORTH words such as IF, THEN, ELSE, WHILE, REPEAT, etc. can be implemented entirely
;	in FORTH.  They are IMMEDIATE words which append various combinations of BRANCH or 0BRANCH
;	into the word currently being compiled.
;
;	As an example, code written like this:
;
;		condition-code IF true-part THEN rest-code
;
;	compiles to:
;
;		condition-code 0BRANCH OFFSET true-part rest-code
;					  |		^
;					  |		|
;					  +-------------+

defcode "BRANCH", BRANCH
        add rsi, [rsi]
        NEXT

defcode "0BRANCH", ZBRANCH
        pop rax
        test rax, rax
        jz code_BRANCH
        add rsi, 8
        NEXT

;       Primitives for DO, LOOP +LOOP:

defcode "(DO)", XDO
        pop rbx             ; Pop 'start' (Index) from Data Stack
        pop rax             ; Pop 'limit' from Data Stack
        PUSHITR rax         ; Push 'limit' to Iterator Stack
        PUSHITR rbx         ; Push 'start' to Iterator Stack. 
                            ; Now [r15] = Index, [r15+8] = Limit
        NEXT

defcode "(LOOP)", XLOOP
        ; 1. Load Loop Parameters
        inc qword [r15]     ; Increment Index in-place
        mov rbx, [r15]      ; Load new Index
        mov rcx, [r15+8]    ; Load Limit
        ; 2. Compare
        cmp rbx, rcx        ; Compare Index vs Limit
        jge .loop_finish    ; If Index >= Limit, we are done
.loop_continue:
        ; 3. Loop Back
        add rsi, [rsi]      ; Apply branch offset
        NEXT
.loop_finish:
        ; 4. Cleanup
        add r15, 16         ; Drop Index & Limit
        add rsi, 8          ; Skip the inline offset
        NEXT

defcode "(+LOOP)", XPLUSLOOP
        pop rax             ; Pop increment 'n' from Data Stack
        mov rbx, [r15]      ; Current Index
        add rax, rbx        ; New Index = Old Index + n
        mov [r15], rax      ; Update Index on stack
        mov rcx, [r15+8]    ; Load Limit
        sub rbx, rcx        ; rbx = OldIndex - Limit
        sub rax, rcx        ; rax = NewIndex - Limit
        xor rax, rbx        ; XOR the differences
        js .loop_finish     ; If Sign Flag is set (result negative), we crossed boundary -> Finish.
.loop_continue:
        add rsi, [rsi]
        NEXT
.loop_finish:
        add r15, 16         ; Drop Loop context
        add rsi, 8          ; Skip offset
        NEXT

defcode "I", I
        mov rax, [r15]      ; Copy TOS of Iterator Stack
        push rax            ; Push to Data Stack
        NEXT

defcode "J", J
        mov rax, [r15+16]   ; Skip current frame
        push rax
        NEXT

defcode "UNLOOP", UNLOOP
        lea r15, [r15+16]   ; Pop one frame
        NEXT

defcode "LEAVE", LEAVE
        mov rax, [r15]      ; Get Index
        mov [r15+8], rax    ; Overwrite Limit with Index
        NEXT


;	LITERAL STRINGS ----------------------------------------------------------------------
;
;	LITSTRING is a primitive used to implement the ." and S" operators (which are written in
;	FORTH).  See the definition of those operators later.
;
;	TELL just prints a string.  It's more efficient to define this in assembly because we
;	can make it a single Linux syscall.

defcode "LITSTRING", LITSTRING
        lodsq
        push rsi
        push rax
        add rsi, rax
        add rsi, 0b111
        and rsi, ~0b111
        NEXT

defcode "TELL", TELL
        pop rdx             ; 3nd param = length of string
        pop rax             ; 2nd param = the string
        push rsi            ; save previous value of rsi in the stack
        call vga_print_string
        pop rsi             ; restore rsi
        NEXT

;	QUIT AND INTERPRET ----------------------------------------------------------------------
;
;	QUIT is the first FORTH function called, almost immediately after the FORTH system "boots".
;	As explained before, QUIT doesn't "quit" anything.  It does some initialisation (in particular
;	it clears the return stack) and it calls INTERPRET in a loop to interpret commands.  The
;	reason it is called QUIT is because you can call it from your own FORTH words in order to
;	"quit" your program and start again at the user prompt.
;
;	INTERPRET is the FORTH interpreter ("toploop", "toplevel" or "REPL" might be a more accurate
;	description -- see: http://en.wikipedia.org/wiki/REPL).

defword "QUIT", QUIT
        dq R0, RSPSTORE
        dq INTERPRET
        dq BRANCH, -16

;	This interpreter is pretty simple, but remember that in FORTH you can always override
;	it later with a more powerful one!

defcode "INTERPRET", INTERPRET
        call _WORD                  ; return rcx = length, rdi = pointer to word

        ; Is it in the dictionary?
        xor rax, rax
        mov [interpret_is_lit], rax ; Not a literal number (not yet anyway ...)
        call _FIND                  ; Return rax = pointer to header or 0 if not found
        test rax, rax               ; Found?
        jz .number

        ; In the dictionary. Is it an IMMEDIATE codeword?
        mov rdi, rax                ; rdi = dictionary entry
        mov al, [rdi+8]             ; Get name+flags.
        push ax                     ; Just save it for now
        call _TCFA                  ; Convert dictionary entry in rdi to codeword pointer
        pop ax
        and al, F_IMMED             ; Is IMMED flag set?
        mov rax, rdi
        jnz .exec                   ; If IMMED, jump straight to executing

        jmp .main

        ; Not in the dictionary (not a word) so assume it's a literal number.
.number:
        inc qword [interpret_is_lit]
        call _NUMBER            ; Returns the parsed number in rax, rcx > 0 if error
        test rcx, rcx
        jnz .numerror
        mov rbx, rax
        mov rax, LIT            ; The word is LIT

        ; Are we compiling or executing?
.main:
        mov rdx, [var_STATE]
        test rdx, rdx
        jz .exec                        ; Jump if executing.

        ; Compiling - just append the word to the current dictionary definition.
        call _COMMA
        mov rcx, [interpret_is_lit]     ; Was it a literal?
        test rcx, rcx
        jz .next
        mov rax, rbx                    ; Yes, so LIT is followed by a number.
        call _COMMA
.next:
        NEXT

        ; Executing - run it!
.exec:
        mov rcx, [interpret_is_lit] ; Literal?
        test rcx, rcx               ; Literal?
        jnz .litexec

        ; Not a literal, execute it now.  This never returns, but the codeword will
        ; eventually call NEXT which will reenter the loop in QUIT.
        jmp [rax]

        ; Executing a literal, which means push it on the stack.
.litexec:
        push rbx
        NEXT

        ; Parse error (not a known word or a number in the current BASE).
.numerror:
        ; Print an error message followed by up to 40 characters of context.
        push rsi
        push rax
        push rdx

        mov rax, errmsg         ; 2nd param: error message
        mov rdx, errmsglen      ; 3rd param: length of string
        call vga_print_string

        mov rax, [currkey]      ; the error occurred just before currkey position
        mov rdx, rax
        sub rdx, buffer         ; rdx = currkey - buffer (length in buffer before currkey)
        cmp rdx, 40             ; if > 40, then print only 40 characters
        jle .le
        mov rdx, 40
.le:
        sub rax, rdx            ; rcx = start of area to print, rdx = length
        call vga_print_string

        mov rax, errmsgnl       ; newline
        mov rdx, 1
        call vga_print_string
        pop rdx
        pop rax
        pop rsi
        NEXT

errmsg: db "PARSE ERROR: "
errmsglen: equ $ - errmsg
errmsgnl: db 0x0A

align 8, db 0
interpret_is_lit:
        dq 0                    ; Flag used to record if reading a literal
align 8, db 0
read_from_fd:
        dq 0

;	ODDS AND ENDS ----------------------------------------------------------------------
;
;	CHAR puts the ASCII code of the first character of the following word on the stack.  For example
;	CHAR A puts 65 on the stack.
;
;	EXECUTE is used to run execution tokens.  See the discussion of execution tokens in the
;	FORTH code for more details.
;
;	SYSCALL0, SYSCALL1, SYSCALL2, SYSCALL3 make a standard Linux system call.  (See <asm/unistd.h>
;	for a list of system call numbers).  As their name suggests these forms take between 0 and 3
;	syscall parameters, plus the system call number.
;
;	In this FORTH, SYSCALL0 must be the last word in the built-in (assembler) dictionary because we
;	initialise the LATEST variable to point to it.  This means that if you want to extend the assembler
;	part, you must put new words before SYSCALL0, or else change how LATEST is initialised.
;
;       The IN/OUT B/W functions will be useful for shutdown, talking to peripherals, and for the eventual
;       creation of a filesystem

defcode "CHAR", CHAR
        call _WORD              ; Returns rcx = length, rdi = pointer to word.
        xor rax, rax
        mov al, [rdi]           ; Get the first character of the word.
        push rax                ; Push it onto the stack.
        NEXT

defcode "EXECUTE", EXECUTE
        pop rax                 ; Get xt into rax
        jmp [rax]               ; and jump to it.
                                ; After xt runs its NEXT will continue executing the current word.

; ( val port -- ) Write byte to I/O port
defcode "OUTB", OUTB
        pop rdx             ; port
        pop rax             ; value
        out dx, al
        NEXT

; ( val port -- ) Write 16-bit word to I/O port
defcode "OUTW", OUTW
        pop rdx             ; port
        pop rax             ; value
        out dx, ax
        NEXT

; ( port -- val ) Read byte from I/O port
defcode "INB", INB
        pop rdx             ; port
        xor rax, rax
        in al, dx
        push rax
        NEXT

; ( port -- val ) Read 16-bit word from I/O port
defcode "INW", INW
        pop rdx             ; port
        xor rax, rax
        in ax, dx
        push rax
        NEXT

; come into this with a 28-bit LBA in rax
shared_ata_setup:
        push rdx
        push rax
        push rax
        mov dx, 0x1F7
.wait:
        in al, dx
        test al, 0x80
        jnz shared_ata_setup.wait
        pop rax
        shr rax, 24
        and al, 0x0F
        or al, 0xE0
        mov dx, 0x1F6
        out dx, al
        mov al, 1
        mov dx, 0x1F2
        out dx, al
        pop rax
        mov dx, 0x1F3
        out dx, al
        mov dx, 0x1F4
        shr rax, 8
        out dx, al
        mov dx, 0x1F5
        shr rax, 8
        out dx, al
        pop rdx
        ret

; ( lba addr -- )
defcode "SECTOR@", SECTOR_FETCH
        pop rdi             ; destination buffer address
        pop rax             ; 28-bit LBA
        call shared_ata_setup
        mov al, 0x20
        mov dx, 0x1F7
        out dx, al
.wait:
        in al, dx
        test al, 0x80       ; BSY == 0?
        jnz .wait
        test al, 0x08       ; DRQ == 1?
        je .wait
        mov dx, 0x1F0
        mov rcx, 256
        rep insw
        NEXT

;  ( lba addr -- )
defcode "SECTOR!", SECTOR_STORE
        pop rbx
        pop rax
        push rdx
        push rsi
        mov rsi, rbx
        call shared_ata_setup
        mov dx, 0x1F7
        mov al, 0x30
        out dx, al
.wait:
        in al, dx
        test al, 0x80       ; BSY == 0?
        jnz .wait
        test al, 0x08       ; DRQ == 1?
        je .wait
        mov dx, 0x1F0
        mov rcx, 256
        rep outsw
        mov dx, 0x1F7
        mov al, 0xE7
        out dx, al
.wait2:
        in al, dx
        test al, 0x80
        jnz .wait2
        pop rsi
        pop rdx
        NEXT

defconst "CURRKEY", CURRKEY, currkey
defconst "BUFFTOP", BUFFTOP, bufftop

; ( -- char ) Read a single raw keystroke immediately without echoing or waiting for Enter
defcode "KEY-RAW", KEY_RAW
        xor rax, rax
        call kbd_get_char
        push rax
        NEXT

; ( x y -- ) Move the console cursor to column x (0..79), row y (1..24)
defcode "AT-XY", AT_XY
        pop rax             ; y
        mov [con_y], al
        pop rax             ; x
        mov [con_x], al
        call vga_update_cursor
        NEXT

; ( -- addr ) Address of the kernel service table (Kernel_services in kernel.nasm)
defconst "KSERVICES", KSERVICES, Kernel_services

; ( arg entry stack-top -- result )
; Call native 64-bit code at 'entry' on a new stack that starts at 'stack-top'.
; 'arg' goes in rcx (Microsoft x64 ABI) and in rdi (System V ABI), so a C
; function compiled for either ABI gets it as its first argument. The return
; value (rax) goes on the data stack. The callee must keep the direction flag
; clear. The Forth registers are saved here, not on the native stack.
defcode "CALL-NATIVE", CALL_NATIVE
        pop rax             ; stack-top
        pop rbx             ; entry
        pop rcx             ; arg
        mov [native_saved_rsp], rsp
        mov [native_saved_rsi], rsi
        mov [native_saved_rbp], rbp
        mov [native_saved_r15], r15
        and rax, -16        ; 16-byte align the new stack
        mov rsp, rax
        mov rdi, rcx
        sub rsp, 32         ; shadow space for the Microsoft x64 ABI
        call rbx
        cld
        mov rsp, [native_saved_rsp]
        mov rsi, [native_saved_rsi]
        mov rbp, [native_saved_rbp]
        mov r15, [native_saved_r15]
        push rax
        NEXT

align 8, db 0
native_saved_rsp dq 0
native_saved_rsi dq 0
native_saved_rbp dq 0
native_saved_r15 dq 0

; ----------------------------------------------
; NOTE: ALWAYS ADD CODE HERE!!!
;-----------------------------------------------

defconst "GET-BRK", GET_BRK, F64_DATA_END

; DATA SEGMENT ----------------------------------------------------------------------------
; This is the non-syscall version of code needed to allocate memory for our data segment
; This will be used for our HERE dictionary
set_up_data_segment:
    mov qword [var_HERE], F64_DATA_START
    ret

; buffer allocation
align 8, db 0
return_stack:
    times RETURN_STACK_SIZE db 0
return_stack_top:

align 8, db 0
iterator_stack:
    times ITERATOR_STACK_SIZE db 0
iterator_stack_top:

align 8, db 0
buffer:
    times BUFFER_SIZE db 0

align 8, db 0
emit_buffer:
    times 4096 db 0

f64_bootstrap_start:
    incbin "kernel/f64_stripped.f"
f64_bootstrap_end: