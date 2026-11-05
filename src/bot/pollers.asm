default rel

global bot_poller_set_init
global bot_poller_set_add
global bot_poller_set_connection
global bot_poller_set_poll_all

; Poller entry: 40 bytes
; +0 start(ctx), +8 stop(ctx), +16 poll(ctx, contexts, count)
; +24 opaque ctx, +32 active uint32, +36 reserved.
; State: 24 bytes: +0 connection_count, +8 entries, +16 entry_count.
; All storage is caller-owned. No internal threads/timers are created.
; The application scheduler calls bot_poller_set_poll_all at each due tick.

section .text
; void bot_poller_set_init(state, entries, count)
bot_poller_set_init:
    test rdi, rdi
    jz .init_done
    mov qword [rdi], 0
    mov [rdi + 8], rsi
    mov [rdi + 16], rdx
    test rsi, rsi
    jz .init_done
    xor ecx, ecx
.init_clear:
    cmp rcx, rdx
    jae .init_done
    mov rax, rcx
    imul rax, 40
    mov dword [rsi + rax + 32], 0
    inc rcx
    jmp .init_clear
.init_done:
    ret

; int bot_poller_set_add(state, entry_index)
; Registers an entry; if connected, starts it immediately.
bot_poller_set_add:
    test rdi, rdi
    jz .add_error
    mov rax, [rdi + 16]
    cmp rsi, rax
    jae .add_error
    mov rdx, [rdi + 8]
    test rdx, rdx
    jz .add_error
    imul rax, rsi, 40
    lea rdx, [rdx + rax]
    cmp dword [rdx + 32], 0
    jne .add_ok
    cmp qword [rdi], 0
    je .add_ok
    mov dword [rdx + 32], 1
    push rbx
    mov rbx, rdx
    mov rax, [rbx]
    test rax, rax
    jz .add_started
    mov rdi, [rbx + 24]
    call rax
.add_started:
    pop rbx
.add_ok:
    xor eax, eax
    ret
.add_error:
    mov eax, -1
    ret

; int bot_poller_set_connection(state, connected)
; connected is nonzero for a connection event, zero for disconnect.
; Pollers start on transition 0->1 and stop on 1->0.
bot_poller_set_connection:
    test rdi, rdi
    jz .conn_error
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, [r12]
    test r13, r13
    jz .disconnect
    inc qword [r12]
    test r14, r14
    jnz .conn_success
    mov rbx, 0
.start_loop:
    cmp rbx, [r12 + 16]
    jae .conn_success
    mov rax, [r12 + 8]
    test rax, rax
    jz .conn_success
    imul rdx, rbx, 40
    lea rdi, [rax + rdx]
    cmp dword [rdi + 32], 0
    jne .start_next
    mov dword [rdi + 32], 1
    mov rax, [rdi]
    test rax, rax
    jz .start_next
    push rdi
    sub rsp, 8
    mov rdi, [rdi + 24]
    call rax
    add rsp, 8
    pop rdi
.start_next:
    inc rbx
    jmp .start_loop

.disconnect:
    test r14, r14
    jz .conn_success
    dec qword [r12]
    cmp qword [r12], 0
    jne .conn_success
    xor ebx, ebx
.stop_loop:
    cmp rbx, [r12 + 16]
    jae .conn_success
    mov rax, [r12 + 8]
    test rax, rax
    jz .conn_success
    imul rdx, rbx, 40
    lea rdi, [rax + rdx]
    cmp dword [rdi + 32], 0
    je .stop_next
    mov dword [rdi + 32], 0
    mov rax, [rdi + 8]
    test rax, rax
    jz .stop_next
    push rdi
    mov rdi, [rdi + 24]
    call rax
    pop rdi
.stop_next:
    inc rbx
    jmp .stop_loop
.conn_success:
    xor eax, eax
    jmp .conn_return
.conn_error:
    mov eax, -1
    ret
.conn_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int bot_poller_set_poll_all(state, contexts, context_count)
; Calls active pollers in registration order; returns number invoked.
bot_poller_set_poll_all:
    test rdi, rdi
    jz .poll_error
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
    xor r15d, r15d
.poll_loop:
    cmp rbx, [r12 + 16]
    jae .poll_done
    mov rax, [r12 + 8]
    test rax, rax
    jz .poll_done
    imul rdx, rbx, 40
    lea rdi, [rax + rdx]
    cmp dword [rdi + 32], 0
    je .poll_next
    mov rax, [rdi + 16]
    test rax, rax
    jz .poll_next
    push rdi
    mov rdi, [rdi + 24]
    mov rsi, r13
    mov rdx, r14
    call rax
    pop rdi
    inc r15d
.poll_next:
    inc rbx
    jmp .poll_loop
.poll_done:
    mov eax, r15d
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.poll_error:
    mov eax, -1
    ret
.poll_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
