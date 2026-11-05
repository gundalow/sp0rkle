default rel

extern irc_tcp_send_all
global irc_send_context_message

; int irc_send_context_message(fd, operation, target, target_len, text, text_len, scratch, capacity)
; operation: 1 PRIVMSG, 2 ACTION, 3 TOPIC. Returns send_all result or -1.
; Rejects NUL/CR/LF in target or text; target also rejects ASCII space.
section .text
irc_send_context_message:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12d, edi
    mov r13d, esi
    mov r14, rdx
    mov r15, rcx
    mov [rsp + 16], r8
    mov [rsp + 24], r9
    mov rax, [rbp + 16]
    mov [rsp], rax
    mov rax, [rbp + 24]
    mov [rsp + 8], rax
    test r14, r14
    jz .bad
    test r15, r15
    jz .bad
    cmp r13d, 1
    je .priv
    cmp r13d, 2
    je .priv
    cmp r13d, 3
    je .topic
    jmp .bad
.priv:
    mov dword [rsp + 32], 8
    jmp .check_target
.topic:
    mov dword [rsp + 32], 6
.check_target:
    xor ebx, ebx
.tcheck:
    cmp rbx, r15
    jae .check_text
    mov al, [r14 + rbx]
    test al, al
    jz .bad
    cmp al, 10
    je .bad
    cmp al, 13
    je .bad
    cmp al, ' '
    je .bad
    inc rbx
    jmp .tcheck
.check_text:
    mov rcx, [rsp + 24]
    test rcx, rcx
    jz .size
    mov rdx, [rsp + 16]
    test rdx, rdx
    jz .bad
    xor ebx, ebx
.xcheck:
    cmp rbx, [rsp + 24]
    jae .size
    mov al, [rdx + rbx]
    test al, al
    jz .bad
    cmp al, 10
    je .bad
    cmp al, 13
    je .bad
    inc rbx
    jmp .xcheck
.size:
    mov rax, [rsp + 24]
    add rax, r15
    jc .bad
    add rax, 4
    jc .bad
    add rax, [rsp + 32]
    jc .bad
    cmp r13d, 2
    jne .size_ready
    add rax, 9
    jc .bad
.size_ready:
    cmp rax, [rsp + 8]
    ja .bad
    mov [rsp + 32], rax
    mov rdi, [rsp]
    test rdi, rdi
    jz .bad
    xor ebx, ebx
    cmp r13d, 3
    jne .priv_prefix
    mov byte [rdi], 'T'
    mov byte [rdi+1], 'O'
    mov byte [rdi+2], 'P'
    mov byte [rdi+3], 'I'
    mov byte [rdi+4], 'C'
    mov byte [rdi+5], ' '
    mov ebx, 6
    jmp .target_copy
.priv_prefix:
    mov byte [rdi], 'P'
    mov byte [rdi+1], 'R'
    mov byte [rdi+2], 'I'
    mov byte [rdi+3], 'V'
    mov byte [rdi+4], 'M'
    mov byte [rdi+5], 'S'
    mov byte [rdi+6], 'G'
    mov byte [rdi+7], ' '
    mov ebx, 8
.target_copy:
    xor ecx, ecx
.tc:
    cmp rcx, r15
    jae .target_done
    mov al, [r14 + rcx]
    mov [rdi + rbx], al
    inc rbx
    inc rcx
    jmp .tc
.target_done:
    mov byte [rdi + rbx], ' '
    inc rbx
    mov byte [rdi + rbx], ':'
    inc rbx
    cmp r13d, 2
    jne .text_copy_start
    mov byte [rdi + rbx], 1
    mov byte [rdi + rbx + 1], 'A'
    mov byte [rdi + rbx + 2], 'C'
    mov byte [rdi + rbx + 3], 'T'
    mov byte [rdi + rbx + 4], 'I'
    mov byte [rdi + rbx + 5], 'O'
    mov byte [rdi + rbx + 6], 'N'
    mov byte [rdi + rbx + 7], ' '
    add rbx, 8
.text_copy_start:
    mov rsi, [rsp + 16]
    mov rcx, [rsp + 24]
.text_copy:
    test rcx, rcx
    jz .text_done
    mov al, [rsi]
    mov [rdi + rbx], al
    inc rsi
    inc rbx
    dec rcx
    jmp .text_copy
.text_done:
    cmp r13d, 2
    jne .crlf
    mov byte [rdi + rbx], 1
    inc rbx
.crlf:
    mov byte [rdi + rbx], 13
    mov byte [rdi + rbx + 1], 10
    mov edi, r12d
    mov rsi, [rsp]
    mov rdx, [rsp + 32]
    call irc_tcp_send_all
    jmp .ret
.bad:
    mov eax, -1
.ret:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
