default rel

global bot_strip_address_prefix
global bot_context_prepare_privmsg

; int bot_strip_address_prefix(text, text_len, nick, nick_len,
;                              out_start, out_len)
; RDI=text, RSI=text_len, RDX=nick, RCX=nick_len,
; R8=out_start (size_t*), R9=out_len (size_t*).
; Returns 1 when text begins with nick followed by one of : ; , > -
; and optional surrounding ASCII whitespace is trimmed from the remainder.
; Returns 0 otherwise and writes zero outputs. Does not modify input.
; Private-message addressing (target == bot nick) is decided by caller.

section .text
bot_strip_address_prefix:
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
    test rbx, rbx
    jz .zero_len
    mov qword [rbx], 0
.zero_len:
    test r9, r9
    jz .check
    mov qword [r9], 0
.check:
    test r15, r15
    jz .no
    lea rax, [r15 + 1]
    cmp r13, rax
    jb .no
    xor r10d, r10d
.compare:
    cmp r10, r15
    jae .delimiter
    movzx eax, byte [r12 + r10]
    movzx edx, byte [r14 + r10]
    cmp al, 'A'
    jb .text_lower
    cmp al, 'Z'
    ja .text_lower
    add al, 32
.text_lower:
    cmp dl, 'A'
    jb .nick_lower
    cmp dl, 'Z'
    ja .nick_lower
    add dl, 32
.nick_lower:
    cmp al, dl
    jne .no
    inc r10
    jmp .compare
.delimiter:
    mov al, [r12 + r15]
    cmp al, ':'
    je .trim
    cmp al, ';'
    je .trim
    cmp al, ','
    je .trim
    cmp al, '>'
    je .trim
    cmp al, '-'
    jne .no
.trim:
    lea r10, [r15 + 1]
    mov r11, r13
    ; trim leading ASCII whitespace
.leading:
    cmp r10, r11
    jae .empty
    mov al, [r12 + r10]
    cmp al, ' '
    je .lead_one
    cmp al, 9
    jb .trailing
    cmp al, 13
    jbe .lead_one
    jmp .trailing
.lead_one:
    inc r10
    jmp .leading
.trailing:
    test r11, r11
    jz .store
    lea rax, [r11 - 1]
    cmp rax, r10
    jb .store
    movzx ecx, byte [r12 + rax]
    cmp cl, ' '
    je .trail_more
    cmp cl, 9
    jb .store
    cmp cl, 13
    jbe .trail_more
    jmp .store
.trail_more:
    mov r11, rax
    jmp .trailing
.empty:
    mov r11, r10
.store:
    test rbx, rbx
    jz .store_len
    mov [rbx], r10
.store_len:
    test r9, r9
    jz .yes
    mov rax, r11
    sub rax, r10
    mov [r9], rax
.yes:
    mov eax, 1
    jmp .done
.no:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; int bot_context_prepare_privmsg(text, text_len, botnick, nick_len,
;                                 target, target_len,
;                                 out_start, out_len, out_addressed)
; Mirrors newContext for PRIVMSG: trim outer ASCII whitespace, remove an
; optional botnick+(: ; , > -) address prefix, then mark addressed when the
; original target exactly equals the bot nick. Output offsets refer to text.
; Returns 0 on success, -1 for missing output pointers.
bot_context_prepare_privmsg:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72

    mov r12, rdi                ; text
    mov r13, rsi                ; text length
    mov r14, rdx                ; bot nick
    mov r15, rcx                ; nick length
    mov rbx, r8                 ; target
    mov [rbp - 48], r9          ; target length
    mov rax, [rbp + 16]
    mov [rbp - 88], rax         ; out_start
    mov rax, [rbp + 24]
    mov [rbp - 96], rax         ; out_len
    mov rax, [rbp + 32]
    mov [rbp - 104], rax        ; out_addressed

    cmp qword [rbp - 88], 0
    je .context_invalid
    cmp qword [rbp - 96], 0
    je .context_invalid
    cmp qword [rbp - 104], 0
    je .context_invalid

    xor r10d, r10d              ; trimmed start
    mov r11, r13                ; trimmed end
.context_leading:
    cmp r10, r11
    jae .context_trimmed
    movzx eax, byte [r12 + r10]
    cmp al, ' '
    je .context_lead_one
    cmp al, 9
    jb .context_trimmed
    cmp al, 13
    jbe .context_lead_one
    jmp .context_trimmed
.context_lead_one:
    inc r10
    jmp .context_leading
.context_trimmed:
.context_trailing:
    cmp r11, r10
    jbe .context_try_prefix
    lea rax, [r11 - 1]
    movzx ecx, byte [r12 + rax]
    cmp cl, ' '
    je .context_trail_one
    cmp cl, 9
    jb .context_try_prefix
    cmp cl, 13
    jbe .context_trail_one
    jmp .context_try_prefix
.context_trail_one:
    dec r11
    jmp .context_trailing

.context_try_prefix:
    mov [rbp - 56], r10         ; default output start
    mov [rbp - 64], r11         ; default output end
    test r15, r15
    jz .context_unprefixed
    mov rax, r11
    sub rax, r10
    lea rcx, [r15 + 1]
    cmp rax, rcx
    jb .context_unprefixed
    xor r8d, r8d
.context_prefix_compare:
    cmp r8, r15
    jae .context_check_delimiter
    mov rax, r10
    add rax, r8
    movzx eax, byte [r12 + rax]
    mov rdx, r8
    movzx edx, byte [r14 + rdx]
    cmp al, 'A'
    jb .context_text_folded
    cmp al, 'Z'
    ja .context_text_folded
    add al, 32
.context_text_folded:
    cmp dl, 'A'
    jb .context_nick_folded
    cmp dl, 'Z'
    ja .context_nick_folded
    add dl, 32
.context_nick_folded:
    cmp al, dl
    jne .context_unprefixed
    inc r8
    jmp .context_prefix_compare

.context_check_delimiter:
    mov rax, r10
    add rax, r15
    mov al, [r12 + rax]
    cmp al, ':'
    je .context_prefix_found
    cmp al, ';'
    je .context_prefix_found
    cmp al, ','
    je .context_prefix_found
    cmp al, '>'
    je .context_prefix_found
    cmp al, '-'
    jne .context_unprefixed

.context_prefix_found:
    lea r10, [r10 + r15 + 1]
.context_prefix_leading:
    cmp r10, r11
    jae .context_prefix_empty
    movzx eax, byte [r12 + r10]
    cmp al, ' '
    je .context_prefix_lead_one
    cmp al, 9
    jb .context_prefix_trailing
    cmp al, 13
    jbe .context_prefix_lead_one
    jmp .context_prefix_trailing
.context_prefix_lead_one:
    inc r10
    jmp .context_prefix_leading
.context_prefix_trailing:
    cmp r11, r10
    jbe .context_prefix_empty
    lea rax, [r11 - 1]
    movzx ecx, byte [r12 + rax]
    cmp cl, ' '
    je .context_prefix_trail_one
    cmp cl, 9
    jb .context_prefix_store
    cmp cl, 13
    jbe .context_prefix_trail_one
    jmp .context_prefix_store
.context_prefix_trail_one:
    dec r11
    jmp .context_prefix_trailing
.context_prefix_empty:
    mov r11, r10
.context_prefix_store:
    mov [rbp - 56], r10
    mov [rbp - 64], r11
    mov edx, 1
    jmp .context_store

.context_unprefixed:
    xor edx, edx
    ; The reference uses exact string equality for target == bot nick.
    mov r8, [rbp - 48]
    cmp r8, r15
    jne .context_store
    test r15, r15
    jz .context_store
    xor r9d, r9d
.context_target_compare:
    cmp r9, r15
    jae .context_private
    mov r8b, [rbx + r9]
    cmp r8b, [r14 + r9]
    jne .context_store
    inc r9
    jmp .context_target_compare
.context_private:
    mov edx, 1

.context_store:
    mov rax, [rbp - 56]
    mov r8, [rbp - 88]
    mov [r8], rax
    mov rax, [rbp - 64]
    sub rax, [rbp - 56]
    mov r8, [rbp - 96]
    mov [r8], rax
    mov r8, [rbp - 104]
    mov [r8], rdx
    xor eax, eax
    jmp .context_return

.context_invalid:
    mov eax, -1
.context_return:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
