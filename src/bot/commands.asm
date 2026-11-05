default rel

global bot_command_match

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
