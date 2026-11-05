default rel

global mem_copy
global mem_equal

section .text
; void *mem_copy(void *dst, const void *src, size_t n)
; memcpy semantics: source and destination ranges must not overlap.
; Returns the original destination pointer in RAX.
mem_copy:
    mov rax, rdi
    mov rcx, rdx
    rep movsb
    ret

; int mem_equal(const void *a, const void *b, size_t n)
; Return zero when all n bytes match, otherwise -1 or 1.
mem_equal:
    test rdx, rdx
    jz .equal
    xor ecx, ecx
.loop:
    mov al, [rdi + rcx]
    mov r8b, [rsi + rcx]
    cmp al, r8b
    jb .less
    ja .greater
    inc rcx
    cmp rcx, rdx
    jb .loop
.equal:
    xor eax, eax
    ret
.less:
    mov eax, -1
    ret
.greater:
    mov eax, 1
    ret
