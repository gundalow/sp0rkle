default rel
global bson_find_field
extern bson_document_validate

section .text
; Find output descriptor: type u32 at +0, value pointer +8, value length +16.
; int bson_find_field(doc,len,name,name_len,out)
bson_find_field:
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
    mov r15, rcx
    mov rbx, r8
    test r14, r14
    jz .find_error
    test rbx, rbx
    jz .find_error
    mov dword [rbx], 0
    mov qword [rbx + 8], 0
    mov qword [rbx + 16], 0
    mov rdi, r12
    mov rsi, r13
    call bson_document_validate
    test eax, eax
    jnz .find_error
    lea r10, [r12 + 4]
    lea r11, [r12 + r13 - 1]
.find_loop:
    cmp r10, r11
    jae .find_missing
    movzx r8d, byte [r10]
    inc r10
    mov r9, r10
    xor ecx, ecx
.find_name_scan:
    cmp byte [r10], 0
    je .find_name_done
    inc r10
    inc rcx
    jmp .find_name_scan
.find_name_done:
    inc r10
    cmp rcx, r15
    jne .find_skip
    xor edx, edx
.find_name_compare:
    cmp rdx, r15
    jae .find_match
    mov al, [r9 + rdx]
    cmp al, [r14 + rdx]
    jne .find_skip
    inc rdx
    jmp .find_name_compare
.find_match:
    mov edi, r8d
    mov rsi, r10
    call bson_value_size
    test rax, rax
    js .find_error
    mov [rbx], r8d
    mov [rbx + 8], r10
    mov [rbx + 16], rax
    mov eax, 1
    jmp .find_done
.find_skip:
    mov edi, r8d
    mov rsi, r10
    call bson_value_size
    test rax, rax
    js .find_error
    add r10, rax
    jmp .find_loop
.find_missing:
    xor eax, eax
    jmp .find_done
.find_error:
    mov eax, -1
.find_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; Internal helper returns raw value byte length in RAX and leaves R10/R11 intact.
bson_value_size:
    cmp edi, 0x01
    je .size8
    cmp edi, 0x09
    je .size8
    cmp edi, 0x11
    je .size8
    cmp edi, 0x12
    je .size8
    cmp edi, 0x10
    je .size4
    cmp edi, 0x07
    je .size12
    cmp edi, 0x13
    je .size16
    cmp edi, 0x08
    je .size1
    cmp edi, 0x06
    je .size0
    cmp edi, 0x0a
    je .size0
    cmp edi, 0x7f
    je .size0
    cmp edi, 0xff
    je .size0
    cmp edi, 0x02
    je .sizestring
    cmp edi, 0x0d
    je .sizestring
    cmp edi, 0x0e
    je .sizestring
    cmp edi, 0x03
    je .sizenested
    cmp edi, 0x04
    je .sizenested
    cmp edi, 0x0f
    je .sizenested
    cmp edi, 0x05
    je .sizebinary
    cmp edi, 0x0c
    je .sizedbpointer
    cmp edi, 0x0b
    je .sizeregex
    mov rax, -1
    ret
.size0:
    xor eax, eax
    ret
.size1:
    mov eax, 1
    ret
.size4:
    mov eax, 4
    ret
.size8:
    mov eax, 8
    ret
.size12:
    mov eax, 12
    ret
.size16:
    mov eax, 16
    ret
.sizestring:
    mov eax, [rsi]
    add rax, 4
    ret
.sizenested:
    mov eax, [rsi]
    ret
.sizebinary:
    mov eax, [rsi]
    add rax, 5
    ret
.sizedbpointer:
    mov eax, [rsi]
    add rax, 16
    ret
.sizeregex:
    mov rdx, rsi
.regex_first:
    cmp byte [rdx], 0
    je .regex_first_done
    inc rdx
    jmp .regex_first
.regex_first_done:
    inc rdx
.regex_second:
    cmp byte [rdx], 0
    je .regex_second_done
    inc rdx
    jmp .regex_second
.regex_second_done:
    inc rdx
    mov rax, rdx
    sub rax, rsi
    ret

; int bson_decode_scalar(type, raw_value, raw_len, out, capacity, out_len)
; Converts one validated BSON raw value into caller-owned host data.
; Strings are NUL-terminated; int32 is widened to int64; binary strips its
; length/subtype header; nested documents are copied whole.
global bson_decode_scalar
bson_decode_scalar:
    cld
    push rbp
    mov rbp, r9
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    test rbp, rbp
    jz .scalar_error
    test r13, r13
    jz .scalar_error

    cmp r12, 0x02
    je .scalar_string
    cmp r12, 0x0d
    je .scalar_string
    cmp r12, 0x0e
    je .scalar_string
    cmp r12, 0x10
    je .scalar_int32
    cmp r12, 0x01
    je .scalar_fixed8
    cmp r12, 0x09
    je .scalar_fixed8
    cmp r12, 0x11
    je .scalar_fixed8
    cmp r12, 0x12
    je .scalar_fixed8
    cmp r12, 0x08
    je .scalar_bool
    cmp r12, 0x07
    je .scalar_fixed12
    cmp r12, 0x13
    je .scalar_fixed16
    cmp r12, 0x05
    je .scalar_binary
    cmp r12, 0x03
    je .scalar_document
    cmp r12, 0x04
    je .scalar_document
    cmp r12, 0x0f
    je .scalar_document
    cmp r12, 0x06
    je .scalar_empty
    cmp r12, 0x0a
    je .scalar_empty
    cmp r12, 0x7f
    je .scalar_empty
    cmp r12, 0xff
    je .scalar_empty
    ; Other supported variable-length values are returned as raw bytes.
    cmp r12, 0x0b
    je .scalar_raw
    cmp r12, 0x0c
    je .scalar_raw
    jmp .scalar_error

.scalar_string:
    cmp r14, 5
    jb .scalar_error
    mov eax, [r13]
    test eax, eax
    js .scalar_error
    cmp eax, 1
    jb .scalar_error
    lea rdx, [rax + 4]
    cmp rdx, r14
    jne .scalar_error
    mov r10d, eax
    dec r10
    lea rdx, [r13 + 4]
    add rdx, r10
    cmp byte [rdx], 0
    jne .scalar_error
    mov rax, r10
    inc rax
    cmp rbx, rax
    jb .scalar_error
    test r15, r15
    jz .scalar_error
    mov rdi, r15
    lea rsi, [r13 + 4]
    mov rcx, r10
    rep movsb
    mov byte [rdi], 0
    mov [rbp], r10
    xor eax, eax
    jmp .scalar_done

.scalar_int32:
    cmp r14, 4
    jne .scalar_error
    cmp rbx, 8
    jb .scalar_error
    test r15, r15
    jz .scalar_error
    movsxd rax, dword [r13]
    mov [r15], rax
    mov qword [rbp], 8
    xor eax, eax
    jmp .scalar_done

.scalar_fixed8:
    cmp r14, 8
    jne .scalar_error
    cmp rbx, 8
    jb .scalar_error
    test r15, r15
    jz .scalar_error
    mov rax, [r13]
    mov [r15], rax
    mov qword [rbp], 8
    xor eax, eax
    jmp .scalar_done

.scalar_bool:
    cmp r14, 1
    jne .scalar_error
    cmp byte [r13], 1
    ja .scalar_error
    cmp rbx, 1
    jb .scalar_error
    test r15, r15
    jz .scalar_error
    mov al, [r13]
    mov [r15], al
    mov qword [rbp], 1
    xor eax, eax
    jmp .scalar_done

.scalar_fixed12:
    cmp r14, 12
    jne .scalar_error
    cmp rbx, 12
    jb .scalar_error
    test r15, r15
    jz .scalar_error
    mov rsi, r13
    mov rdi, r15
    mov ecx, 12
    rep movsb
    mov qword [rbp], 12
    xor eax, eax
    jmp .scalar_done

.scalar_fixed16:
    cmp r14, 16
    jne .scalar_error
    cmp rbx, 16
    jb .scalar_error
    test r15, r15
    jz .scalar_error
    mov rsi, r13
    mov rdi, r15
    mov ecx, 16
    rep movsb
    mov qword [rbp], 16
    xor eax, eax
    jmp .scalar_done

.scalar_binary:
    cmp r14, 5
    jb .scalar_error
    mov eax, [r13]
    test eax, eax
    js .scalar_error
    lea rdx, [rax + 5]
    cmp rdx, r14
    jne .scalar_error
    cmp rbx, rax
    jb .scalar_error
    test rax, rax
    jz .scalar_binary_done
    test r15, r15
    jz .scalar_error
    mov rsi, r13
    add rsi, 5
    mov rdi, r15
    mov rcx, rax
    rep movsb
.scalar_binary_done:
    mov eax, [r13]
    mov [rbp], rax
    xor eax, eax
    jmp .scalar_done

.scalar_document:
    cmp r14, 5
    jb .scalar_error
    mov eax, [r13]
    cmp rax, r14
    jne .scalar_error
    mov rdi, r13
    mov rsi, r14
    call bson_document_validate
    test eax, eax
    jnz .scalar_error
    cmp rbx, r14
    jb .scalar_error
    test r15, r15
    jz .scalar_error
    mov rsi, r13
    mov rdi, r15
    mov rcx, r14
    rep movsb
    mov [rbp], r14
    xor eax, eax
    jmp .scalar_done

.scalar_raw:
    cmp rbx, r14
    jb .scalar_error
    test r14, r14
    jz .scalar_empty
    test r15, r15
    jz .scalar_error
    mov rsi, r13
    mov rdi, r15
    mov rcx, r14
    rep movsb
    mov [rbp], r14
    xor eax, eax
    jmp .scalar_done

.scalar_empty:
    test r14, r14
    jnz .scalar_error
    mov qword [rbp], 0
    xor eax, eax
    jmp .scalar_done

.scalar_error:
    mov eax, -1
.scalar_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
