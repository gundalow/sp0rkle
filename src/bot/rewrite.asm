default rel

global bot_rewrite_apply

; struct bot_rewriter { rewrite_fn fn; void *ctx; }; 16 bytes.
; rewrite_fn(ctx, input, input_len, output, output_capacity) -> ssize_t.
; The callback writes at most capacity-1 bytes and returns their length.
;
; const char *bot_rewrite_apply(entries, count, input, input_len,
;                               scratch_a, scratch_b, capacity, out_len)
; Applies callbacks in registration order. Alternates the two caller-owned
; scratch buffers. Returns the final string pointer or NULL on error.
; With zero callbacks, returns input unchanged. out_len is required.
section .text
bot_rewrite_apply:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72

    mov r12, rdi                ; entries
    mov r13d, esi               ; count
    mov r14, rdx                ; current input
    mov r15, rcx                ; current length
    mov rbx, r8                 ; scratch A
    mov [rbp - 48], r9          ; scratch B
    mov rax, [rbp + 16]         ; capacity
    mov [rbp - 56], rax
    mov rax, [rbp + 24]         ; out_len
    mov [rbp - 64], rax
    mov qword [rbp - 72], 0     ; entry index
    mov qword [rbp - 80], 0     ; use A flag

    cmp qword [rbp - 64], 0
    je .rewrite_error
    mov rax, [rbp - 64]
    mov qword [rax], 0
    test r13d, r13d
    jz .rewrite_identity

.rewrite_loop:
    mov eax, [rbp - 72]
    cmp eax, r13d
    jae .rewrite_done
    mov rax, [rbp - 72]
    shl rax, 4
    lea rdx, [r12 + rax]
    mov rax, [rdx]              ; callback
    test rax, rax
    jz .rewrite_next
    mov [rbp - 96], rax
    mov rax, [rdx + 8]
    mov [rbp - 104], rax

    ; Choose alternating destination.
    cmp qword [rbp - 80], 0
    jne .use_b
    mov r8, rbx                 ; output A
    mov qword [rbp - 80], 1
    jmp .invoke
.use_b:
    mov r8, [rbp - 48]          ; output B
    mov qword [rbp - 80], 0
.invoke:
    test r8, r8
    jz .rewrite_error
    mov [rbp - 88], r8          ; selected output buffer
    mov rdi, [rbp - 104]        ; callback context
    mov rsi, r14                ; current input
    mov rdx, r15                ; current length
    mov rcx, [rbp - 88]         ; output buffer
    mov r8, [rbp - 56]          ; output capacity
    mov rax, [rbp - 96]         ; callback
    call rax
    test rax, rax
    js .rewrite_error
    cmp rax, [rbp - 56]
    jae .rewrite_error
    mov rdx, [rbp - 88]
    mov byte [rdx + rax], 0
    mov r14, rdx
    mov r15, rax

.rewrite_next:
    inc qword [rbp - 72]
    jmp .rewrite_loop

.rewrite_identity:
    mov rax, [rbp - 64]
    mov [rax], r15
    mov rax, r14
    jmp .rewrite_return
.rewrite_done:
    mov rax, [rbp - 64]
    mov [rax], r15
    mov rax, r14
    jmp .rewrite_return
.rewrite_error:
    xor eax, eax
.rewrite_return:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
