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
