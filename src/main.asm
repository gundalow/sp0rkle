default rel

global main
extern puts
extern strcmp
extern getopt
extern optarg
extern irc_console_run
extern str_len
extern strn_len
extern str_ascii_casecmp_n
extern mem_copy
extern mem_equal
extern str_ascii_casecmp
extern irc_line_length
extern irc_parse_message

section .rodata
version_text: db "sp0rkle-asm 0.1.0-dev (x86-64 Linux, NASM)", 0
usage_text: db "Usage: sp0rkle -s SERVER [-p PORT] -c CHANNEL [-n NICK] [--version|--self-test]", 0
default_port: db "6667", 0
default_nick: db "sp0rklf", 0
getopt_options: db "s:p:n:c:h", 0
selftest_ok: db "self-test: PASS", 0
selftest_fail: db "self-test: FAIL", 0
arg_version: db "--version", 0
arg_selftest: db "--self-test", 0
arg_help: db "-h", 0
test_irc_line: db "PING :server", 13, 10, 0
test_upper: db "PRIVMSG", 0
test_lower: db "privmsg", 0
test_irc_message: db "@aaa=bbb :nick!u@h PRIVMSG #chan :hello there"
test_irc_message_len: equ $ - test_irc_message
test_numeric_message: db ":server 001 nick :Welcome"
test_numeric_message_len: equ $ - test_numeric_message
test_bad_irc_message: db "PING", 13
test_bad_irc_message_len: equ $ - test_bad_irc_message

section .text
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov ebx, edi
    mov r12, rsi
    xor r13d, r13d             ; server
    lea r14, [rel default_port]
    lea r15, [rel default_nick]
    mov qword [rsp], 0         ; channel

    cmp ebx, 1
    jle .parse_options
    mov rdi, [r12 + 8]
    lea rsi, [rel arg_version]
    call strcmp
    test eax, eax
    jz .version
    mov rdi, [r12 + 8]
    lea rsi, [rel arg_selftest]
    call strcmp
    test eax, eax
    jz .selftest
    mov rdi, [r12 + 8]
    lea rsi, [rel arg_help]
    call strcmp
    test eax, eax
    jz .usage_success

.parse_options:
    mov edi, ebx
    mov rsi, r12
    lea rdx, [rel getopt_options]
    call getopt
    cmp eax, -1
    je .options_done
    cmp eax, 's'
    je .set_server
    cmp eax, 'p'
    je .set_port
    cmp eax, 'n'
    je .set_nick
    cmp eax, 'c'
    je .set_channel
    cmp eax, 'h'
    je .usage_success
    jmp .usage_error

.set_server:
    mov r13, [rel optarg]
    jmp .parse_options
.set_port:
    mov r14, [rel optarg]
    jmp .parse_options
.set_nick:
    mov r15, [rel optarg]
    jmp .parse_options
.set_channel:
    mov rax, [rel optarg]
    mov [rsp], rax
    jmp .parse_options

.options_done:
    test r13, r13
    jz .usage_error
    cmp qword [rsp], 0
    je .usage_error
    mov rdi, r13
    mov rsi, r14
    mov rdx, r15
    mov rcx, [rsp]
    call irc_console_run
    jmp .done

.version:
    lea rdi, [rel version_text]
    call puts
    xor eax, eax
    jmp .done
.selftest:
    call run_selftest
    jmp .done
.usage_success:
    lea rdi, [rel usage_text]
    call puts
    xor eax, eax
    jmp .done
.usage_error:
    lea rdi, [rel usage_text]
    call puts
    mov eax, 2
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

run_selftest:
    push rbp
    mov rbp, rsp
    sub rsp, 176
    lea rdi, [rel test_irc_line]
    call irc_line_length
    cmp rax, 12
    jne .failed
    lea rdi, [rel test_upper]
    lea rsi, [rel test_lower]
    call str_ascii_casecmp
    test eax, eax
    jne .failed
    lea rdi, [rel test_upper]
    call str_len
    cmp rax, 7
    jne .failed
    lea rdi, [rel test_upper]
    mov esi, 3
    call strn_len
    cmp rax, 3
    jne .failed
    lea rdi, [rel test_upper]
    lea rsi, [rel test_lower]
    mov edx, 7
    call str_ascii_casecmp_n
    test eax, eax
    jne .failed
    lea rdi, [rel test_upper]
    lea rsi, [rel test_upper]
    mov edx, 8
    call mem_equal
    test eax, eax
    jne .failed
    lea rdi, [rbp - 8]
    lea rsi, [rel test_upper]
    mov edx, 8
    call mem_copy
    lea rdi, [rbp - 8]
    lea rsi, [rel test_upper]
    mov edx, 8
    call mem_equal
    test eax, eax
    jne .failed
    lea rdi, [rel test_irc_message]
    mov esi, test_irc_message_len
    lea rdx, [rbp - 160]
    call irc_parse_message
    test eax, eax
    jne .failed
    cmp dword [rbp - 160 + 20], 7
    jne .failed
    cmp dword [rbp - 160 + 24], 2
    jne .failed
    cmp dword [rbp - 160 + 28], 1
    jne .failed
    cmp dword [rbp - 160 + 32 + 8 + 4], 11
    jne .failed
    lea rdi, [rel test_numeric_message]
    mov esi, test_numeric_message_len
    lea rdx, [rbp - 160]
    call irc_parse_message
    test eax, eax
    jne .failed
    cmp dword [rbp - 160 + 20], 3
    jne .failed
    cmp dword [rbp - 160 + 24], 2
    jne .failed
    lea rdi, [rel test_bad_irc_message]
    mov esi, test_bad_irc_message_len
    lea rdx, [rbp - 160]
    call irc_parse_message
    cmp eax, -1
    jne .failed
    lea rdi, [rel selftest_ok]
    call puts
    xor eax, eax
    jmp .return
.failed:
    lea rdi, [rel selftest_fail]
    call puts
    mov eax, 1
.return:
    add rsp, 176
    pop rbp
    ret
