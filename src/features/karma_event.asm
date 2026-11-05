; IRC PRIVMSG/CTCP ACTION event adapter for persistent Karma recording.
default rel
global karma_irc_event_callback

extern bot_irc_privmsg_views
extern karma_parse_annotations
extern karma_apply_annotations
extern karma_sqlite_lookup
extern karma_sqlite_put
extern clock_gettime

section .text
; Event context (56 bytes):
; +0 karma_sqlite_context pointer
; +8 annotation buffer pointer
; +16 annotation capacity (number of 16-byte entries)
; +24 normalized-key scratch pointer
; +32 normalized-key scratch capacity
; +40 karma_record scratch pointer
;
; Callback ABI: void callback(ctx,line,line_len,parsed_message).
; Returns are ignored by irc_event_dispatch; direct callers may observe the
; annotation count or -1 for malformed input/storage failure.
karma_irc_event_callback:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 264

    mov r12, rdi                ; feature context
    mov r13, rsi                ; original IRC line
    mov r14, rdx                ; line length
    mov r15, rcx                ; parsed message
    test r12, r12
    jz .event_error

    ; Extract the source nick and raw PRIVMSG body.
    mov rdi, r13
    mov rsi, r14
    mov rdx, r15
    mov rcx, rsp
    call bot_irc_privmsg_views
    cmp eax, 1
    je .event_user_message
    test eax, eax
    jz .event_ignored
    jmp .event_error

.event_user_message:
    mov rax, [rsp]
    mov [rsp + 64], rax         ; voter nick
    mov rax, [rsp + 8]
    mov [rsp + 72], rax         ; voter length
    mov rax, [rsp + 32]
    mov [rsp + 48], rax         ; text pointer
    mov rax, [rsp + 40]
    mov [rsp + 56], rax         ; text length

    ; Treat CTCP ACTION bodies as their visible text, excluding delimiters.
    mov r10, [rsp + 48]
    mov r11, [rsp + 56]
    cmp r11, 9
    jb .event_parse
    cmp byte [r10], 1
    jne .event_parse
    cmp byte [r10 + 1], 'A'
    jne .event_parse
    cmp byte [r10 + 2], 'C'
    jne .event_parse
    cmp byte [r10 + 3], 'T'
    jne .event_parse
    cmp byte [r10 + 4], 'I'
    jne .event_parse
    cmp byte [r10 + 5], 'O'
    jne .event_parse
    cmp byte [r10 + 6], 'N'
    jne .event_parse
    cmp byte [r10 + 7], ' '
    jne .event_parse
    lea rax, [r10 + 8]
    cmp byte [r10 + r11 - 1], 1
    jne .event_parse
    mov [rsp + 48], rax
    sub r11, 9
    mov [rsp + 56], r11

.event_parse:
    ; Parse annotations into the caller-owned array.
    mov rdi, [rsp + 48]
    mov rsi, [rsp + 56]
    mov rdx, [r12 + 8]
    mov rcx, [r12 + 16]
    call karma_parse_annotations
    test rax, rax
    js .event_error
    test rax, rax
    jz .event_ignored
    mov rbx, rax

    ; Obtain wall-clock Unix milliseconds for the record metadata.
    xor edi, edi                ; CLOCK_REALTIME
    lea rsi, [rsp + 88]
    call clock_gettime
    test eax, eax
    jnz .event_error
    mov rax, [rsp + 88]
    imul rax, rax, 1000
    mov rcx, [rsp + 96]
    mov rdx, 1000000
    mov r8, rdx
    mov rdx, rcx
    mov rax, rdx
    xor edx, edx
    div r8
    mov r9, rax
    mov rax, [rsp + 88]
    imul rax, rax, 1000
    add rax, r9
    mov [rsp + 80], rax

    ; Construct karma_apply_request at rsp+112.
    lea rdi, [rsp + 112]
    mov rax, [rsp + 48]
    mov [rdi], rax
    mov rax, [rsp + 56]
    mov [rdi + 8], rax
    mov rax, [r12 + 8]
    mov [rdi + 16], rax
    mov [rdi + 24], rbx
    mov rax, [rsp + 64]
    mov [rdi + 32], rax
    mov rax, [rsp + 72]
    mov [rdi + 40], rax
    mov rax, [rsp + 80]
    mov [rdi + 48], rax
    lea rax, [rel karma_sqlite_lookup]
    mov [rdi + 56], rax
    lea rax, [rel karma_sqlite_put]
    mov [rdi + 64], rax
    mov rax, [r12]
    mov [rdi + 72], rax
    mov rax, [r12 + 24]
    mov [rdi + 80], rax
    mov rax, [r12 + 32]
    mov [rdi + 88], rax
    mov rax, [r12 + 40]
    mov [rdi + 96], rax
    call karma_apply_annotations
    jmp .event_done

.event_ignored:
    xor eax, eax
    jmp .event_done
.event_error:
    mov eax, -1
.event_done:
    add rsp, 264
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
