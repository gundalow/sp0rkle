default rel

global db_key_validate_name
global db_key_encode_string
global db_key_encode_u64
global db_key_encode_bool
global db_key_encode_id
global db_key_encode_timestamp_ms
global db_key_path_append

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
    push r10
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
    pop r10
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
    lea rcx, [r10 + r9]
    mov [rbx + rcx], al
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
    push r15
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
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ssize_t db_key_encode_id(value12,out,capacity)
; Encodes the reference ObjectId key element: "_id" || USEP || 12 raw bytes.
db_key_encode_id:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, rsi
    mov r13, rdx
    test r12, r12
    jz .id_error
    test rbx, rbx
    jz .id_error
    cmp r13, 16
    jb .id_error
    mov dword [rbx], 0x1f64695f
    mov rax, [r12]
    mov [rbx + 4], rax
    mov eax, [r12 + 8]
    mov [rbx + 12], eax
    mov eax, 16
    jmp .id_return
.id_error:
    mov rax, -1
.id_return:
    pop r13
    pop r12
    pop rbx
    ret

; ssize_t db_key_encode_timestamp_ms(name,nlen,unix_ms,out,capacity)
; Mirrors TS.Bytes(): truncate-at-source to signed Unix milliseconds, then
; encode the two's-complement bit pattern as an unsigned big-endian uint64.
db_key_encode_timestamp_ms:
    ; The uint64 encoder accepts the same register layout after treating the
    ; signed millisecond value as its raw 64-bit representation.
    jmp db_key_encode_u64

; ssize_t db_key_path_append(path,path_len,element,element_len,out,capacity)
; Appends an unambiguous length-prefixed element to an opaque bucket path:
; path || uint64_be(element_len) || element. Returns new path length or -1.
db_key_path_append:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov r10, r9
    test r12, r12
    jz .path_error
    test r14, r14
    jz .path_error
    test rbx, rbx
    jz .path_error
    mov rax, r13
    add rax, 8
    jc .path_error
    add rax, r15
    jc .path_error
    cmp rax, r10
    ja .path_error
    xor ecx, ecx
.path_copy_parent:
    cmp rcx, r13
    jae .path_length_prefix
    mov al, [r12 + rcx]
    mov [rbx + rcx], al
    inc rcx
    jmp .path_copy_parent
.path_length_prefix:
    mov r11, r13
    mov rax, r15
    xor edx, edx
.path_prefix_loop:
    cmp edx, 8
    jae .path_copy_element
    mov rsi, 7
    sub rsi, rdx
    shl rsi, 3
    mov rdi, rax
    mov rcx, rsi
    shr rdi, cl
    mov [rbx + r11 + rdx], dil
    inc edx
    jmp .path_prefix_loop
.path_copy_element:
    lea rdi, [rbx + r11 + 8]
    xor ecx, ecx
.path_element_loop:
    cmp rcx, r15
    jae .path_done
    mov al, [r14 + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp .path_element_loop
.path_done:
    mov rax, r13
    add rax, 8
    add rax, r15
    jmp .path_return
.path_error:
    mov rax, -1
.path_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
