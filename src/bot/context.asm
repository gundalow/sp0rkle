default rel

global bot_strip_address_prefix

; int bot_strip_address_prefix(text, text_len, nick, nick_len,
;                              out_start, out_len)
; RDI=text, RSI=text_len, RDX=nick, RCX=nick_len,
; R8=out_start (size_t*), R9=out_len (size_t*).
; Returns 1 when text begins with nick followed by one of : ; , > -
; and optional surrounding ASCII whitespace is trimmed from the remainder.
; Returns 0 otherwise and writes zero outputs. Does not modify input.
; Private-message addressing (target == bot nick) is decided by caller.

section .text
bot_strip_address_prefix:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    test rbx, rbx
    jz .zero_len
    mov qword [rbx], 0
.zero_len:
    test r9, r9
    jz .check
    mov qword [r9], 0
.check:
    test r15, r15
    jz .no
    lea rax, [r15 + 1]
    cmp r13, rax
    jb .no
    xor r10d, r10d
.compare:
    cmp r10, r15
    jae .delimiter
    movzx eax, byte [r12 + r10]
    movzx edx, byte [r14 + r10]
    cmp al, 'A'
    jb .text_lower
    cmp al, 'Z'
    ja .text_lower
    add al, 32
.text_lower:
    cmp dl, 'A'
    jb .nick_lower
    cmp dl, 'Z'
    ja .nick_lower
    add dl, 32
.nick_lower:
    cmp al, dl
    jne .no
    inc r10
    jmp .compare
.delimiter:
    mov al, [r12 + r15]
    cmp al, ':'
    je .trim
    cmp al, ';'
    je .trim
    cmp al, ','
    je .trim
    cmp al, '>'
    je .trim
    cmp al, '-'
    jne .no
.trim:
    lea r10, [r15 + 1]
    mov r11, r13
    ; trim leading ASCII whitespace
.leading:
    cmp r10, r11
    jae .empty
    mov al, [r12 + r10]
    cmp al, ' '
    je .lead_one
    cmp al, 9
    jb .trailing
    cmp al, 13
    jbe .lead_one
    jmp .trailing
.lead_one:
    inc r10
    jmp .leading
.trailing:
    test r11, r11
    jz .store
    lea rax, [r11 - 1]
    cmp rax, r10
    jb .store
    movzx ecx, byte [r12 + rax]
    cmp cl, ' '
    je .trail_more
    cmp cl, 9
    jb .store
    cmp cl, 13
    jbe .trail_more
    jmp .store
.trail_more:
    mov r11, rax
    jmp .trailing
.empty:
    mov r11, r10
.store:
    test rbx, rbx
    jz .store_len
    mov [rbx], r10
.store_len:
    test r9, r9
    jz .yes
    mov rax, r11
    sub rax, r10
    mov [r9], rax
.yes:
    mov eax, 1
    jmp .done
.no:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
