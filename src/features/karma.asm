default rel

global karma_parse_annotations

; int karma_parse_annotations(text, text_len, out, out_capacity)
; Output entry is 16 bytes: uint64 offset, uint32 length, int32 delta.
; Results are emitted in the same reverse textual order as the Go lexer.
; ASCII alphanumeric tokens and one-level parenthesised multiword tokens
; are supported. Unicode category recognition is not yet implemented.

section .text
karma_parse_annotations:
    test rdi, rdi
    jz .karma_error
    test rdx, rdx
    jz .karma_error
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov r12, rdi                ; input
    mov r13, rsi                ; input length
    mov r14, rdx                ; output
    mov r15, rcx                ; output capacity
    mov [rbp - 48], rsi
    mov rbx, rsi                ; reverse cursor
    mov qword [rbp - 56], 0     ; result count

.scan_prefix:
    test rbx, rbx
    jz .karma_done
    mov [rbp - 64], rbx        ; prefix end
.prefix_loop:
    test rbx, rbx
    jz .prefix_ready
    mov al, [r12 + rbx - 1]
    cmp al, '+'
    je .prefix_ready
    cmp al, '-'
    je .prefix_ready
    dec rbx
    jmp .prefix_loop
.prefix_ready:
    mov rax, [rbp - 64]
    sub rax, rbx
    mov [rbp - 72], rax        ; suffix/prefix length
    test rbx, rbx
    jz .op_scan
    ; When text after the operator is non-empty, it must start with
    ; whitespace (the last byte of the reversed prefix).
    test rax, rax
    jz .op_scan
    mov dl, [r12 + rbx]
    cmp dl, ' '
    je .op_scan
    cmp dl, 9
    jb .skip_operator
    cmp dl, 13
    jbe .op_scan
    jmp .skip_operator

.op_scan:
    mov [rbp - 80], rbx        ; operator end
    movzx eax, byte [r12 + rbx - 1]
    mov [rbp - 84], eax        ; operator sign
.op_loop:
    test rbx, rbx
    jz .op_ready
    movzx eax, byte [r12 + rbx - 1]
    cmp eax, [rbp - 84]
    jne .op_ready
    dec rbx
    jmp .op_loop
.op_ready:
    mov rax, [rbp - 80]
    sub rax, rbx
    cmp rax, 2
    jne .scan_prefix
    cmp dword [rbp - 84], '+'
    je .positive
    cmp dword [rbp - 84], '-'
    jne .scan_prefix
    mov dword [rbp - 88], -1
    jmp .parse_thing
.positive:
    mov dword [rbp - 88], 1

.parse_thing:
    mov [rbp - 80], rbx        ; operator start
    test rbx, rbx
    jz .scan_prefix
    cmp byte [r12 + rbx - 1], ')'
    jne .plain_thing

    ; Parenthesised subject: find the nearest preceding '('.
    mov rax, rbx
    dec rax                    ; skip ')'
    mov [rbp - 96], rax        ; closing bracket index
.bracket_loop:
    test rax, rax
    jz .scan_prefix
    cmp byte [r12 + rax - 1], '('
    je .bracket_found
    dec rax
    jmp .bracket_loop
.bracket_found:
    mov [rbp - 104], rax       ; opening bracket index
    mov rcx, [rbp - 96]
    sub rcx, rax              ; inner length
    test rcx, rcx
    jz .scan_prefix
    mov rdx, [rbp - 56]
    cmp rdx, r15
    jae .karma_error_stack
    imul rdx, rdx, 16
    lea rdi, [r14 + rdx]
    lea r8, [rax]              ; open index
    mov [rdi], r8
    mov [rdi + 8], ecx
    mov eax, [rbp - 88]
    mov [rdi + 12], eax
    inc qword [rbp - 56]
    mov rbx, [rbp - 104]
    jmp .scan_prefix

.plain_thing:
    mov [rbp - 96], rbx
.plain_loop:
    test rbx, rbx
    jz .plain_ready
    movzx eax, byte [r12 + rbx - 1]
    cmp al, '0'
    jb .plain_alpha
    cmp al, '9'
    jbe .plain_consume
.plain_alpha:
    cmp al, 'A'
    jb .plain_lower
    cmp al, 'Z'
    jbe .plain_consume
.plain_lower:
    cmp al, 'a'
    jb .plain_ready
    cmp al, 'z'
    ja .plain_ready
.plain_consume:
    dec rbx
    jmp .plain_loop
.plain_ready:
    mov rax, [rbp - 96]
    sub rax, rbx
    test rax, rax
    jz .scan_prefix
    mov [rbp - 104], rax
    mov rdx, [rbp - 56]
    cmp rdx, r15
    jae .karma_error_stack
    imul rdx, rdx, 16
    lea rdi, [r14 + rdx]
    mov [rdi], rbx
    mov eax, [rbp - 104]
    mov [rdi + 8], eax
    mov eax, [rbp - 88]
    mov [rdi + 12], eax
    inc qword [rbp - 56]
    jmp .scan_prefix

.skip_operator:
    ; Skip this sign run and continue scanning earlier bytes.
    test rbx, rbx
    jz .karma_done
    movzx eax, byte [r12 + rbx - 1]
    cmp al, '+'
    je .skip_signs
    cmp al, '-'
    jne .scan_prefix
.skip_signs:
    mov edx, eax
.skip_sign_loop:
    test rbx, rbx
    jz .scan_prefix
    cmp byte [r12 + rbx - 1], dl
    jne .scan_prefix
    dec rbx
    jmp .skip_sign_loop

.karma_done:
    mov rax, [rbp - 56]
    jmp .karma_return
.karma_error_stack:
    mov rax, -1
.karma_return:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.karma_error:
    mov eax, -1
    ret
