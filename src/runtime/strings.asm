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

; size_t strn_len(const char *s, size_t max_len)
; Return the first NUL position, or max_len when no NUL occurs in range.
global strn_len
strn_len:
    xor eax, eax
.loop:
    cmp rax, rsi
    jae .done
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; int str_ascii_casecmp_n(const char *a, const char *b, size_t n)
; Compare at most n bytes, ASCII case-insensitively.
global str_ascii_casecmp_n
str_ascii_casecmp_n:
    xor ecx, ecx
.loop:
    cmp rcx, rdx
    jae .equal
    movzx eax, byte [rdi + rcx]
    movzx r8d, byte [rsi + rcx]
    cmp al, 'A'
    jb .a_ready
    cmp al, 'Z'
    ja .a_ready
    add al, 32
.a_ready:
    cmp r8b, 'A'
    jb .b_ready
    cmp r8b, 'Z'
    ja .b_ready
    add r8b, 32
.b_ready:
    cmp al, r8b
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
