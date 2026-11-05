default rel

global irc_tcp_connect
global irc_tcp_send_all
global irc_tcp_recv_line

extern getaddrinfo
extern freeaddrinfo
extern socket
extern connect
extern close
extern send
extern recv

section .text

; int irc_tcp_connect(const char *host, const char *service)
; RDI=host, RSI=decimal service/port string. Returns connected fd or -1.
; Tries each address returned by getaddrinfo(AF_UNSPEC, SOCK_STREAM).
irc_tcp_connect:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56

    mov r12, rdi                ; host
    mov r13, rsi                ; service

    ; struct addrinfo hints = { .ai_socktype = SOCK_STREAM };
    lea rdi, [rsp]
    xor eax, eax
    mov ecx, 6
    rep stosq
    mov dword [rsp + 8], 1      ; SOCK_STREAM
    mov qword [rsp + 48], 0     ; result pointer

    mov rdi, r12
    mov rsi, r13
    lea rdx, [rsp]
    lea rcx, [rsp + 48]
    call getaddrinfo
    test eax, eax
    jnz .connect_failed

    mov r14, [rsp + 48]         ; addrinfo list head
    mov rbx, r14
.try_address:
    test rbx, rbx
    jz .all_failed

    mov edi, [rbx + 4]          ; ai_family
    mov esi, [rbx + 8]          ; ai_socktype
    mov edx, [rbx + 12]         ; ai_protocol
    call socket
    test eax, eax
    js .next_address
    mov r15d, eax               ; candidate fd

    mov edi, r15d
    mov rsi, [rbx + 24]         ; ai_addr
    mov edx, [rbx + 16]        ; ai_addrlen
    call connect
    test eax, eax
    jz .connected

    mov edi, r15d
    call close
.next_address:
    mov rbx, [rbx + 40]         ; ai_next
    jmp .try_address

.connected:
    mov rdi, r14
    call freeaddrinfo
    mov eax, r15d
    jmp .return

.all_failed:
    mov rdi, r14
    call freeaddrinfo
.connect_failed:
    mov eax, -1
.return:
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int irc_tcp_send_all(int fd, const void *buf, size_t len)
; Returns 0 after all bytes are sent, or -1 on error/closed connection.
; MSG_NOSIGNAL prevents a broken peer from terminating the process via SIGPIPE.
irc_tcp_send_all:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8

    mov r12d, edi
    mov r13, rsi
    mov rbx, rdx
.send_loop:
    test rbx, rbx
    jz .send_ok
    mov edi, r12d
    mov rsi, r13
    mov rdx, rbx
    mov ecx, 0x4000             ; MSG_NOSIGNAL
    call send
    test rax, rax
    jle .send_error
    add r13, rax
    sub rbx, rax
    jmp .send_loop
.send_ok:
    xor eax, eax
    jmp .send_return
.send_error:
    mov eax, -1
.send_return:
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ssize_t irc_tcp_recv_line(int fd, char *buf, size_t capacity)
; Reads through LF, strips one preceding CR, NUL-terminates and returns the
; payload length. Returns 0 on clean EOF before any bytes, -1 on error,
; truncated EOF, or a line that does not fit. Capacity includes the NUL byte.
; This deliberately simple first version receives one byte per recv call.
irc_tcp_recv_line:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
    test r14, r14
    jz .recv_error
.recv_loop:
    mov edi, r12d
    lea rsi, [r13 + rbx]
    mov edx, 1
    xor ecx, ecx
    call recv
    test rax, rax
    jz .recv_eof
    js .recv_error
    mov al, [r13 + rbx]
    cmp al, 10
    je .line_end
    lea rdx, [r14 - 1]
    cmp rbx, rdx
    jae .recv_error
    inc rbx
    jmp .recv_loop
.line_end:
    test rbx, rbx
    jz .terminate
    cmp byte [r13 + rbx - 1], 13
    jne .terminate
    dec rbx
.terminate:
    mov byte [r13 + rbx], 0
    mov rax, rbx
    jmp .recv_return
.recv_eof:
    test rbx, rbx
    jnz .recv_error
    xor eax, eax
    jmp .recv_return
.recv_error:
    mov eax, -1
.recv_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
