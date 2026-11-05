default rel

global bot_context_emit
global bot_context_prefix_nick

global bot_context_resolve_target

; struct bot_string_view { const char *ptr; size_t len; }
; bot_context_resolve_target(target,target_len,nick,nick_len)
; Mirrors goirc Line.Target(): channel targets (# & + !) remain the target;
; direct messages are replied to the sender nick.
bot_context_resolve_target:
    test rdi, rdi
    jz .target_empty
    test rsi, rsi
    jz .target_private
    mov al, [rdi]
    cmp al, '#'
    je .target_public
    cmp al, '&'
    je .target_public
    cmp al, '+'
    je .target_public
    cmp al, '!'
    je .target_public
.target_private:
    mov rax, rdx
    mov rdx, rcx
    ret
.target_public:
    mov rax, rdi
    mov rdx, rsi
    ret
.target_empty:
    mov rax, rdx
    mov rdx, rcx
    ret
extern bot_rewrite_apply

; struct bot_emit_request (112 bytes):
;   0 send callback, 8 callback context, 16 operation (1 PRIVMSG, 2 ACTION, 3 TOPIC)
;  24 target, 32 target length, 40 text, 48 text length
;  56 rewriter entries, 64 rewriter count, 72 scratch A, 80 scratch B
;  88 scratch capacity, 96 apply rewrites (uint32).
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
    ; Stack arguments 7 and 8: capacity and out_len.
    push qword [rbp - 64]
    push qword [rbp - 48]
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
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rbx, rcx
    test r12, r12
    jz .prefix_bad
    test r14, r14
    jz .prefix_bad
    test r8, r8
    jz .prefix_bad
    mov rax, r13
    add rax, 2
    jc .prefix_bad
    add rax, rbx
    jc .prefix_bad
    lea r10, [rax + 1]
    jc .prefix_bad
    cmp r9, r10
    jb .prefix_bad
    mov rdi, r8
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov byte [rdi], ':'
    mov byte [rdi + 1], ' '
    add rdi, 2
    mov rsi, r14
    mov rcx, rbx
    rep movsb
    mov byte [rdi], 0
    mov rax, r13
    add rax, 2
    add rax, rbx
    jmp .prefix_done
.prefix_bad:
    mov rax, -1
.prefix_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
