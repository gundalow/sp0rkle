default rel

global karma_key_normalize
global karma_record_apply

; ssize_t karma_key_normalize(input, input_len, output, output_capacity)
; ASCII lowercases a subject for its persistent lookup key. Returns length
; or -1. Non-ASCII bytes are preserved; full Unicode folding is outstanding.
karma_key_normalize:
    test rdi, rdi
    jz .key_error
    test rdx, rdx
    jz .key_error
    cmp rsi, rcx
    jae .key_error
    xor r8d, r8d
.key_loop:
    cmp r8, rsi
    jae .key_done
    mov al, [rdi + r8]
    cmp al, 'A'
    jb .key_store
    cmp al, 'Z'
    ja .key_store
    add al, 32
.key_store:
    mov [rdx + r8], al
    inc r8
    jmp .key_loop
.key_done:
    mov byte [rdx + r8], 0
    mov rax, r8
    ret
.key_error:
    mov rax, -1
    ret

; struct karma_record (88 bytes):
; +0 subject ptr, +8 subject length, +16 normalized key ptr,
; +24 int64 score, +32 uint64 votes,
; +40 upvoter ptr, +48 upvoter length, +56 upvote Unix milliseconds,
; +64 downvoter ptr, +72 downvoter length, +80 downvote Unix milliseconds.
;
; int karma_record_apply(record, delta, voter, voter_len, unix_ms)
; delta must be +1 or -1. Returns 0 or -1 on invalid/overflow.
karma_record_apply:
    test rdi, rdi
    jz .record_error
    cmp esi, 1
    je .record_positive
    cmp esi, -1
    jne .record_error
    mov rax, [rdi + 24]
    mov r9, 0x8000000000000000
    cmp rax, r9
    je .record_error
    jmp .record_votes
.record_positive:
    mov rax, [rdi + 24]
    mov r9, 0x7fffffffffffffff
    cmp rax, r9
    je .record_error
.record_votes:
    mov rax, [rdi + 32]
    cmp rax, 0xffffffffffffffff
    je .record_error
    inc qword [rdi + 32]
    cmp esi, 1
    jne .record_down
    inc qword [rdi + 24]
    mov [rdi + 40], rdx
    mov [rdi + 48], rcx
    mov [rdi + 56], r8
    xor eax, eax
    ret
.record_down:
    dec qword [rdi + 24]
    mov [rdi + 64], rdx
    mov [rdi + 72], rcx
    mov [rdi + 80], r8
    xor eax, eax
    ret
.record_error:
    mov eax, -1
    ret
