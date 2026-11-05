; BSON-compatible encoder for the reference karma record.
; Record layout is the 88-byte karma_record ABI.
default rel
section .text
global karma_bson_encode

%macro WRITE_STRING 3
    mov byte [rdi], 0x02
    inc rdi
    lea rsi, [rel %%name]
    mov ecx, %%namelen
    rep movsb
    mov byte [rdi], 0
    inc rdi
    mov eax, [r14 + %3]
    inc eax
    mov [rdi], eax
    add rdi, 4
    mov rsi, [r14 + %2]
    mov rcx, [r14 + %3]
    rep movsb
    mov byte [rdi], 0
    inc rdi
    jmp %%done
%%name: db %1
%%namelen equ $ - %%name
%%done:
%endmacro

%macro WRITE_INT 2
    mov rax, [r14 + %2]
    cmp rax, 0x7fffffff
    jg %%wide
    cmp rax, -0x80000000
    jl %%wide
    mov byte [rdi], 0x10
    inc rdi
    lea rsi, [rel %%name]
    mov ecx, %%namelen
    rep movsb
    mov byte [rdi], 0
    inc rdi
    mov eax, [r14 + %2]
    mov [rdi], eax
    add rdi, 4
    jmp %%done
%%wide:
    mov byte [rdi], 0x12
    inc rdi
    lea rsi, [rel %%name]
    mov ecx, %%namelen
    rep movsb
    mov byte [rdi], 0
    inc rdi
    mov rax, [r14 + %2]
    mov [rdi], rax
    add rdi, 8
    jmp %%done
%%done:
%%name: db %1
%%namelen equ $ - %%name
%endmacro

%macro WRITE_DATE 2
    mov byte [rdi], 0x09
    inc rdi
    lea rsi, [rel %%name]
    mov ecx, %%namelen
    rep movsb
    mov byte [rdi], 0
    inc rdi
    mov rax, [r14 + %2]
    test rax, rax
    jnz %%time_ready
    mov rax, -62135596800000
%%time_ready:
    mov [rdi], rax
    add rdi, 8
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
    ; String lengths are uint32 in BSON; reject unrepresentable fields.
    mov rax, [r14 + 8]
    mov edx, -1
    cmp rax, rdx
    ja .encode_error
    ; subject and key use the same byte length.
    add rax, 14
    add r13, rax
    add rax, 0
    sub rax, 14
    add rax, 10
    add r13, rax
    mov rax, [r14 + 48]
    mov edx, -1
    cmp rax, rdx
    ja .encode_error
    add rax, 14
    add r13, rax
    mov rax, [r14 + 72]
    mov edx, -1
    cmp rax, rdx
    ja .encode_error
    add rax, 16
    add r13, rax
    ; int32/int64 encoded size depends on the Go int range.
    mov rax, [r14 + 24]
    cmp rax, 0x7fffffff
    jg .score_wide
    cmp rax, -0x80000000
    jl .score_wide
    add r13, 11
    jmp .score_done
.score_wide:
    add r13, 15
.score_done:
    mov rax, [r14 + 32]
    test rax, rax
    js .encode_error
    cmp rax, 0x7fffffff
    ja .votes_wide
    add r13, 11
    jmp .votes_done
.votes_wide:
    add r13, 15
.votes_done:
    ; date elements are 17 and 19 bytes.
    add r13, 36
    cmp r13, r12
    ja .encode_error
    cmp r13, 0x7fffffff
    ja .encode_error

    mov dword [rbx], 0
    lea rdi, [rbx + 4]
    WRITE_STRING "subject", 0, 8
    WRITE_STRING "key", 16, 8
    WRITE_INT "score", 24
    WRITE_INT "votes", 32
    WRITE_STRING "upvoter", 40, 48
    WRITE_DATE "upvtime", 56
    WRITE_STRING "downvoter", 64, 72
    WRITE_DATE "downvtime", 80
    mov byte [rdi], 0
    inc rdi
    mov r13, rdi
    sub r13, rbx
    mov [rbx], r13d
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
