; Bounds-checked structural validator for BSON documents.
default rel
global bson_document_validate
global bson_document_encode

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
    mov rdx, r14
    add rdx, rax
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
    mov rdx, r14
    add rdx, rax
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
    lea r9, [r8 + 5]
    cmp r9, [rsp]
    ja .invalid
    mov eax, [r8]               ; embedded scope document length
    cmp eax, 5
    jb .invalid
    mov r9, r8
    add r9, rax
    jc .invalid
    cmp r9, [rsp]
    jne .invalid
    mov rdi, r8
    mov esi, eax
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

; Field descriptor (40 bytes):
; +0 name pointer, +8 name length, +16 BSON type (uint32), +20 reserved,
; +24 raw BSON value pointer, +32 raw BSON value length.
; int bson_document_encode(fields,count,out,capacity,out_len)
; Writes one BSON document from raw, already BSON-encoded field values.
; Capacity failures are detected before output is modified. Structural value
; validation runs after assembly; invalid raw values leave output unspecified.
bson_document_encode:
    cld
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
    test r12, r12
    jz .encode_doc_error
    test r14, r14
    jz .encode_doc_error
    test rbx, rbx
    jz .encode_doc_error

    ; Preflight every name and total size before writing anything.
    mov r11d, 5
    xor r10d, r10d
.encode_doc_size_loop:
    cmp r10, r13
    jae .encode_doc_size_done
    mov rax, r10
    imul rax, 40
    jo .encode_doc_error
    lea r9, [r12 + rax]
    mov rsi, [r9]
    test rsi, rsi
    jz .encode_doc_error
    mov rcx, [r9 + 8]
    mov r8, [r9 + 32]
    test r8, r8
    jz .encode_doc_value_pointer_ok
    cmp qword [r9 + 24], 0
    je .encode_doc_error
.encode_doc_value_pointer_ok:
    xor eax, eax
.encode_doc_name_check:
    cmp rax, rcx
    jae .encode_doc_name_done
    cmp byte [rsi + rax], 0
    je .encode_doc_error
    inc rax
    jmp .encode_doc_name_check
.encode_doc_name_done:
    add r11, 2
    jc .encode_doc_error
    add r11, rcx
    jc .encode_doc_error
    add r11, r8
    jc .encode_doc_error
    inc r10
    jmp .encode_doc_size_loop
.encode_doc_size_done:
    cmp r11, 0x7fffffff
    ja .encode_doc_error
    cmp r11, r15
    ja .encode_doc_error

    mov rdi, r14
    add rdi, 4
    xor r10d, r10d
.encode_doc_write_loop:
    cmp r10, r13
    jae .encode_doc_finish
    mov rax, r10
    imul rax, 40
    lea r9, [r12 + rax]
    mov eax, [r9 + 16]
    mov [rdi], al
    inc rdi
    mov rsi, [r9]
    mov rcx, [r9 + 8]
    rep movsb
    mov byte [rdi], 0
    inc rdi
    mov rsi, [r9 + 24]
    mov rcx, [r9 + 32]
    rep movsb
    inc r10
    jmp .encode_doc_write_loop
.encode_doc_finish:
    mov byte [rdi], 0
    inc rdi
    mov r15, rdi
    sub r15, r14
    mov [r14], r15d
    mov [rbx], r15
    mov rdi, r14
    mov rsi, r15
    call bson_document_validate
    test eax, eax
    jnz .encode_doc_error
    xor eax, eax
    jmp .encode_doc_done
.encode_doc_error:
    mov eax, -1
.encode_doc_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
