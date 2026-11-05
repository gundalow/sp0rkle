default rel

global db_key_validate_name
global db_key_encode_string
global db_key_encode_u64
global db_key_encode_bool

%define USEP 0x1f

section .text
; int db_key_validate_name(name, name_len)
; Returns 0 for a valid name, -1 if null or containing USEP.
db_key_validate_name:
    test rdi, rdi
    jz .name_bad
    xor eax, eax
.name_scan:
    cmp rax, rsi
    jae .name_ok
    cmp byte [rdi + rax], USEP
    je .name_bad
    inc rax
    jmp .name_scan
.name_ok:
    xor eax, eax
    ret
.name_bad:
    mov eax, -1
    ret

; ssize_t db_key_encode_string(name,nlen,value,vlen,out,capacity)
; Encodes name || USEP || value. Returns encoded length or -1.
db_key_encode_string:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rax
    sub rsp, 8
    mov [rsp], r9
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    ; Validate all pointers and capacity before writing.
    test r12, r12
    jz .str_error
    test r14, r14
    jz .str_error
    test rbx, rbx
    jz .str_error
    mov rax, r13
    add rax, r15
    jc .str_error
    add rax, 1
    jc .str_error
    cmp rax, [rsp]
    ja .str_error
    mov rdi, r12
    mov rsi, r13
    call db_key_validate_name
    test eax, eax
    jnz .str_error
    xor ecx, ecx
.str_name:
    cmp rcx, r13
    jae .str_sep
    mov al, [r12 + rcx]
    mov [rbx + rcx], al
    inc rcx
    jmp .str_name
.str_sep:
    mov byte [rbx + rcx], USEP
    inc rcx
    xor edx, edx
.str_value:
    cmp rdx, r15
    jae .str_done
    mov al, [r14 + rdx]
    mov [rbx + rcx], al
    inc rcx
    inc rdx
    jmp .str_value
.str_done:
    mov rax, rcx
    jmp .str_return
.str_error:
    mov rax, -1
.str_return:
    add rsp, 8
    pop rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ssize_t db_key_encode_u64(name,nlen,value,out,capacity)
; Encodes name || USEP || uint64 big-endian.
db_key_encode_u64:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rbx, rcx
    mov r15, r8
    test r12, r12
    jz .u64_error
    test rbx, rbx
    jz .u64_error
    lea rax, [r13 + 9]
    cmp rax, r15
    ja .u64_error
    mov rdi, r12
    mov rsi, r13
    call db_key_validate_name
    test eax, eax
    jnz .u64_error
    xor ecx, ecx
.u64_name:
    cmp rcx, r13
    jae .u64_sep
    mov al, [r12 + rcx]
    mov [rbx + rcx], al
    inc rcx
    jmp .u64_name
.u64_sep:
    mov byte [rbx + rcx], USEP
    lea r10, [r13 + 1]
    xor r9d, r9d
.u64_store_loop:
    cmp r9d, 8
    jae .u64_done
    mov eax, 7
    sub eax, r9d
    shl eax, 3
    mov ecx, eax
    mov rax, r14
    shr rax, cl
    mov [rbx + r10 + r9], al
    inc r9d
    jmp .u64_store_loop
.u64_done:
    lea rax, [r13 + 9]
    jmp .u64_return
.u64_error:
    mov rax, -1
.u64_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ssize_t db_key_encode_bool(name,nlen,value,out,capacity)
; Encodes name || USEP || (0xff if true, else 0x00).
db_key_encode_bool:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov rbx, rcx
    mov r15, r8
    test r12, r12
    jz .bool_error
    test rbx, rbx
    jz .bool_error
    lea rax, [r13 + 2]
    cmp rax, r15
    ja .bool_error
    mov rdi, r12
    mov rsi, r13
    call db_key_validate_name
    test eax, eax
    jnz .bool_error
    xor ecx, ecx
.bool_name:
    cmp rcx, r13
    jae .bool_sep
    mov al, [r12 + rcx]
    mov [rbx + rcx], al
    inc rcx
    jmp .bool_name
.bool_sep:
    mov byte [rbx + rcx], USEP
    inc rcx
    test r14d, r14d
    setne al
    neg al
    mov [rbx + rcx], al
    lea rax, [r13 + 2]
    jmp .bool_return
.bool_error:
    mov rax, -1
.bool_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
