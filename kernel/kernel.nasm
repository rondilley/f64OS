BITS 64   ; LONG MODE! w00t!

;---Constants-------------------------------------------------------------------
DATA_SEG equ 0x0010

;---Include---------------------------------------------------------------------
%include "kernel/vga.nasm"
%include "kernel/idt.nasm"
%include "kernel/isr.nasm"
%include "kernel/pma.nasm"
%include "kernel/tasking.nasm"


;---Initialized data------------------------------------------------------------
topline_message dw 80
db 'Stack Depth:                 f64 Bare-Metal OS v1.0    Ticks:                   '

;---Code------------------------------------------------------------------------
; this is the start of our 64-bit kernel
Kernel:
    lidt [abs IDTR] ; Load our IDTR

    mov al, 0xFC       ; OCW1: Unmask all interrupts at master PIC.
    out PIC1_DATA, al
    mov al, 0xFF       ; OCW1: Unmask all interrupts at master PIC.
    out PIC2_DATA, al

    ; Set all segments registers to DATA_SEG.
    mov ax, DATA_SEG
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    call PMA_init
    mov qword [abs stack_allocation], 0x7C00
    ; Clear the screen.
    mov rax, 0x0f200f200f200f20 ; Set background color to black (0), foreground
                                ; color to white (15/f) and the character to blank space (20).
    call vga_CLS

    ; Create two tasks.
    mov rsi, Task0
    call Create_task
    mov rsi, Task1
    call Create_task

    mov qword [abs active_task_slot], 0
    mov rsp, [abs TS0 + TS.rsp]
    sti
Task0:
    ; This is a "sorta" task... We're just getting the Forth implementation running
    ; and keeping it's stack frame separate for switching to our second task that
    ; implements the status bar... i.e. Task1, below...
    jmp f64_start

Task1:
    ; print on the top line
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 1
    mov r9, 1
    mov rsi, topline_message
    call vga_print
.loop:
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 63    ; x = 63
    mov r9, 1     ; y = 1
    ; Print system timer ticks.
    mov r10, [abs systimer_ticks]
    call vga_print_hex
    mov r10, [abs var_S0]
    sub r10, [abs cur_dsp]
    shr r10, 3                  ; Exact Forth Data Stack depth (0 when empty!)
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 14   ; x = 1
    mov r9, 1    ; y = 1
    call vga_print_int
    ; yield our remaining time slice..
    ; using hlt here would cause there to be a lot of "stuttering" as we wait for
    ; the remainder of the time slice to run out...
    call Yield_task
    jmp Task1.loop

%include "kernel/f64_baremetal.nasm"
