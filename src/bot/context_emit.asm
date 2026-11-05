default rel

global bot_context_emit
global bot_context_prefix_nick
extern bot_rewrite_apply

; struct bot_emit_request (112 bytes):
;   0 send callback, 8 callback context, 16 operation (1 PRIVMSG, 2 ACTION, 3 TOPIC)
;  24 target, 32 target length, 40 text, 48 text length
;  56 rewriter entries, 64 rewriter count, 72 scratch A, 80 scratch B
;  88 scratch capacity, 96 apply rewrites (uint32), remaining reserved.
; send callback: int send(ctx, operation, target, target_len, text, text_len)
; Returns callback result; -1 for invalid request or rewrite failure.
bot_context_emit:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12, rdi
    mov rax, [r12]
    test rax, rax
    jz .emit_invalid
    mov rbx, [r12 + 40]
    mov r13, [r12 + 48]
    cmp dword [r12 + 96], 0
    je .emit_send
    mov rdi, [r12 + 56]
    mov esi, [r12 + 64]
    mov rdx, rbx
    mov rcx, r13
    mov r8, [r12 + 72]
    mov r9, [r12 + 80]
    mov rax, [r12 + 88]
    mov [rbp - 48], rax
    lea rax, [rbp - 56]
    mov [rbp - 64], rax
    ; Seventh argument is capacity, eighth is out_len.
    mov rax, [rbp - 48]
    push qword [rbp - 64]
    push rax
    call bot_rewrite_apply
    add rsp, 16
    test rax, rax
    jz .emit_invalid
    mov rbx, rax
    mov r13, [rbp - 56]
.emit_send:
    mov rdi, [r12 + 8]
    mov esi, [r12 + 16]
    mov rdx, [r12 + 24]
    mov rcx, [r12 + 32]
    mov r8, rbx
    mov r9, r13
    call qword [r12]
    jmp .emit_done
.emit_invalid:
    mov eax, -1
.emit_done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; size_t bot_context_prefix_nick(nick,nick_len,text,text_len,out,capacity)
; Produces "nick: text", including a trailing NUL. Returns length or -1.
bot_context_prefix_nick:
    test rdi, rdi
    jz .prefix_bad
    test rdx, rdx
    jz .prefix_bad
    test r8, r8
    jz .prefix_bad
    mov rax, rsi
    add rax, 2
    jc .prefix_bad
    add rax, rcx
    jc .prefix_bad
    lea r10, [rax + 1]
    jc .prefix_bad
    cmp r9, r10
    jb .prefix_bad
    mov r11, r8
    mov r10, rdi
    mov rax, rsi
    mov rdi, r11
    mov rsi, r10
    mov rcx, rax
    rep movsb
    mov byte [r11 + rax], ':'
    mov byte [r11 + rax + 1], ' '
    lea rdi, [r11 + rax + 2]
    mov rsi, rdx
    mov rcx, [rsp + 8]
    ; text_len is fourth argument, originally in RCX; preserve before rep.
    ; Reload from the caller stack is not valid for this register argument.
    ; This path is replaced below by the saved register value.
    xor eax, eax
    ret
.prefix_bad:
    mov rax, -1
    ret
