; BSON-compatible encoder for the reference karma record.
; Record layout is the 88-byte karma_record ABI.
default rel
section .text
global karma_bson_encode

%macro WRITE_STRING 3
    mov byte [rdi], 0x02
    inc r13
    lea rsi, [rel %%name]
    mov ecx, %%namelen
    rep movsb
    mov byte [rdi], 0
    inc r13
    mov eax, [r14 + %3]
    inc eax
    mov [rdi], eax
    add r13, 4
    mov rsi, [r14 + %2]
    mov ecx, [r14 + %3]
    rep movsb
    mov byte [rdi], 0
    inc r13
    jmp %%done
%%name: db %1
%%namelen equ $ - %%name
%%done:
%endmacro

%macro WRITE_INT32 2
    mov byte [rdi], 0x10
    inc r13
    lea rsi, [rel %%name]
    mov ecx, %%namelen
    rep movsb
    mov byte [rdi], 0
    inc r13
    mov eax, [r14 + %2]
    mov [rdi], eax
    add r13, 4
    jmp %%done
%%name: db %1
%%namelen equ $ - %%name
%%done:
%endmacro

%macro WRITE_DATE 2
    mov byte [rdi], 0x09
    inc r13
    lea rsi, [rel %%name]
    mov ecx, %%namelen
    rep movsb
    mov byte [rdi], 0
    inc r13
    mov rax, [r14 + %2]
    test rax, rax
    jnz %%time_ready
    mov rax, -62135596800000
%%time_ready:
    mov [rdi], rax
    add r13, 8
    jmp %%done
%%name: db %1
%%namelen equ $ - %%name
%%done:
%endmacro

; int karma_bson_encode(record, output, capacity, output_len)
; Returns 0 on success, -1 on invalid pointers or insufficient capacity.
; Strings are length-delimited and may contain arbitrary non-NUL bytes.
karma_bson_encode:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rdi
    mov rbx, rsi
    mov r12, rdx
    mov r15, rcx
    test r14, r14
    jz .encode_error
    test rbx, rbx
    jz .encode_error
    test r15, r15
    jz .encode_error

    ; Compute required length before touching output.
    mov r13d, 5
    ; subject: 1 + 8 + 4 + len + 1
    mov eax, [r14 + 8]
    add rax, 14
    add r13, rax
    ; key: 1 + 4 + 4 + len + 1
    mov eax, [r14 + 16]
    add rax, 10
    add r13, rax
    ; score + votes: 2 * (1 + 6 + 4)
    add r13, 22
    ; upvoter: 1 + 8 + 4 + len + 1
    mov eax, [r14 + 48]
    add rax, 14
    add r13, rax
    ; upvtime: 1 + 8 + 8
    add r13, 17
    ; downvoter: 1 + 10 + 4 + len + 1
    mov eax, [r14 + 72]
    add rax, 16
    add r13, rax
    ; downvtime: 1 + 10 + 8
    add r13, 19
    cmp r13, r12
    ja .encode_error
    cmp r13, 0x7fffffff
    ja .encode_error

    mov dword [rbx], 0
    mov r13d, 4
    lea rdi, [rdi]
    WRITE_STRING "subject", 0, 8
    WRITE_STRING "key", 16, 24
    WRITE_INT32 "score", 24
    WRITE_INT32 "votes", 32
    WRITE_STRING "upvoter", 40, 48
    WRITE_DATE "upvtime", 56
    WRITE_STRING "downvoter", 64, 72
    WRITE_DATE "downvtime", 80
    mov byte [rdi], 0
    inc r13
    mov eax, r13d
    mov [rbx], eax
    mov [r15], r13
    xor eax, eax
    jmp .encode_done
.encode_error:
    mov eax, -1
.encode_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
