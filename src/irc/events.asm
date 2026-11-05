default rel

global irc_event_dispatch
global irc_session_dispatch_next
extern str_ascii_casecmp_n
extern irc_session_next

; int64_t irc_event_dispatch(const struct irc_event_handler *entries,
;     uint64_t count, const char *line, uint64_t line_len,
;     const struct irc_message *message)
;
; Handler entry (32 bytes):
;   +0 command pointer, +8 command length,
;   +16 callback pointer, +24 callback context.
; Callback ABI:
;   void callback(void *ctx, const char *line, size_t line_len,
;                 const struct irc_message *message)
; All handlers registered for the matching command are invoked in order.
; Returns invocation count, or -1 for invalid top-level arguments.
%define ENTRY_SIZE 32
%define MSG_COMMAND_OFFSET 16
%define MSG_COMMAND_LENGTH 20

section .text
irc_event_dispatch:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24

    mov r12, rdi                ; entries
    mov r13, rsi                ; count
    mov r14, rdx                ; original line
    mov r15, rcx                ; line length
    mov rbx, r8                 ; parsed message

    test rbx, rbx
    jz .invalid
    test r14, r14
    jz .invalid
    test r12, r12
    jz .invalid
    mov r10d, [rbx + MSG_COMMAND_LENGTH]
    test r10d, r10d
    jz .invalid
    mov r11d, [rbx + MSG_COMMAND_OFFSET]
    cmp r11, r15
    jae .invalid
    mov rax, r15
    sub rax, r11
    cmp r10, rax
    ja .invalid
    mov eax, r10d
    shl rax, 32
    or rax, r11
    mov [rbp - 64], rax   ; packed command offset/length

    mov qword [rbp - 48], 0     ; invocation count
    mov qword [rbp - 56], 0     ; entry index
.loop:
    mov r9, [rbp - 56]
    cmp r9, r13
    jae .done
    mov rax, r9
    shl rax, 5
    lea rdi, [r12 + rax]
    mov rdx, [rdi + 8]
    mov rax, [rbp - 64]
    shr rax, 32
    cmp rdx, rax
    jne .next
    mov rsi, [rdi]
    test rsi, rsi
    jz .next
    mov rax, [rbp - 64]
    mov r10d, eax
    shr rax, 32
    mov r11d, eax
    mov rdi, rsi
    lea rsi, [r14 + r10]
    mov edx, r11d
    call str_ascii_casecmp_n
    test eax, eax
    jne .next

    ; Reload caller-clobbered loop state after the comparison call.
    mov r9, [rbp - 56]
    mov rax, r9
    shl rax, 5
    lea rdi, [r12 + rax]
    mov rax, [rdi + 16]
    test rax, rax
    jz .next
    mov rdi, [rdi + 24]
    mov rsi, r14
    mov rdx, r15
    mov rcx, rbx
    call rax
    inc qword [rbp - 48]
.next:
    inc qword [rbp - 56]
    jmp .loop
.done:
    mov rax, [rbp - 48]
    jmp .return
.invalid:
    mov rax, -1
.return:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; int64_t irc_session_dispatch_next(fd, line, capacity, message,
;                                   handlers, handler_count)
; Receives and parses the next non-PING event, then dispatches it. Returns
; 0 for EOF, -1 for transport/parse/argument failure, or the number of
; callbacks invoked (zero is a valid event with no registered handler).
irc_session_dispatch_next:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24

    mov r12d, edi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov [rbp - 48], r9

    mov edi, r12d
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call irc_session_next
    test eax, eax
    jle .dispatch_return
    mov [rbp - 56], rax

    mov rdi, rbx
    mov rsi, [rbp - 48]
    mov rdx, r13
    mov rcx, [rbp - 56]
    mov r8, r15
    call irc_event_dispatch
.dispatch_return:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
