default rel

extern karma_key_normalize
extern karma_record_apply

global karma_apply_annotations

; struct karma_apply_request (104 bytes):
; +0 text, +8 text_len, +16 annotations, +24 annotation_count
; +32 voter, +40 voter_len, +48 unix_ms
; +56 lookup(ctx,key,key_len,record), +64 put(ctx,record), +72 ctx
; +80 key_scratch, +88 key_capacity, +96 record_scratch
; lookup returns 1 found, 0 absent, negative error; put returns 0 or negative.
; int64 karma_apply_annotations(const request *)
; Returns applied annotation count, or -1. Callbacks run synchronously.

%define A_TEXT       0
%define A_TEXT_LEN   8
%define A_ITEMS     16
%define A_COUNT     24
%define A_VOTER     32
%define A_VOTER_LEN 40
%define A_TIME      48
%define A_LOOKUP    56
%define A_PUT       64
%define A_CTX       72
%define A_KEY       80
%define A_KEY_CAP   88
%define A_RECORD    96

section .text
karma_apply_annotations:
    test rdi, rdi
    jz .apply_error
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, [r12 + A_ITEMS]
    mov r14, [r12 + A_COUNT]
    xor ebx, ebx                ; applied count
    test r13, r13
    jz .apply_error_frame
    cmp qword [r12 + A_LOOKUP], 0
    je .apply_error_frame
    cmp qword [r12 + A_PUT], 0
    je .apply_error_frame
    cmp qword [r12 + A_KEY], 0
    je .apply_error_frame
    cmp qword [r12 + A_RECORD], 0
    je .apply_error_frame

.item_loop:
    cmp rbx, r14
    jae .apply_done
    mov rax, rbx
    shl rax, 4
    lea r15, [r13 + rax]        ; current annotation
    mov rax, [r15]              ; offset
    add rax, [r15 + 8]          ; offset + length
    jc .apply_error_frame
    cmp rax, [r12 + A_TEXT_LEN]
    ja .apply_error_frame

    mov rdi, [r12 + A_TEXT]
    test rdi, rdi
    jz .apply_error_frame
    add rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r12 + A_KEY]
    mov rcx, [r12 + A_KEY_CAP]
    call karma_key_normalize
    test rax, rax
    js .apply_error_frame
    mov [rbp - 48], rax         ; normalized key length

    ; lookup(ctx, key, key_len, record)
    mov rdi, [r12 + A_CTX]
    mov rsi, [r12 + A_KEY]
    mov rdx, [rbp - 48]
    mov rcx, [r12 + A_RECORD]
    call qword [r12 + A_LOOKUP]
    cmp eax, 0
    jl .apply_error_frame
    cmp eax, 1
    je .record_ready
    ; Initialise a new record using the first spelling of the subject.
    mov rax, [r12 + A_RECORD]
    mov rcx, [r15]
    add rcx, [r12 + A_TEXT]
    mov [rax], rcx
    mov rcx, [r15 + 8]
    mov [rax + 8], rcx
    mov rcx, [r12 + A_KEY]
    mov [rax + 16], rcx
    mov qword [rax + 24], 0
    mov qword [rax + 32], 0
    mov qword [rax + 40], 0
    mov qword [rax + 48], 0
    mov qword [rax + 56], 0
    mov qword [rax + 64], 0
    mov qword [rax + 72], 0
    mov qword [rax + 80], 0

.record_ready:
    mov rdi, [r12 + A_RECORD]
    mov esi, [r15 + 12]
    mov rdx, [r12 + A_VOTER]
    mov rcx, [r12 + A_VOTER_LEN]
    mov r8, [r12 + A_TIME]
    call karma_record_apply
    test eax, eax
    jnz .apply_error_frame

    mov rdi, [r12 + A_CTX]
    mov rsi, [r12 + A_RECORD]
    call qword [r12 + A_PUT]
    test eax, eax
    js .apply_error_frame
    inc rbx
    jmp .item_loop

.apply_done:
    mov rax, rbx
    jmp .apply_return
.apply_error_frame:
    mov rax, -1
.apply_return:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.apply_error:
    mov rax, -1
    ret
