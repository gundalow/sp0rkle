; Bounds-checked structural validator for BSON documents.
default rel
global bson_document_validate

section .text
; int bson_document_validate(document, document_len)
; Returns 0 for a structurally valid BSON document, -1 otherwise.
; Recursion is bounded to 32 nested document/array/code-scope levels.
bson_document_validate:
    xor edx, edx
    jmp bson_validate_inner

bson_validate_inner:
    push rbp
    mov rbp, rdx                ; nesting depth
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .invalid
    cmp r13, 5
    jb .invalid
    cmp rbp, 32
    jae .invalid
    mov eax, [r12]
    cmp rax, r13
    jne .invalid
    cmp byte [r12 + r13 - 1], 0
    jne .invalid
    lea r14, [r12 + 4]
    lea r15, [r12 + r13 - 1]

.element_loop:
    cmp r14, r15
    jae .valid
    movzx ebx, byte [r14]
    inc r14

    ; Every element has a NUL-terminated cstring field name.
.name_scan:
    cmp r14, r15
    jae .invalid
    cmp byte [r14], 0
    je .name_done
    inc r14
    jmp .name_scan
.name_done:
    inc r14
    cmp r14, r15
    ja .invalid

    cmp ebx, 0x01
    je .fixed8
    cmp ebx, 0x02
    je .string
    cmp ebx, 0x03
    je .nested
    cmp ebx, 0x04
    je .nested
    cmp ebx, 0x05
    je .binary
    cmp ebx, 0x06
    je .element_loop
    cmp ebx, 0x07
    je .fixed12
    cmp ebx, 0x08
    je .boolean
    cmp ebx, 0x09
    je .fixed8
    cmp ebx, 0x0a
    je .element_loop
    cmp ebx, 0x0b
    je .regex
    cmp ebx, 0x0c
    je .dbpointer
    cmp ebx, 0x0d
    je .string
    cmp ebx, 0x0e
    je .string
    cmp ebx, 0x0f
    je .code_scope
    cmp ebx, 0x10
    je .fixed4
    cmp ebx, 0x11
    je .fixed8
    cmp ebx, 0x12
    je .fixed8
    cmp ebx, 0x13
    je .fixed16
    cmp ebx, 0x7f
    je .element_loop
    cmp ebx, 0xff
    je .element_loop
    jmp .invalid

.fixed4:
    lea rax, [r14 + 4]
    cmp rax, r15
    ja .invalid
    mov r14, rax
    jmp .element_loop
.fixed8:
    lea rax, [r14 + 8]
    cmp rax, r15
    ja .invalid
    mov r14, rax
    jmp .element_loop
.fixed12:
    lea rax, [r14 + 12]
    cmp rax, r15
    ja .invalid
    mov r14, rax
    jmp .element_loop
.fixed16:
    lea rax, [r14 + 16]
    cmp rax, r15
    ja .invalid
    mov r14, rax
    jmp .element_loop

.boolean:
    cmp r14, r15
    jae .invalid
    cmp byte [r14], 1
    ja .invalid
    inc r14
    jmp .element_loop

.string:
    mov eax, [r14]
    test eax, eax
    js .invalid
    cmp eax, 1
    jb .invalid
    lea rax, [r14 + 4]
    add rax, rax                 ; discard: overflow check below uses length
    mov eax, [r14]
    lea rdx, [r14 + 4]
    add rdx, rax
    jc .invalid
    cmp rdx, r15
    ja .invalid
    cmp byte [rdx - 1], 0
    jne .invalid
    mov r14, rdx
    jmp .element_loop

.binary:
    mov eax, [r14]
    test eax, eax
    js .invalid
    lea rdx, [r14 + 5]
    add rdx, rax
    jc .invalid
    cmp rdx, r15
    ja .invalid
    mov r14, rdx
    jmp .element_loop

.nested:
    mov eax, [r14]
    cmp eax, 5
    jb .invalid
    lea rdx, [r14 + rax]
    jc .invalid
    cmp rdx, r15
    ja .invalid
    mov rdi, r14
    mov esi, eax
    lea rdx, [rbp + 1]
    call bson_validate_inner
    test eax, eax
    jnz .invalid
    mov eax, [r14]
    add r14, rax
    jmp .element_loop

.regex:
    ; BSON regex is two consecutive cstrings: pattern and options.
.regex_first:
    cmp r14, r15
    jae .invalid
    cmp byte [r14], 0
    je .regex_first_done
    inc r14
    jmp .regex_first
.regex_first_done:
    inc r14
.regex_second:
    cmp r14, r15
    jae .invalid
    cmp byte [r14], 0
    je .regex_second_done
    inc r14
    jmp .regex_second
.regex_second_done:
    inc r14
    jmp .element_loop

.dbpointer:
    mov eax, [r14]
    test eax, eax
    js .invalid
    cmp eax, 1
    jb .invalid
    lea rdx, [r14 + 4]
    add rdx, rax
    jc .invalid
    add rdx, 12
    jc .invalid
    cmp rdx, r15
    ja .invalid
    cmp byte [rdx - 13], 0
    jne .invalid
    mov r14, rdx
    jmp .element_loop

.code_scope:
    mov eax, [r14]
    cmp eax, 14
    jb .invalid
    lea rdx, [r14 + rax]
    jc .invalid
    cmp rdx, r15
    ja .invalid
    mov [rsp], rdx              ; end of code-with-scope value
    mov ecx, [r14 + 4]          ; code string length
    cmp ecx, 1
    jb .invalid
    lea r8, [r14 + 8]
    add r8, rcx
    jc .invalid
    cmp r8, [rsp]
    ja .invalid
    cmp byte [r8 - 1], 0
    jne .invalid
    mov rdi, r8                 ; embedded scope document
    mov esi, [r8]
    lea rdx, [rbp + 1]
    call bson_validate_inner
    test eax, eax
    jnz .invalid
    mov r14, [rsp]
    jmp .element_loop

.valid:
    xor eax, eax
    jmp .return
.invalid:
    mov eax, -1
.return:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
