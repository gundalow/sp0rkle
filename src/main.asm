default rel

global main
extern puts
extern strcmp
extern str_len
extern strn_len
extern str_ascii_casecmp_n
extern mem_copy
extern mem_equal
extern str_ascii_casecmp
extern irc_line_length

section .text
version_text: db "sp0rkle-asm 0.1.0-dev (x86-64 Linux, NASM)", 0
usage_text: db "Usage: sp0rkle [--version|--self-test]", 0
startup_text: db "sp0rkle assembly port scaffold: IRC and feature runtime not yet implemented.", 0
selftest_ok: db "self-test: PASS", 0
selftest_fail: db "self-test: FAIL", 0
arg_version: db "--version", 0
arg_selftest: db "--self-test", 0
test_irc_line: db "PING :server", 13, 10, 0
test_upper: db "PRIVMSG", 0
test_lower: db "privmsg", 0

main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rsi
    cmp rdi, 1
    jle .default
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
    lea rdi, [rel usage_text]
    call puts
    mov eax, 2
    jmp .done
.version:
    lea rdi, [rel version_text]
    call puts
    xor eax, eax
    jmp .done
.selftest:
    call run_selftest
    jmp .done
.default:
    lea rdi, [rel startup_text]
    call puts
    xor eax, eax
.done:
    pop r12
    pop rbx
    pop rbp
    ret

run_selftest:
    push rbp
    mov rbp, rsp
    sub rsp, 16
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
    lea rdi, [rel selftest_ok]
    call puts
    xor eax, eax
    jmp .return
.failed:
    lea rdi, [rel selftest_fail]
    call puts
    mov eax, 1
.return:
    add rsp, 16
    pop rbp
    ret
