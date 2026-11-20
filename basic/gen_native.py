#! /usr/bin/env python
"""Make disk_files/basic/bnative.f, the machine-code words of f64 BASIC.

Each word below is x86-64 code that works directly on the Forth data
stack (RSP points to the top cell). NASM assembles each word. The script
writes the bytes as Forth source:

    CODE F+  M, DD442408DC0424...  M, ...  ALIGN

CODE and M, are defined in disk_files/basic/basic.f. The script adds the
Forth NEXT (lodsq / jmp [rax]) to the end of each word.

Register rules (see kernel/f64_baremetal.nasm): RSI is the Forth
instruction pointer, RBP is the return stack, R15 is the iterator stack.
Do not change them. RAX, RBX, RCX, RDX, RDI and R8-R14 are free.
Interrupts use the current stack, so do not use memory below RSP.

Floating-point numbers are IEEE doubles, one per 64-bit cell. The words
use the x87 FPU. The x87 stack is empty before and after each word.

Usage: python basic/gen_native.py   (from the repository root)
Needs: NASM (on PATH, or in the places that run.ps1 looks).
"""
import os
import shutil
import subprocess
import sys
import tempfile

# 2^st0 -> st0  (x87 macro used by FEXP, FPOW and F10^)
POW2 = """
    fld st0
    frndint
    fsub st1, st0
    fxch st1
    f2xm1
    fld1
    faddp st1, st0
    fscale
    fstp st1
"""

WORDS = [
    # ( a b -- a+b ) and the other three operators
    ('F+', 'fld qword [rsp+8]\n fadd qword [rsp]\n add rsp, 8\n fstp qword [rsp]'),
    ('F-', 'fld qword [rsp+8]\n fsub qword [rsp]\n add rsp, 8\n fstp qword [rsp]'),
    ('F*', 'fld qword [rsp+8]\n fmul qword [rsp]\n add rsp, 8\n fstp qword [rsp]'),
    ('F/', 'fld qword [rsp+8]\n fdiv qword [rsp]\n add rsp, 8\n fstp qword [rsp]'),
    # ( f -- -f ) ( f -- |f| )
    ('FNEGATE', 'btc qword [rsp], 63'),
    ('FABS', 'btr qword [rsp], 63'),
    # ( n -- f ) integer to float
    ('S>F', 'fild qword [rsp]\n fstp qword [rsp]'),
    # ( f -- n ) float to integer, round to nearest
    ('FROUND>S', 'fld qword [rsp]\n fistp qword [rsp]'),
    # ( f -- f ) round down to a whole number
    ('FFLOOR', """
    fld qword [rsp]
    sub rsp, 8
    fnstcw [rsp]
    mov ax, [rsp]
    and ax, 0xF3FF
    or ax, 0x0400
    mov [rsp+2], ax
    fldcw [rsp+2]
    frndint
    fldcw [rsp]
    add rsp, 8
    fstp qword [rsp]"""),
    # ( a b -- n ) n = -1 if a<b, 0 if a=b, 1 if a>b
    ('FCMP', """
    fld qword [rsp]
    fld qword [rsp+8]
    add rsp, 8
    fcomip st0, st1
    fstp st0
    seta al
    setb cl
    sub al, cl
    movsx rax, al
    mov [rsp], rax"""),
    ('FSQRT', 'fld qword [rsp]\n fsqrt\n fstp qword [rsp]'),
    ('FSIN', 'fld qword [rsp]\n fsin\n fstp qword [rsp]'),
    ('FCOS', 'fld qword [rsp]\n fcos\n fstp qword [rsp]'),
    ('FTAN', 'fld qword [rsp]\n fptan\n fstp st0\n fstp qword [rsp]'),
    ('FATAN', 'fld qword [rsp]\n fld1\n fpatan\n fstp qword [rsp]'),
    # natural logarithm and base-10 logarithm (argument must be > 0)
    ('FLN', 'fldln2\n fld qword [rsp]\n fyl2x\n fstp qword [rsp]'),
    ('FLOG10', 'fldlg2\n fld qword [rsp]\n fyl2x\n fstp qword [rsp]'),
    # ( f -- e^f )
    ('FEXP', 'fld qword [rsp]\n fldl2e\n fmulp st1, st0\n' + POW2 +
     ' fstp qword [rsp]'),
    # ( x y -- x^y ) x must be > 0
    ('FPOW', 'fld qword [rsp]\n fld qword [rsp+8]\n fyl2x\n' + POW2 +
     ' add rsp, 8\n fstp qword [rsp]'),
    # ( n -- f ) f = 10^n
    ('F10^', 'fild qword [rsp]\n fldl2t\n fmulp st1, st0\n' + POW2 +
     ' fstp qword [rsp]'),
    # ( -- ) reset the FPU: round to nearest, 64-bit precision, no traps
    ('FINIT', 'fninit'),
    # ( x n -- x<<n ) ( x n -- x>>n ) logical shifts
    ('LSHIFT', 'pop rcx\n shl qword [rsp], cl'),
    ('RSHIFT', 'pop rcx\n shr qword [rsp], cl'),
    # ( u1 u2 -- flag ) unsigned u1 < u2
    ('U<', 'pop rax\n cmp [rsp], rax\n setb al\n movzx rax, al\n mov [rsp], rax'),
    # ( addr len byte -- ) fill memory
    ('FILL', 'pop rax\n pop rcx\n pop rdi\n rep stosb'),
    # ( src dst len -- ) copy from the end (for dst > src overlap)
    ('CMOVE>', """
    pop rcx
    pop rdi
    pop rax
    mov rdx, rsi
    lea rsi, [rax+rcx-1]
    lea rdi, [rdi+rcx-1]
    std
    rep movsb
    cld
    mov rsi, rdx"""),
    # ( -- ) wait for the next interrupt (timer or key)
    ('HALT', 'sti\n hlt'),
    # ( glyph fg bg dest -- ) draw one 8x8 character cell in mode 13h
    ('DRAW-CELL', """
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    mov r8d, 8
.row:
    movzx eax, byte [rbx]
    inc rbx
    mov r9d, 8
.col:
    mov r10d, edx
    shl al, 1
    cmovc r10d, ecx
    mov [rdi], r10b
    inc rdi
    dec r9d
    jnz .col
    add rdi, 312
    dec r8d
    jnz .row"""),
]

NEXT = bytes([0x48, 0xAD, 0xFF, 0x20])   # lodsq ; jmp [rax]


def find_nasm():
    for c in (shutil.which('nasm'),
              os.path.expandvars(r'%LOCALAPPDATA%\bin\NASM\nasm.exe'),
              os.path.expandvars(r'%ProgramFiles%\NASM\nasm.exe')):
        if c and os.path.exists(c):
            return c
    sys.exit('nasm not found')


def assemble(nasm, name, body):
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, 'w.nasm')
        out = os.path.join(tmp, 'w.bin')
        with open(src, 'w') as f:
            f.write('BITS 64\n' + body + '\n')
        r = subprocess.run([nasm, '-fbin', src, '-o', out],
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit('%s: %s' % (name, r.stderr))
        return open(out, 'rb').read() + NEXT


def main():
    nasm = find_nasm()
    lines = ['( f64 BASIC V2 - bnative.f: machine-code words )',
             '( Made by basic/gen_native.py. Do not edit. )',
             'DECIMAL']
    for name, body in WORDS:
        code = assemble(nasm, name, body).hex().upper()
        chunks = ['M, ' + code[i:i + 32] for i in range(0, len(code), 32)]
        lines.append('CODE %s %s ALIGN' % (name, ' '.join(chunks)))
    lines.append('INCLUDE bfloat.f')
    path = os.path.join('disk_files', 'basic', 'bnative.f')
    with open(path, 'w', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print('wrote', path)


if __name__ == '__main__':
    main()
