default rel

global bot_nick_ignore_should_process
global bot_filter_pipeline_should_process

; int bot_nick_ignore_should_process(nick, nick_len, lookup, lookup_ctx)
; lookup(ctx, lowercase_nick, nick_len) returns nonzero when the ignore
; namespace contains a non-empty value for that nick.
; Empty nick always passes. The callback is invoked with an ASCII-lowercase
; temporary NUL-terminated copy; nick_len remains authoritative.
section .text
bot_nick_ignore_should_process:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx

    test r13, r13
    jz .allow
    test r14, r14
    jz .allow

    ; Keep the stack 16-byte aligned before calling the lookup callback.
    mov rax, r13
    inc rax
    add rax, 15
    and rax, -16
    sub rsp, rax
    mov rbx, rsp
    xor ecx, ecx
.lower:
    cmp rcx, r13
    jae .terminate
    movzx eax, byte [r12 + rcx]
    cmp al, 'A'
    jb .store
    cmp al, 'Z'
    ja .store
    add al, 32
.store:
    mov [rbx + rcx], al
    inc rcx
    jmp .lower
.terminate:
    mov byte [rbx + r13], 0
    mov rdi, r15
    mov rsi, rbx
    mov rdx, r13
    call r14
    test eax, eax
    jnz .blocked
    mov eax, 1
    jmp .restore
.blocked:
    xor eax, eax
.restore:
    ; Recompute the rounded allocation before releasing it.
    mov rax, r13
    inc rax
    add rax, 15
    and rax, -16
    add rsp, rax
    jmp .done
.allow:
    mov eax, 1
.done:
    pop r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; struct bot_line_filter { int (*should_process)(void *ctx,
;                                      const char *nick, size_t nick_len);
;                          void *ctx; }; size 16 bytes.
; int bot_filter_pipeline_should_process(filters, count, nick, nick_len)
; Filters are ANDed and evaluated in registration order; first false stops.
bot_filter_pipeline_should_process:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov rbx, rcx
    xor r15d, r15d
.scan:
    cmp r15d, r13d
    jae .pass
    mov rax, r15
    shl rax, 4
    lea r11, [r12 + rax]
    mov rax, [r11]
    test rax, rax
    jz .next
    mov rdi, [r11 + 8]
    mov rsi, r14
    mov rdx, rbx
    call rax
    test eax, eax
    jz .reject
.next:
    inc r15d
    jmp .scan
.pass:
    mov eax, 1
    jmp .return
.reject:
    xor eax, eax
.return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
