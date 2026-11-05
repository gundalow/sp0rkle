default rel

extern bot_irc_privmsg_context
extern bot_irc_privmsg_views
extern bot_is_factoid_addition
extern bot_command_process

global bot_irc_privmsg_command_process

; struct bot_irc_command_request (96 bytes):
;  +0 line pointer, +8 line length, +16 parsed IRC message
; +24 bot nick pointer, +32 bot nick length
; +40 filters, +48 filter count (u32)
; +56 command entries, +64 command count (u32)
; +72 output args, +80 output capacity, +88 output handler pointer
;
; int bot_irc_privmsg_command_process(const request *)
; Returns 1 dispatched, 0 ignored/non-PRIVMSG/filtered/unmatched, -1 error.
; Context views are built from the input line and remain caller-owned.
; Factoid-addition detection is evaluated against the raw PRIVMSG body.

%define REQ_LINE          0
%define REQ_LINE_LEN      8
%define REQ_MESSAGE      16
%define REQ_BOTNICK       24
%define REQ_BOTNICK_LEN   32
%define REQ_FILTERS       40
%define REQ_FILTER_COUNT  48
%define REQ_COMMANDS      56
%define REQ_COMMAND_COUNT 64
%define REQ_OUT_ARGS      72
%define REQ_OUT_CAP       80
%define REQ_OUT_HANDLER   88
%define LOCAL_SIZE       232

section .text
bot_irc_privmsg_command_process:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, LOCAL_SIZE

    mov r12, rdi
    lea r13, [rsp]              ; prepared Context (72 bytes)
    lea r14, [rsp + 72]         ; raw PRIVMSG views (48 bytes)
    lea r15, [rsp + 128]        ; bot_command_request (96 bytes)

    test r12, r12
    jz .invalid

    ; Prepare sender, body, addressed flag and reply target.
    mov rdi, [r12 + REQ_LINE]
    mov rsi, [r12 + REQ_LINE_LEN]
    mov rdx, [r12 + REQ_MESSAGE]
    mov rcx, [r12 + REQ_BOTNICK]
    mov r8,  [r12 + REQ_BOTNICK_LEN]
    mov r9, r13
    call bot_irc_privmsg_context
    cmp eax, 1
    jne .adapter_return

    ; Preserve the raw body separately for the factoid-addition predicate.
    mov rdi, [r12 + REQ_LINE]
    mov rsi, [r12 + REQ_LINE_LEN]
    mov rdx, [r12 + REQ_MESSAGE]
    mov rcx, r14
    call bot_irc_privmsg_views
    cmp eax, 1
    jne .invalid
    mov rdi, [r14 + 32]
    mov rsi, [r14 + 40]
    call bot_is_factoid_addition
    mov ebx, eax

    ; Construct the existing 96-byte command request on our stack.
    mov rax, [r12 + REQ_FILTERS]
    mov [r15], rax
    mov eax, [r12 + REQ_FILTER_COUNT]
    mov [r15 + 8], eax
    mov rax, [r13]
    mov [r15 + 16], rax
    mov rax, [r13 + 8]
    mov [r15 + 24], rax
    mov rax, [r12 + REQ_COMMANDS]
    mov [r15 + 32], rax
    mov eax, [r12 + REQ_COMMAND_COUNT]
    mov [r15 + 40], eax
    mov rax, [r13 + 32]
    mov [r15 + 48], rax
    mov rax, [r13 + 40]
    mov [r15 + 56], rax
    mov eax, [r13 + 64]
    mov [r15 + 64], eax
    mov [r15 + 68], ebx
    mov rax, [r12 + REQ_OUT_ARGS]
    mov [r15 + 72], rax
    mov rax, [r12 + REQ_OUT_CAP]
    mov [r15 + 80], rax
    mov rax, [r12 + REQ_OUT_HANDLER]
    mov [r15 + 88], rax

    mov rdi, r15
    call bot_command_process
    jmp .return

.adapter_return:
    ; No context event: clear valid outputs consistently with command_process.
    cmp eax, 0
    jne .return
    mov rax, [r12 + REQ_OUT_ARGS]
    test rax, rax
    jz .clear_handler
    cmp qword [r12 + REQ_OUT_CAP], 0
    je .clear_handler
    mov byte [rax], 0
.clear_handler:
    mov rax, [r12 + REQ_OUT_HANDLER]
    test rax, rax
    jz .return
    mov qword [rax], 0
    xor eax, eax
    jmp .return

.invalid:
    mov eax, -1
.return:
    add rsp, LOCAL_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
