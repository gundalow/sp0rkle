default rel

global bot_irc_privmsg_views

; int bot_irc_privmsg_views(line, line_len, message, out)
; Output struct (48 bytes):
;   +0 sender nick pointer, +8 sender nick length
;  +16 target pointer,      +24 target length
;  +32 text pointer,        +40 text length
; Returns 1 for a valid user-originated PRIVMSG, 0 for another command or
; non-user prefix, and -1 for invalid pointers/offsets/parameter structure.
; All returned pointers refer into the caller-owned original IRC line.
%define MSG_PREFIX_OFFSET 8
%define MSG_PREFIX_LENGTH 12
%define MSG_COMMAND_OFFSET 16
%define MSG_COMMAND_LENGTH 20
%define MSG_PARAM_COUNT 24
%define MSG_PARAMS 32
%define MSG_SIZE 152

section .text
bot_irc_privmsg_views:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov r12, rdi                ; line
    mov r13, rsi                ; line length
    mov r14, rdx                ; parsed message
    mov r15, rcx                ; output

    test r12, r12
    jz .invalid
    test r14, r14
    jz .invalid
    test r15, r15
    jz .invalid

    ; A non-PRIVMSG command is an ordinary, non-context event.
    cmp dword [r14 + MSG_COMMAND_LENGTH], 7
    jne .not_privmsg
    mov eax, [r14 + MSG_COMMAND_OFFSET]
    cmp rax, r13
    jae .invalid
    mov ecx, r13d
    sub ecx, eax
    cmp ecx, 7
    jb .invalid
    lea rsi, [r12 + rax]
    lea rdi, [rel privmsg_name]
    mov ecx, 7
.compare_command:
    mov al, [rdi]
    mov dl, [rsi]
    cmp al, 'a'
    jb .command_left_folded
    cmp al, 'z'
    ja .command_left_folded
    sub al, 32
.command_left_folded:
    cmp dl, 'a'
    jb .command_right_folded
    cmp dl, 'z'
    ja .command_right_folded
    sub dl, 32
.command_right_folded:
    cmp al, dl
    jne .not_privmsg
    inc rdi
    inc rsi
    dec ecx
    jnz .compare_command

    ; Require at least target and trailing text parameters.
    cmp dword [r14 + MSG_PARAM_COUNT], 2
    jb .invalid

    ; Validate the source prefix and extract the nick before ! or @.
    mov eax, [r14 + MSG_PREFIX_OFFSET]
    mov edx, [r14 + MSG_PREFIX_LENGTH]
    test edx, edx
    jz .not_user
    cmp eax, r13d
    jae .invalid
    mov ecx, r13d
    sub ecx, eax
    cmp edx, ecx
    ja .invalid
    lea rbx, [r12 + rax]
    xor ecx, ecx
.scan_nick:
    cmp ecx, edx
    jae .not_user
    mov al, [rbx + rcx]
    cmp al, '!'
    je .nick_end
    cmp al, '@'
    je .nick_end
    inc ecx
    jmp .scan_nick
.nick_end:
    test ecx, ecx
    jz .not_user
    mov [r15], rbx
    mov [r15 + 8], rcx

    ; Parameter 0: target.
    mov eax, [r14 + MSG_PARAMS]
    mov edx, [r14 + MSG_PARAMS + 4]
    cmp eax, r13d
    jae .invalid
    mov ecx, r13d
    sub ecx, eax
    cmp edx, ecx
    ja .invalid
    lea rax, [r12 + rax]
    mov [r15 + 16], rax
    mov [r15 + 24], rdx

    ; Parameter 1: message body.
    mov eax, [r14 + MSG_PARAMS + 8]
    mov edx, [r14 + MSG_PARAMS + 12]
    cmp eax, r13d
    ja .invalid
    mov ecx, r13d
    sub ecx, eax
    cmp edx, ecx
    ja .invalid
    lea rax, [r12 + rax]
    mov [r15 + 32], rax
    mov [r15 + 40], rdx
    mov eax, 1
    jmp .return

.not_user:
    xor eax, eax
    jmp .return
.not_privmsg:
    xor eax, eax
    jmp .return
.invalid:
    mov eax, -1
.return:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


extern bot_context_prepare_privmsg
extern bot_context_resolve_target

global bot_irc_privmsg_context

; int bot_irc_privmsg_context(line,line_len,message,botnick,botnick_len,out)
; Output struct (72 bytes):
;  +0 nick ptr, +8 nick len, +16 original target ptr, +24 target len
; +32 prepared body ptr, +40 body len, +48 reply target ptr, +56 reply len
; +64 addressed (u32; remaining bytes reserved).
; Returns 1 for a user PRIVMSG, 0 for non-context events, -1 on malformed input.
bot_irc_privmsg_context:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov [rbp - 56], r9

    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, [rbp - 56]
    call bot_irc_privmsg_views
    cmp eax, 1
    jne .context_adapter_return

    ; Prepare the body and addressed state, retaining the original views.
    mov rdi, [rbp - 56]
    mov rdi, [rdi + 32]
    mov rsi, [rbp - 56]
    mov rsi, [rsi + 40]
    mov rdx, r15
    mov rcx, rbx
    mov r8, [rbp - 56]
    mov r8, [r8 + 16]
    mov r9, [rbp - 56]
    mov r9, [r9 + 24]
    call bot_context_prepare_privmsg
    ; Context preparation returns {start in RAX, len/addressed packed in RDX}.
    mov [rbp - 80], rax
    mov ecx, edx
    mov [rbp - 88], rcx
    shr rdx, 32
    mov [rbp - 96], edx

    ; Replace raw text view with the trimmed/address-prefix-stripped body.
    mov rax, [rbp - 56]
    mov rcx, [rax + 32]
    add rcx, [rbp - 80]
    mov [rax + 32], rcx
    mov rcx, [rbp - 88]
    mov [rax + 40], rcx

    ; Resolve Line.Target(): channel target, otherwise sender nick.
    mov rdi, [rax + 16]
    mov rsi, [rax + 24]
    mov rdx, [rax]
    mov rcx, [rax + 8]
    call bot_context_resolve_target
    mov [rbp - 104], rax
    mov [rbp - 112], rdx

    mov rax, [rbp - 56]
    mov rcx, [rbp - 104]
    mov [rax + 48], rcx
    mov rcx, [rbp - 112]
    mov [rax + 56], rcx
    mov ecx, [rbp - 96]
    mov [rax + 64], ecx
    mov eax, 1

.context_adapter_return:
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


section .rodata
privmsg_name: db "PRIVMSG"
