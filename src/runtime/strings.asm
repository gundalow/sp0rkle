default rel

global str_len
global str_ascii_casecmp

section .text
; size_t str_len(const char *s): RDI input, RAX byte length.
str_len:
    xor eax, eax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; int str_ascii_casecmp(const char *a, const char *b)
; ASCII-only, locale-independent comparison; returns -1, 0, or 1.
str_ascii_casecmp:
    xor ecx, ecx
.loop:
    mov al, [rdi + rcx]
    mov dl, [rsi + rcx]
    cmp al, 'A'
    jb .a_ready
    cmp al, 'Z'
    ja .a_ready
    add al, 32
.a_ready:
    cmp dl, 'A'
    jb .b_ready
    cmp dl, 'Z'
    ja .b_ready
    add dl, 32
.b_ready:
    cmp al, dl
    jb .less
    ja .greater
    test al, al
    jz .equal
    inc rcx
    jmp .loop
.less:
    mov eax, -1
    ret
.greater:
    mov eax, 1
    ret
.equal:
    xor eax, eax
    ret
