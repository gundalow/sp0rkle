default rel

global irc_line_length
global irc_parse_message

; struct irc_message layout (all fields are uint32_t):
;   0 tags_offset       4 tags_length
;   8 prefix_offset    12 prefix_length
;  16 command_offset   20 command_length
;  24 param_count      28 flags (bit 0 = trailing parameter present)
;  32 params[15], each { offset, length }
%define IRC_MSG_SIZE 152
%define IRC_PARAMS_OFFSET 32
%define IRC_MAX_PARAMS 15
%define IRC_FLAG_TRAILING 1

section .text
; size_t irc_line_length(const char *line)
; Return bytes before NUL, CR or LF. For trusted NUL-terminated strings only.
irc_line_length:
    xor eax, eax
.loop:
    mov dl, [rdi + rax]
    test dl, dl
    jz .done
    cmp dl, 10
    je .done
    cmp dl, 13
    je .done
    inc rax
    jmp .loop
.done:
    ret

; int irc_parse_message(const uint8_t *buf, size_t len,
;                       struct irc_message *out)
; RDI=buffer, RSI=length, RDX=output. Returns 0 on success, -1 on malformed
; input. Offsets refer to the original buffer; no strings are copied.
; The caller must provide IRC_MSG_SIZE writable bytes for out.
irc_parse_message:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                ; input buffer
    mov r13, rsi                ; input length
    mov r14, rdx                ; output structure
    xor ebx, ebx                ; current offset
    xor r15d, r15d              ; parameter count

    ; Clear the complete output structure.
    mov rdi, r14
    xor eax, eax
    mov ecx, IRC_MSG_SIZE / 4
    rep stosd

    test r13, r13
    jz .bad

    ; Reject line terminators and NUL inside the explicit-length frame.
    xor ebx, ebx
.validate:
    cmp rbx, r13
    jae .validated
    mov al, [r12 + rbx]
    test al, al
    jz .bad
    cmp al, 10
    je .bad
    cmp al, 13
    je .bad
    inc rbx
    jmp .validate

.validated:
    xor ebx, ebx

    ; Optional IRCv3 tags: @tag=value;tag=value<space>
    cmp byte [r12], '@'
    jne .prefix
    mov ebx, 1
.tags_scan:
    cmp rbx, r13
    jae .bad
    cmp byte [r12 + rbx], ' '
    je .tags_end
    inc rbx
    jmp .tags_scan
.tags_end:
    cmp rbx, 1
    jbe .bad
    mov dword [r14 + 0], 1
    mov eax, ebx
    dec eax
    mov [r14 + 4], eax
    inc rbx
.tags_skip_spaces:
    cmp rbx, r13
    jae .bad
    cmp byte [r12 + rbx], ' '
    jne .prefix
    inc rbx
    jmp .tags_skip_spaces

.prefix:
    ; Optional source prefix: :server or :nick!user@host
    cmp byte [r12 + rbx], ':'
    jne .command
    inc rbx
    mov r9, rbx                ; prefix content start
.prefix_scan:
    cmp rbx, r13
    jae .bad
    cmp byte [r12 + rbx], ' '
    je .prefix_end
    inc rbx
    jmp .prefix_scan
.prefix_end:
    cmp rbx, 1
    jbe .bad
    mov [r14 + 8], r9d
    mov eax, ebx
    sub eax, r9d
    mov [r14 + 12], eax
    inc rbx
.prefix_skip_spaces:
    cmp rbx, r13
    jae .bad
    cmp byte [r12 + rbx], ' '
    jne .command
    inc rbx
    jmp .prefix_skip_spaces

.command:
    ; Command is alphabetic or exactly three decimal digits.
    mov r10, rbx
.command_scan:
    cmp rbx, r13
    jae .command_end
    mov al, [r12 + rbx]
    cmp al, ' '
    je .command_end
    inc rbx
    jmp .command_scan
.command_end:
    test ebx, ebx
    jz .bad
    mov r11, rbx
    sub r11, r10
    test r11, r11
    jz .bad
    mov [r14 + 16], r10d
    mov [r14 + 20], r11d
    ; Determine whether the command is numeric from its first byte.
    mov al, [r12 + r10]
    cmp al, '0'
    jb .alpha_command
    cmp al, '9'
    ja .alpha_command
    cmp r11, 3
    jne .bad
    lea r9, [r12 + r10]
    xor ecx, ecx
.numeric_scan:
    cmp rcx, r11
    jae .command_done
    mov al, [r9 + rcx]
    cmp al, '0'
    jb .bad
    cmp al, '9'
    ja .bad
    inc rcx
    jmp .numeric_scan
.alpha_command:
    lea r9, [r12 + r10]
    xor ecx, ecx
.alpha_scan:
    cmp rcx, r11
    jae .command_done
    mov al, [r9 + rcx]
    cmp al, 'A'
    jb .alpha_lower
    cmp al, 'Z'
    jbe .alpha_next
.alpha_lower:
    cmp al, 'a'
    jb .bad
    cmp al, 'z'
    ja .bad
.alpha_next:
    inc rcx
    jmp .alpha_scan
.command_done:
    test r11, r11
    jz .bad
    inc rbx
    jmp .skip_spaces

.skip_spaces:
    cmp rbx, r13
    jae .success
    cmp byte [r12 + rbx], ' '
    jne .parameters
    inc rbx
    jmp .skip_spaces

.parameters:
    cmp r15, IRC_MAX_PARAMS
    jae .bad
    ; A colon at parameter start consumes the entire remaining frame.
    cmp byte [r12 + rbx], ':'
    jne .middle_parameter
    or dword [r14 + 28], IRC_FLAG_TRAILING
    inc rbx
    mov eax, ebx
    mov ecx, r15d
    shl ecx, 3
    add ecx, IRC_PARAMS_OFFSET
    mov [r14 + rcx], eax
    mov eax, r13d
    sub eax, ebx
    mov [r14 + rcx + 4], eax
    inc r15
    jmp .success

.middle_parameter:
    mov r8, rbx
.middle_scan:
    cmp rbx, r13
    jae .middle_end
    cmp byte [r12 + rbx], ' '
    je .middle_end
    inc rbx
    jmp .middle_scan
.middle_end:
    mov eax, r8d
    mov ecx, r15d
    shl ecx, 3
    add ecx, IRC_PARAMS_OFFSET
    mov [r14 + rcx], eax
    mov eax, ebx
    sub eax, r8d
    mov [r14 + rcx + 4], eax
    inc r15
    jmp .skip_spaces

.success:
    mov [r14 + 24], r15d
    xor eax, eax
    jmp .return
.bad:
    mov eax, -1
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
