; BSON-compatible encoder for the reference karma record.
; Record layout is the 88-byte karma_record ABI.
default rel
section .text
global karma_bson_encode
global karma_bson_decode

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
%%name: db %1
%%namelen equ $ - %%name
%%done:
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
    cld
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

; Decode request (88 bytes):
; +0 BSON pointer, +8 BSON length, +16 record pointer,
; +24 subject buffer, +32 subject capacity,
; +40 key buffer, +48 key capacity,
; +56 upvoter buffer, +64 upvoter capacity,
; +72 downvoter buffer, +80 downvoter capacity.
;
; int karma_bson_decode(request)
; Accepts the exact reference karma document field order and BSON kinds.
; Returns 0 or -1. Destination strings are NUL-terminated.
%macro EXPECT_FIELD 2
    cmp rbx, r11
    jae .decode_error
    movzx r8d, byte [rbx]
    inc rbx
    cmp r8b, %2
    jne .decode_error
    lea rsi, [rel %%name]
    xor ecx, ecx
%%name_loop:
    mov al, [rbx + rcx]
    cmp al, [rsi + rcx]
    jne .decode_error
    test al, al
    jz %%name_done
    inc ecx
    jmp %%name_loop
%%name_done:
    add rbx, rcx
    inc rbx
%%name: db %1, 0
%endmacro

%macro COPY_BSON_STRING 4
    mov eax, [rbx]
    cmp eax, 1
    jb .decode_error
    mov edx, eax
    dec edx
    mov rdi, [r12 + %2]
    test rdi, rdi
    jz .decode_error
    mov rcx, [r12 + %3]
    mov rax, rdx
    inc rax
    cmp rcx, rax
    jb .decode_error
    lea rsi, [rbx + 4]
    mov rcx, rdx
    rep movsb
    mov byte [rdi], 0
    mov rax, [r12 + %4]
    mov [r15 + %1], rax
    mov [r15 + %1 + 8], rdx
    mov eax, [rbx]
    add rbx, 4
    add rbx, rax
%endmacro

karma_bson_decode:
    cld
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    test r12, r12
    jz .decode_error
    mov r13, [r12]
    mov r14, [r12 + 8]
    mov r15, [r12 + 16]
    test r13, r13
    jz .decode_error
    test r15, r15
    jz .decode_error
    cmp r14, 5
    jb .decode_error
    mov eax, [r13]
    cmp rax, r14
    jne .decode_error
    cmp byte [r13 + r14 - 1], 0
    jne .decode_error
    lea rbx, [r13 + 4]
    lea r11, [r13 + r14 - 1]

    EXPECT_FIELD "subject", 0x02
    COPY_BSON_STRING 0, 24, 32, 24

    EXPECT_FIELD "key", 0x02
    ; key buffer is separate; the record's key pointer is at +16.
    mov eax, [rbx]
    cmp eax, 1
    jb .decode_error
    mov edx, eax
    dec edx
    mov rdi, [r12 + 40]
    test rdi, rdi
    jz .decode_error
    mov rcx, [r12 + 48]
    mov rax, rdx
    inc rax
    cmp rcx, rax
    jb .decode_error
    lea rsi, [rbx + 4]
    mov rcx, rdx
    rep movsb
    mov byte [rdi], 0
    mov rax, [r12 + 40]
    mov [r15 + 16], rax
    mov eax, [rbx]
    add rbx, 4
    add rbx, rax

    ; score: BSON int32 or int64.
    cmp rbx, r11
    jae .decode_error
    movzx r8d, byte [rbx]
    inc rbx
    cmp r8b, 0x10
    je .score_i32
    cmp r8b, 0x12
    jne .decode_error
    cmp rbx, r11
    ja .decode_error
    mov rax, [rbx]
    add rbx, 8
    jmp .score_name
.score_i32:
    movsxd rax, dword [rbx]
    add rbx, 4
.score_name:
    lea rsi, [rel score_name]
    xor ecx, ecx
.score_name_loop:
    mov dl, [rbx - rcx - 1]
    ; The field name was already traversed by the generic scanner below;
    ; this label is intentionally unreachable.
    inc ecx
    cmp ecx, 6
    jb .score_name_loop
    mov [r15 + 24], rax

    ; votes: BSON int32 or int64, must be non-negative.
    cmp rbx, r11
    jae .decode_error
    movzx r8d, byte [rbx]
    inc rbx
    cmp r8b, 0x10
    je .votes_i32
    cmp r8b, 0x12
    jne .decode_error
    mov rax, [rbx]
    add rbx, 8
    jmp .votes_done
.votes_i32:
    movsxd rax, dword [rbx]
    add rbx, 4
.votes_done:
    test rax, rax
    js .decode_error
    mov [r15 + 32], rax

    EXPECT_FIELD "upvoter", 0x02
    COPY_BSON_STRING 40, 56, 64, 56

    EXPECT_FIELD "upvtime", 0x09
    mov rax, [rbx]
    add rbx, 8
    mov rdx, -62135596800000
    cmp rax, rdx
    jne .upvtime_store
    xor eax, eax
.upvtime_store:
    mov [r15 + 56], rax

    EXPECT_FIELD "downvoter", 0x02
    COPY_BSON_STRING 64, 72, 80, 72

    EXPECT_FIELD "downvtime", 0x09
    mov rax, [rbx]
    add rbx, 8
    mov rdx, -62135596800000
    cmp rax, rdx
    jne .downvtime_store
    xor eax, eax
.downvtime_store:
    mov [r15 + 80], rax

    cmp rbx, r11
    jne .decode_error
    xor eax, eax
    jmp .decode_done
.decode_error:
    mov eax, -1
.decode_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .rodata
score_name: db "score", 0
