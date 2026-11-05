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
    ; Empty frames are not valid IRC messages; reserve zero for clean EOF.
    test rbx, rbx
    jz .recv_error
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

; int irc_send_registration(int fd, const char *nick, const char *user,
;                           const char *realname)
; Sends the initial NICK and USER commands. Identity strings are trusted
; configuration values and must not contain CR or LF.
global irc_send_registration
extern snprintf
extern irc_tcp_send_all

section .rodata
registration_format: db "NICK %s", 13, 10, "USER %s 0 * :%s", 13, 10, 0
ping_command: db "PING", 0
pong_prefix: db "PONG :", 0

section .text
irc_send_registration:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 1040

    mov r12d, edi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx

    mov rdi, rsp
    mov esi, 1024
    lea rdx, [rel registration_format]
    mov rcx, r13
    mov r8, r14
    mov r9, r15
    xor eax, eax
    call snprintf
    test eax, eax
    js .registration_error
    cmp eax, 1024
    jae .registration_error
    mov ebx, eax
    mov edi, r12d
    mov rsi, rsp
    mov rdx, rbx
    call irc_tcp_send_all
    jmp .registration_return
.registration_error:
    mov eax, -1
.registration_return:
    add rsp, 1040
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int irc_session_next(int fd, char *line, size_t capacity,
;                      struct irc_message *out)
; Blocks until a non-PING IRC message arrives, clean EOF occurs, or an error
; occurs. Automatically answers PING with PONG using the first parameter.
; Returns 1 for an event, 0 for clean EOF, and -1 for malformed input/I/O.
global irc_session_next
extern irc_tcp_recv_line
extern irc_parse_message
extern irc_tcp_send_all
extern str_ascii_casecmp_n
extern mem_copy

irc_session_next:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 552

    mov r12d, edi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx

.next_line:
    mov edi, r12d
    mov rsi, r13
    mov rdx, r14
    call irc_tcp_recv_line
    test rax, rax
    jz .session_eof
    js .session_error
    mov ebx, eax

    mov rdi, r13
    mov rsi, rbx
    mov rdx, r15
    call irc_parse_message
    test eax, eax
    jnz .session_error

    cmp dword [r15 + 20], 4
    jne .return_event
    mov rdi, r13
    mov esi, [r15 + 16]
    add rdi, rsi
    lea rsi, [rel ping_command]
    mov edx, 4
    call str_ascii_casecmp_n
    test eax, eax
    jnz .return_event

    ; PING must carry at least one parameter.
    cmp dword [r15 + 24], 1
    jb .session_error
    mov eax, [r15 + 32]         ; first parameter offset
    mov edx, [r15 + 36]         ; first parameter length
    cmp edx, 504                ; PONG + token + CRLF <= 512 bytes
    ja .session_error
    mov r8d, edx                ; preserve token length

    mov rdi, rsp
    lea rsi, [rel pong_prefix]
    mov edx, 6
    call mem_copy

    mov eax, [r15 + 32]
    lea rdi, [rsp + 6]
    lea rsi, [r13 + rax]
    mov edx, r8d
    call mem_copy

    mov byte [rsp + 6 + r8], 13
    mov byte [rsp + 7 + r8], 10
    lea rdx, [r8 + 8]
    mov edi, r12d
    mov rsi, rsp
    call irc_tcp_send_all
    test eax, eax
    jnz .session_error
    jmp .next_line

.return_event:
    mov eax, 1
    jmp .session_return
.session_eof:
    xor eax, eax
    jmp .session_return
.session_error:
    mov eax, -1
.session_return:
    add rsp, 552
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
