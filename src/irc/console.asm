default rel
global irc_console_run

extern irc_tcp_connect
extern irc_send_registration
extern irc_session_wait_welcome
extern irc_send_join
extern irc_session_next
extern puts
extern close

section .rodata
console_user_realname: db "sp0rkle IRC console", 0
console_connect_error: db "sp0rkle: unable to connect to IRC server", 0
console_register_error: db "sp0rkle: IRC registration failed", 0
console_nick_error: db "sp0rkle: nickname is already in use", 0
console_welcome_error: db "sp0rkle: IRC server closed or registration failed before welcome", 0
console_join_error: db "sp0rkle: unable to join configured channel", 0
console_receive_error: db "sp0rkle: error receiving IRC message", 0

section .text
; int irc_console_run(host, service, nick, channel)
; Connects to one plain-TCP IRC server, registers, waits for 001, joins one
; channel, then prints each non-PING IRC line to stdout until EOF/error.
; Returns 0 on clean disconnect, -1 on connection/protocol/I/O failure.
irc_console_run:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 680

    mov r13, rdi
    mov r14, rsi
    mov r15, rdx
    mov rbx, rcx

    mov rdi, r13
    mov rsi, r14
    call irc_tcp_connect
    test eax, eax
    js .connect_error
    mov r12d, eax

    mov edi, r12d
    mov rsi, r15
    mov rdx, r15
    lea rcx, [rel console_user_realname]
    call irc_send_registration
    test eax, eax
    jnz .register_error

    mov edi, r12d
    mov rsi, rsp
    mov edx, 512
    lea rcx, [rsp + 512]
    call irc_session_wait_welcome
    cmp eax, 1
    je .welcomed
    cmp eax, -2
    je .nick_error
    jmp .welcome_error

.welcomed:
    ; The welcome line was consumed by the registration waiter; show it too.
    mov rdi, rsp
    call puts

    mov edi, r12d
    mov rsi, rbx
    call irc_send_join
    test eax, eax
    jnz .join_error

.receive_loop:
    mov edi, r12d
    mov rsi, rsp
    mov edx, 512
    lea rcx, [rsp + 512]
    call irc_session_next
    test eax, eax
    jz .clean_eof
    js .receive_error
    mov rdi, rsp
    call puts
    jmp .receive_loop

.clean_eof:
    xor ebx, ebx
    jmp .close_socket
.connect_error:
    lea rdi, [rel console_connect_error]
    call puts
    mov ebx, -1
    jmp .return
.register_error:
    lea rdi, [rel console_register_error]
    call puts
    mov ebx, -1
    jmp .close_socket
.nick_error:
    lea rdi, [rel console_nick_error]
    call puts
    mov ebx, -1
    jmp .close_socket
.welcome_error:
    lea rdi, [rel console_welcome_error]
    call puts
    mov ebx, -1
    jmp .close_socket
.join_error:
    lea rdi, [rel console_join_error]
    call puts
    mov ebx, -1
    jmp .close_socket
.receive_error:
    lea rdi, [rel console_receive_error]
    call puts
    mov ebx, -1
.close_socket:
    mov edi, r12d
    call close
    mov eax, ebx
    jmp .done
.return:
    mov eax, ebx
.done:
    add rsp, 680
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
