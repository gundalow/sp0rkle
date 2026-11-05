default rel

global bot_command_match
global bot_command_normalize_args

; struct bot_command_entry (32 bytes):
;   +0  const char *prefix
;   +8  uint64_t prefix_len
;   +16 void *handler
;   +24 const char *help
;
; const struct bot_command_entry *bot_command_match(
;   entries, count, text, text_len, size_t *matched_prefix_len)
; Returns the entry with the longest ASCII-case-insensitive prefix match,
; or NULL. Equal-length ties retain the first registered entry.
; Prefixes are byte strings; callers supply explicit lengths.

section .text
bot_command_match:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                ; entries
    mov r13d, esi               ; count
    mov r14, rdx                ; text
    mov r15, rcx                ; text length
    mov rbx, r8                 ; output matched length
    xor r10d, r10d              ; index
    xor r11d, r11d              ; best length
    xor eax, eax                ; best entry (NULL)

    test rbx, rbx
    jz .scan
    mov qword [rbx], 0

.scan:
    cmp r10d, r13d
    jae .done
    mov r9, r10
    shl r9, 5
    lea r8, [r12 + r9]          ; current entry
    mov rcx, [r8 + 8]           ; prefix length
    test rcx, rcx
    jz .next
    cmp rcx, r15
    ja .next
    cmp rcx, r11
    jbe .next                   ; only strictly longer matches can win

    mov rdi, [r8]               ; prefix
    xor edx, edx
.compare:
    cmp rdx, rcx
    jae .matched
    movzx esi, byte [rdi + rdx]
    movzx r9d, byte [r14 + rdx]
    cmp sil, 'A'
    jb .prefix_ready
    cmp sil, 'Z'
    ja .prefix_ready
    add sil, 32
.prefix_ready:
    cmp r9b, 'A'
    jb .text_ready
    cmp r9b, 'Z'
    ja .text_ready
    add r9b, 32
.text_ready:
    cmp sil, r9b
    jne .next
    inc rdx
    jmp .compare

.matched:
    mov r11, rcx
    mov rax, r8
.next:
    inc r10d
    jmp .scan

.done:
    test rbx, rbx
    jz .return
    mov [rbx], r11
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; ssize_t bot_command_normalize_args(input, input_len, output, output_capacity)
; Trims leading/trailing ASCII whitespace and compresses each internal run
; to one space. Capacity includes the terminating NUL. Returns output length,
; or -1 when output is null/too small. On failure, output[0] is cleared when
; possible. The input and output may not overlap.
bot_command_normalize_args:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    xor ebx, ebx
    xor r10d, r10d
    xor r11d, r11d              ; pending whitespace

    test r14, r14
    jz .error
    test r15, r15
    jz .error

.scan:
    cmp r10, r13
    jae .finish
    movzx eax, byte [r12 + r10]
    inc r10
    cmp al, ' '
    je .space
    cmp al, 9
    jb .character
    cmp al, 13
    jbe .space
.character:
    test r11d, r11d
    jz .write_char
    test rbx, rbx
    jz .clear_pending
    lea rdx, [rbx + 1]
    cmp rdx, r15
    jae .error
    mov byte [r14 + rbx], ' '
    inc rbx
.clear_pending:
    xor r11d, r11d
.write_char:
    lea rdx, [rbx + 1]
    cmp rdx, r15
    jae .error
    mov [r14 + rbx], al
    inc rbx
    jmp .scan
.space:
    test rbx, rbx
    jz .scan
    mov r11d, 1
    jmp .scan
.finish:
    mov byte [r14 + rbx], 0
    mov rax, rbx
    jmp .return
.error:
    test r14, r14
    jz .error_return
    test r15, r15
    jz .error_return
    mov byte [r14], 0
.error_return:
    mov rax, -1
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
