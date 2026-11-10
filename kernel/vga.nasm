BITS 64 ; Long-mode VGA console stuff
DEFAULT ABS

;---Initialized data----------------------------------------------------------------
; our current x and y console positions
con_x db 0
con_y db 0
blank_h db 0
blank_l db 0
blanking dq 0

;---Constants-----------------------------------------------------------------------
VRAM equ 0xB8000
VGA_WIDTH equ 80
VGA_HEIGHT equ 25
; Colors
VGA_COLOR_BLACK equ 0
VGA_COLOR_BLUE equ 1
VGA_COLOR_GREEN equ 2
VGA_COLOR_CYAN equ 3
VGA_COLOR_RED equ 4
VGA_COLOR_MAGENTA equ 5
VGA_COLOR_BROWN equ 6
VGA_COLOR_LIGHT_GREY equ 7
VGA_COLOR_DARK_GREY equ 8
VGA_COLOR_LIGHT_BLUE equ 9
VGA_COLOR_LIGHT_GREEN equ 10
VGA_COLOR_LIGHT_CYAN equ 11
VGA_COLOR_LIGHT_RED equ 12
VGA_COLOR_LIGHT_MAGENTA equ 13
VGA_COLOR_LIGHT_BROWN equ 14
VGA_COLOR_WHITE equ 15

;---Code---------------------------------------------------------------------------
vga_CLS:
;*********************************************************************************;
; Before calling this, load rax w/an appropriate value                            ;
;---------------------------------------------------------------------------------;
; rax (XY__XY__XY__XY__): X -> Background color, Y -> Foreground (Character) color;
; rax (__ZZ__ZZ__ZZ__ZZ): ASCII code(s) of character(s) to use to fill the screen ;
;*********************************************************************************;
    push rax
    push rcx
    push rdi
    push rdx
    mov [blanking], rax
    mov [blank_h], ah
    mov [blank_l], al
    mov rdi, VRAM + VGA_WIDTH * 2
    mov rcx, 480 ; 80*25 / 4 = 500 (we set 4 characters each time).
    rep stosq    ; Clear the entire screen.
    mov byte [con_x], 0
    mov byte [con_y], 1
    ; set hardware cursor to full block retro style
    push dx
    mov dx, 0x3d4
    mov al, 0x0a
    out dx, al
    inc dx
    mov al, 0
    out dx, al
    mov dx, 0x3d4
    mov al, 0x0b
    out dx, al
    inc dx
    mov al, 0x0F
    out dx, al
    pop dx
    ;
    call vga_update_cursor
    pop rdx
    pop rdi
    pop rcx
    pop rax
    ret

vga_print_chr:
;**********************************************************************************;
; Prints a character at the current x, y location                                  ;
;----------------------------------------------------------------------------------;
;  ah: Color attributes                                                            ;
;  al: Character                                                                   ;
;**********************************************************************************;
    push rax
    push rdx
    push rdi
    push r8
    push r9
    movzx r8, byte[con_x]
    movzx r9, byte[con_y]
    ; Compute rdi = VRAM + (r9 * VGA_WIDTH * 2) + (r8 * 2)
    ; (Leaves r8 and r9 untouched!)
    mov rdi, VRAM
    lea rdi, [rdi + r8*2]
    push rax
    mov rax, VGA_WIDTH*2
    mul r9
    add rdi, rax
    pop rax
    cmp al, 0x0A
    je vga_print_chr.lf
    cmp al, 0x08
    je vga_print_chr.bs
    mov [rdi], ax     ; Write attributes (ah) + character (al) to VRAM.
    inc r8
    cmp r8, VGA_WIDTH
    jl vga_print_chr.done
    xor r8,r8
.y_bump:
    inc r9
    cmp r9, VGA_HEIGHT
    jl vga_print_chr.done
    call vga_scroll
    mov r9, VGA_HEIGHT - 1
.done:
    mov [con_x], r8b
    mov [con_y], r9b
    call vga_update_cursor
    pop r9
    pop r8
    pop rdi
    pop rdx
    pop rax
    ret
.lf:
    mov r8, 0
    jmp vga_print_chr.y_bump
.bs:
    cmp r8, 0
    jne .bs_same_line
    cmp r9, 1
    je .done                ; Already at (0, 0) — nothing to backspace!
    dec r9                  ; Move up to previous row
    mov r8, VGA_WIDTH - 1   ; Wrap to column 79
    jmp .bs_erase
.bs_same_line:
    dec r8                  ; Move back 1 column
.bs_erase:
    mov al, [blank_l]
    mov ah, [blank_h]
    mov [rdi - 2], ax       ; Erase the character right before the old cursor!
    jmp .done

vga_print_string:
;**********************************************************************************;
; a helper function using vga_print_chr to print a string                          ;
;----------------------------------------------------------------------------------;
    push rdx
    push rax
    push rcx
    mov rcx, rax
.loop:
    test rdx, rdx
    je vga_print_string.done
    mov al, byte [rcx]
    mov ah, 0x0F
    call vga_print_chr
    inc rcx
    dec rdx
    jmp vga_print_string.loop
.done:
    pop rcx
    pop rax
    pop rdx
    ret

vga_scroll:
;**********************************************************************************;
; Scrolls the screen when we get to the bottom...                                  ;
;----------------------------------------------------------------------------------;
    push rcx
    push rsi
    push rdi
    push rax
    cld
    ; lock the top row, scroll everything up
    mov rcx, (VGA_HEIGHT - 2) * (2 * VGA_WIDTH)
    mov rsi, VRAM + (VGA_WIDTH * 4)
    mov rdi, VRAM + (VGA_WIDTH * 2)
    rep movsb
    mov rdi, VRAM + ((VGA_WIDTH * 2) * 24)
    mov rax, [blanking]
    mov rcx, 20
    rep stosq    ; Clear the last line
    pop rax
    pop rdi
    pop rsi
    pop rcx
    ret

vga_update_cursor:
;*****************************************************************************;
; Because the hardware cursor isn't updated when we put characters directly   ;
; into VGA ram, we need to control the cursor manually. This does that by     ;
; updating the VGA CRTC's internal registers via the Index/Address Port 0x3D4 ;
; and the Data Port 0x3D5                                                     ;
;*****************************************************************************;
    push ax
    push dx
    movzx ax, byte [con_y]
    imul ax, VGA_WIDTH
    movzx dx, byte [con_x]
    add ax, dx
    push ax
    mov dx, 0x3d4
    mov al, 0x0f
    out dx, al
    inc dx
    pop ax
    push ax
    out dx, al
    mov dx, 0x3d4
    mov al, 0x0e
    out dx, al
    inc dx
    pop ax
    mov al, ah
    out dx, al
    pop dx
    pop ax
    ret

vga_print:
;**********************************************************************************;
; Prints a string - only used for error messages...                                ;
;----------------------------------------------------------------------------------;
;  ah: Color attributes                                                            ;
;  r8: x                                                                           ;
;  r9: y                                                                           ;
; rsi: pointer to string (first 16 bits = the number of characters in the string.) ;
;**********************************************************************************;
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    ; Map x, y coordinates to VRAM
    dec r8
    add r8, r8
    dec r9
    mov rdi, VRAM
    push rax
    mov rax, VGA_WIDTH*2
    mul r9
    add r8, rax
    pop rax
    movzx rcx, word [rsi]    ; rcx = string length (zero-extend first 16 bits)
    add rsi, 2
   .string_loop:             ; Print all the characters in the string.
        lodsb                ; al = [rsi], rsi++
        mov [rdi+r8], ax     ; Write attributes (ah) + character (al) to VRAM.
        add rdi, 2           ; Move to next word in VRAM
    loop .string_loop        ; rcx--, jnz
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

vga_print_hex:
;******************************************************************************;
; Prints a 16-digit hexadecimal value                                          ;
;------------------------------------------------------------------------------;
;  ah: Color attributes                                                        ;
;  r8: x                                                                       ;
;  r9: y                                                                       ;
; r10: value to be printed                                                     ;
;******************************************************************************;
    push rcx
    push rsi
    push r10
    sub rsp, 24              ; Make space for the string + alignment
    mov rsi, rsp
    push rsi                 ; Store rsi (string address)
    mov [rsi], word 18       ; String length = 18
    mov [rsi+2], word "0x"   ; Add hex prefix "0x"
    add rsi, 19              ; Point rsi to the end of the string
    mov ecx, 16              ; Loop 16 times (one for each digit)
   .digit:
        push r10             ; Store r10
        and r10, 0Fh         ; Isolate digit
        add r10b,'0'         ; We add '0' to convert a numerical digit to ASCII
        cmp r10b,'9'         ; Is hex digit ("ABCDEF") ?
        jbe .nohex
        add r10b, 7          ; We add 7 more to convert a hex digit to ASCII
       .nohex:
        mov [rsi], byte r10b ; Store result
        dec rsi              ; Next position
        pop r10              ; Restore r10
        shr r10, 4           ; Right shift by 4
    loop .digit
    pop rsi                  ; Restore rsi (string address)
    call vga_print               ; Print string
    add rsp, 24              ; Release local space
    pop r10
    pop rsi
    pop rcx
    ret

vga_print_int:
;******************************************************************************;
; Prints an integer value                                                      ;
;------------------------------------------------------------------------------;
;  ah: Color attributes                                                        ;
;  r8: x                                                                       ;
;  r9: y                                                                       ;
; r10: value to be printed                                                     ;
;******************************************************************************;
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push r10
    push r11
    sub rsp, 24         ; Make space for the string length + alignment
    mov rsi, rsp
    add rsi, 20         ; Point rsi to the end of the string
    xor rcx, rcx        ; rcx = 0
    push rax            ; Store color attributes
.digit_loop:
    ; Fast divmod by 10 using multiplication
    mov rax, r10
    mov r11, 0x199999999999999A   ; 2^64 / 10 (rounded up)
    mul r11                       ; Result in rdx
    mov rbx, rdx                  ; Quotient
    ; Calculate remainder (= r10 - quotient * 10)
    lea rdx, [rbx + rbx * 4]
    shl rdx, 1
    sub r10, rdx
    add r10, '0'                  ; We add '0' to convert a digit to ASCII
    mov [rsi], byte r10b          ; Write character to string
    dec rsi
    inc rcx
    mov r10, rbx                  ; Next quotient
    test rbx, rbx                 ; If not zero, loop
    jnz .digit_loop
    dec rsi
    mov [rsi], word cx            ; Write string length
    pop rax                       ; Restore color attributes
    call vga_print                    ; Print it
    add rsp, 24
    pop r11
    pop r10
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret
