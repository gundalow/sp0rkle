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
; Decodes the exact field order emitted by karma_bson_encode and the Go struct.
%macro EXPECT_FIELD 2
    cmp rbx, r11
    jae .decode_error
    movzx r8d, byte [rbx]
    inc rbx
    cmp r8b, %2
    jne .decode_error
    lea rsi, [rel %%name]
    xor ecx, ecx
%%compare:
    lea rdx, [rbx + rcx]
    cmp rdx, r11
    jae .decode_error
    mov al, [rbx + rcx]
    cmp al, [rsi + rcx]
    jne .decode_error
    test al, al
    jz %%matched
    inc ecx
    jmp %%compare
%%matched:
    add rbx, rcx
    inc rbx
    jmp %%skip
%%name: db %1, 0
%%skip:
%endmacro

%macro EXPECT_INT_FIELD 1
    cmp rbx, r11
    jae .decode_error
    movzx r8d, byte [rbx]
    inc rbx
    cmp r8b, 0x10
    je %%type_ok
    cmp r8b, 0x12
    jne .decode_error
%%type_ok:
    lea rsi, [rel %%name]
    xor ecx, ecx
%%compare:
    lea rdx, [rbx + rcx]
    cmp rdx, r11
    jae .decode_error
    mov al, [rbx + rcx]
    cmp al, [rsi + rcx]
    jne .decode_error
    test al, al
    jz %%matched
    inc ecx
    jmp %%compare
%%matched:
    add rbx, rcx
    inc rbx
    jmp %%skip
%%name: db %1, 0
%%skip:
%endmacro

%macro COPY_STRING 3
    ; %1 = record pointer offset, %2 = record length offset,
    ; %3 = request buffer pointer offset; capacity is %3 + 8.
    cmp rbx, r11
    jae .decode_error
    mov eax, [rbx]
    cmp eax, 1
    jb .decode_error
    mov r10d, eax
    dec r10
    lea rdx, [rbx + 4]
    mov rax, rdx
    add rax, r10
    inc rax
    cmp rax, r11
    ja .decode_error
    cmp byte [rax - 1], 0
    jne .decode_error
    mov r9, [r12 + %3]
    test r9, r9
    jz .decode_error
    mov rax, [r12 + %3 + 8]
    mov rcx, r10
    inc rcx
    cmp rax, rcx
    jb .decode_error
    mov rdi, r9
    mov rsi, rdx
    mov rcx, r10
    rep movsb
    mov byte [rdi], 0
    mov [r15 + %1], r9
    mov [r15 + %2], r10
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
    cmp r14, 0x7fffffff
    ja .decode_error
    mov eax, [r13]
    cmp rax, r14
    jne .decode_error
    cmp byte [r13 + r14 - 1], 0
    jne .decode_error
    lea rbx, [r13 + 4]
    lea r11, [r13 + r14 - 1]

    EXPECT_FIELD "subject", 0x02
    COPY_STRING 0, 8, 24

    EXPECT_FIELD "key", 0x02
    COPY_STRING 16, 0, 40

    EXPECT_INT_FIELD "score"
    cmp r8b, 0x10
    je .decode_score_i32
    lea rax, [rbx + 8]
    cmp rax, r11
    ja .decode_error
    mov rax, [rbx]
    add rbx, 8
    jmp .decode_score_store
.decode_score_i32:
    lea rax, [rbx + 4]
    cmp rax, r11
    ja .decode_error
    movsxd rax, dword [rbx]
    add rbx, 4
.decode_score_store:
    mov [r15 + 24], rax

    EXPECT_INT_FIELD "votes"
    cmp r8b, 0x10
    je .decode_votes_i32
    lea rdx, [rbx + 8]
    cmp rdx, r11
    ja .decode_error
    mov rax, [rbx]
    add rbx, 8
    jmp .decode_votes_store
.decode_votes_i32:
    lea rdx, [rbx + 4]
    cmp rdx, r11
    ja .decode_error
    movsxd rax, dword [rbx]
    add rbx, 4
.decode_votes_store:
    test rax, rax
    js .decode_error
    mov [r15 + 32], rax

    EXPECT_FIELD "upvoter", 0x02
    COPY_STRING 40, 48, 56

    EXPECT_FIELD "upvtime", 0x09
    lea rax, [rbx + 8]
    cmp rax, r11
    ja .decode_error
    mov rax, [rbx]
    add rbx, 8
    mov rdx, -62135596800000
    cmp rax, rdx
    jne .decode_up_time_store
    xor eax, eax
.decode_up_time_store:
    mov [r15 + 56], rax

    EXPECT_FIELD "downvoter", 0x02
    COPY_STRING 64, 72, 72

    EXPECT_FIELD "downvtime", 0x09
    lea rax, [rbx + 8]
    cmp rax, r11
    ja .decode_error
    mov rax, [rbx]
    add rbx, 8
    mov rdx, -62135596800000
    cmp rax, rdx
    jne .decode_down_time_store
    xor eax, eax
.decode_down_time_store:
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
