; INTERRUPT SERVICE ROUTINES
BITS 64 

;---Initialized data----------------------------------------------------------
systimer_ticks dq 0
tasktimer_ticks dq 0
keyboard_scancode dq 0
error_code_low dw 0
error_code_high dw 0
shift_state db 0
use_arrows db 0

int_message dw 17
db 'Interrupt raised!'

division_by_zero_message dw 17
db 'Division by zero!'

invalid_opcode_message dw 15
db 'Invalid Opcode!'

gpf_message dw 25
db 'General Protection Fault!'

pf_message dw 11
db 'Page Fault!'

alignment_check_message dw 26
db 'Alignment Check Exception!'

fault_rip_message dw 5
db ' RIP '

fault_extra_message dw 7
db ' EXTRA '

; PS/2 Set 1 Scancode-to-ASCII Tables (128 bytes each: 0x00 .. 0x7F)
; Non-printable / modifier keys are 0 so the ISR can ignore them with `test al, al / jz .done`.
kbd_map_unshifted:
    db 0, 27                                                 ; 0x00: None, 0x01: ESC
    db '1','2','3','4','5','6','7','8','9','0','-','='       ; 0x02..0x0D: Top number row
    db 0x08, 0x09                                            ; 0x0E: Backspace, 0x0F: Tab
    db 'q','w','e','r','t','y','u','i','o','p','[',']'       ; 0x10..0x1B: QWERTY row
    db 0x0A, 0                                               ; 0x1C: Enter (\n), 0x1D: Left Ctrl
    db 'a','s','d','f','g','h','j','k','l',';',"'"           ; 0x1E..0x28: Home row
    db '`', 0, 0x5C                                          ; 0x29: `, 0x2A: LShift, 0x2B: backslash
    db 'z','x','c','v','b','n','m',',','.','/'               ; 0x2C..0x35: Bottom row
    db 0, '*', 0, ' '                                        ; 0x36: RShift, 0x37: KP*, 0x38: LAlt, 0x39: Space
    times 14 db 0                                            ; 0x3A..0x47
    db 0x80, 0x84, 0, 0x82, 0, 0x83, 0, 0, 0x81, 0x85        ; 0x48: Up, PGUP, 0, Left, 0, Right, PGDN
    times 46 db 0                                            ; 0x52..0x7F: Unused

kbd_map_shifted:
    db 0, 27                                                 ; 0x00: None, 0x01: ESC
    db '!','@','#','$','%','^','&','*','(',')','_','+'       ; 0x02..0x0D: Shifted number row
    db 0x08, 0x09                                            ; 0x0E: Backspace, 0x0F: Tab
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}'       ; 0x10..0x1B: Shifted QWERTY row
    db 0x0A, 0                                               ; 0x1C: Enter (\n), 0x1D: Left Ctrl
    db 'A','S','D','F','G','H','J','K','L',':','"'           ; 0x1E..0x28: Shifted home row (: and ")
    db '~', 0, '|'                                           ; 0x29: ~, 0x2A: LShift, 0x2B: |
    db 'Z','X','C','V','B','N','M','<','>','?'               ; 0x2C..0x35: Shifted bottom row
    db 0, '*', 0, ' '                                        ; 0x36: RShift, 0x37: KP*, 0x38: LAlt, 0x39: Space
    times 70 db 0                                            ; 0x3A..0x7F: F-keys, arrows, etc.

; ring buffer of raw scancodes (every byte from port 0x60, with key
; releases and 0xE0/0xE1 prefixes). Native programs, such as DOOM, read it
; through the kernel service table (see Kernel_services in kernel.nasm).
scan_ring_write_pos db 0
scan_ring:
    times 256 db 0

; ring buffer for keyboard input
ring_buffer_write_pos db 0
ring_buffer_read_pos db 0
ring_buffer:
    times 256 db 0

;---Code------------------------------------------------------------------------
ISR_dummy:
;***************************************************************************;
; Just a dummy generic handler. It prints the message "Interrupt raised!".  ;
;***************************************************************************;
    push rax
    push r8
    push r9
    push rsi
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 1
    mov r9, 1
    mov rsi, int_message
    call vga_print
    pop rsi
    pop r9
    pop r8
    pop rax
    .halt: hlt
    jmp .halt ; Infinite loop
    iretq
    

ISR_Division_by_Zero:
;***************************************************************************;
; Division by zero handler (no error code: [rsp] = RIP)                     ;
;***************************************************************************;
    mov rsi, division_by_zero_message
    mov r10, [rsp]
    xor r11, r11
    jmp Fault_report


ISR_Invalid_Opcode:
;***************************************************************************;
; Invalid Opcode handler (no error code: [rsp] = RIP)                       ;
;***************************************************************************;
    mov rsi, invalid_opcode_message
    mov r10, [rsp]
    xor r11, r11
    jmp Fault_report


ISR_GPF:
;***************************************************************************;
; General Protection Fault handler ([rsp] = error code, [rsp+8] = RIP)      ;
;***************************************************************************;
    mov rsi, gpf_message
    mov r10, [rsp + 8]
    mov r11, [rsp]
    jmp Fault_report


ISR_Page_Fault:
;***************************************************************************;
; Page Fault handler ([rsp] = error code, [rsp+8] = RIP, CR2 = address)     ;
;***************************************************************************;
    mov rsi, pf_message
    mov r10, [rsp + 8]
    mov r11, cr2
    jmp Fault_report


ISR_Alignment_Check:
;***************************************************************************;
; Alignment Check handler ([rsp] = error code, [rsp+8] = RIP)               ;
;***************************************************************************;
    mov rsi, alignment_check_message
    mov r10, [rsp + 8]
    mov r11, [rsp]
    jmp Fault_report


Fault_report:
;***************************************************************************;
; Show a CPU fault on the VGA console (row 2) and on COM1, then halt.       ;
; The serial copy is visible when the screen is in a graphics mode.         ;
;---------------------------------------------------------------------------;
; rsi: fault message (length-prefixed string)                               ;
; r10: RIP of the faulting instruction                                      ;
; r11: extra value (error code or CR2)                                      ;
;***************************************************************************;
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 1
    mov r9, 2
    call vga_print
    call serial_print
    mov rsi, fault_rip_message
    call serial_print
    call serial_print_hex
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 1
    mov r9, 3
    mov rsi, fault_rip_message
    call vga_print
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 6
    mov r9, 3
    call vga_print_hex
    mov r10, r11
    mov rsi, fault_extra_message
    call serial_print
    call serial_print_hex
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 24
    mov r9, 3
    mov rsi, fault_extra_message
    call vga_print
    mov ah, (VGA_COLOR_RED << 4) | VGA_COLOR_LIGHT_BROWN
    mov r8, 31
    mov r9, 3
    call vga_print_hex
    mov al, 10
    call serial_putc
    .halt: hlt
    jmp .halt ; Infinite loop


serial_putc:
;***************************************************************************;
; Write the byte in al to COM1 (0x3F8). Waits for the transmit buffer.      ;
;***************************************************************************;
    push rdx
    push rax
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    pop rax
    mov dx, 0x3F8
    out dx, al
    pop rdx
    ret


serial_print:
;***************************************************************************;
; Write a length-prefixed string (rsi) to COM1.                             ;
;***************************************************************************;
    push rax
    push rcx
    push rsi
    movzx rcx, word [rsi]
    add rsi, 2
.loop:
    test rcx, rcx
    jz .done
    lodsb
    call serial_putc
    dec rcx
    jmp .loop
.done:
    pop rsi
    pop rcx
    pop rax
    ret


serial_print_hex:
;***************************************************************************;
; Write r10 to COM1 as 16 hexadecimal digits.                               ;
;***************************************************************************;
    push rax
    push rcx
    push r10
    mov rcx, 16
.loop:
    rol r10, 4
    mov al, r10b
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .out
    add al, 'A' - '9' - 1
.out:
    call serial_putc
    dec rcx
    jnz .loop
    pop r10
    pop rcx
    pop rax
    ret


ISR_systimer:
;*****************************************************************************;
; System Timer Interrupt Service Routine (IRQ0 mapped to INT 0x20)            ;
;*****************************************************************************;
    inc qword [abs systimer_ticks]
    inc qword [abs tasktimer_ticks]
    cmp qword [abs tasktimer_ticks], 1 ; Every how many ticks we want to switch tasks.
    jle .no_switch
    cmp [abs num_tasks], 0             ; No tasks to switch
    je .no_switch
   
    ; set tasktimer_ticks to 0
    mov qword [abs tasktimer_ticks], 0
    ; In long mode, when an interrupt occurs, the processor pushes in the stack
    ; the interrupted program's stack pointer (SS:RSP), the RFLAGS, and the
    ; return pointer (CS:RIP). In order to switch task, we have to replace them.
    ; Therefore, we remove (pop) them from the stack.
    pop qword [abs return_address] ; RIP
    pop qword [abs code_segment]   ; CS
    pop qword [abs rflags]         ; RFLAGS
    pop qword [abs stack_pointer]  ; RSP
    pop qword [abs stack_segment]  ; SS
    ; We save the current task state in the active task slot.
    call Save_task_state
    ; We activate the next task slot
    inc qword [abs active_task_slot]
    ; We check if the current task was the last task.
    mov rax, [abs num_tasks]
    cmp [abs active_task_slot], rax
    jnz .load
    ; If we reach the last task, switch to the first task
    mov qword [abs active_task_slot], 0
   .load:
    ; Load the next task state from the active task slot.
    call Load_task_state
    ; We now push back to the stack the values we have loaded for the next task.
    push qword [abs stack_segment]
    push qword [abs stack_pointer]
    push qword [abs rflags]
    push qword [abs code_segment]
    push qword [abs return_address] 
    ; The instruction IRETQ will load these values to the proper registers
    ; and we will switch to the next task.        
        
.no_switch:
    push rax
    mov al, PIC_EOI       ; Send EOI (End of Interrupt) command
    out PIC1_COMMAND, al  
    pop rax        
    iretq


ISR_keyboard:
;*****************************************************************************;
; Keyboard Controller Interrupt Service Routine (IRQ1 mapped to INT 0x21)     ;
;*****************************************************************************;
    push rax
    push rbx
    push rcx
    xor rax, rax
    ; bit 5 of the 8042 status is set when the byte comes from the PS/2 mouse.
    in al, 0x64
    mov ah, al
    ; we MUST read the byte from keyboard (or else we get no more interrupts!).
    in al, 0x60
    ; ignore mouse bytes: they are not scancodes
    test ah, 0x20
    jnz ISR_keyboard.done
    xor ah, ah
    ; store the raw scancode for native programs
    movzx rbx, byte [scan_ring_write_pos]
    mov rcx, scan_ring
    mov [rbx + rcx], al
    inc bl
    mov [scan_ring_write_pos], bl
    ; check for left/right shift keys being pressed
    cmp al, 0x2A
    je ISR_keyboard.shift
    cmp al, 0x36
    je ISR_keyboard.shift
    ; check for left/right shift keys being released
    cmp al, 0xAA
    je ISR_keyboard.unshift
    cmp al, 0xB6
    je ISR_keyboard.unshift
    ; if the inbound keycode is above the printable chars, we ignore
    test al, 0x80
    jnz ISR_keyboard.done
    ; if we get here, we have a likely usable keypress - lookup and store ascii
    ; first check if we're looking at a shifted or unshifted keymap
    cmp byte [shift_state], 1
    je ISR_keyboard.lookup_shifted
    mov rbx, kbd_map_unshifted
    jmp ISR_keyboard.do_lookup
.lookup_shifted:
    mov rbx, kbd_map_shifted
    ; find the ascii using the offset (based on the keycode) into the lookup table
.do_lookup:
    mov al, [rbx + rax]
    ; if it's a zero, ignore it and leave (there are some ignored keys...)
    test al, al
    jz ISR_keyboard.done
    ; write the ascii value into our ring buffer
    xor rbx, rbx
    mov bl, byte [ring_buffer_write_pos]
    mov rcx, ring_buffer
    mov [rbx + rcx], al
    ; update the pointer into the buffer
    inc bl
    mov [ring_buffer_write_pos], bl
    ; clean up and get out of our interrupt routine...
.done:
    mov al, PIC_EOI      ; Send EOI (End of Interrupt) command
    out PIC1_COMMAND, al
    pop rcx
    pop rbx
    pop rax
    iretq
    ; if shift is pressed, we turn shift_state to "on" (1)
.shift:
    mov [shift_state], byte 1
    jmp ISR_keyboard.done
    ; if shift is released, we turn shift_state to "off" (0)
.unshift:
    mov [shift_state], byte 0
    jmp ISR_keyboard.done

kbd_get_char:
    push rbx
.loop1:
    xor rbx, rbx
    mov al, byte[ring_buffer_write_pos]
    mov bl, byte[ring_buffer_read_pos]
    cmp al, bl
    je kbd_get_char.empty
    mov al, [ring_buffer + rbx]
    inc bl
    mov byte [ring_buffer_read_pos], bl
    pop rbx
    ret
.empty:
    hlt
    jmp kbd_get_char.loop1

