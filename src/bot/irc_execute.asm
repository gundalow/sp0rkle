default rel

extern bot_irc_privmsg_command_process
extern bot_irc_privmsg_context

global bot_irc_privmsg_execute

; int bot_irc_privmsg_execute(const struct bot_irc_command_request *request,
;                             void *handler_context)
; Executes the selected handler using this C callback ABI:
;   int handler(void *handler_context,
;               const struct bot_privmsg_context *context,
;               const char *normalized_args, size_t args_len)
; The Context and argument view are valid only for the duration of the call.
; Returns the handler's result, 0 when no command was dispatched, -1 on error.

%define EXEC_LOCAL_SIZE 88

section .text
bot_irc_privmsg_execute:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, EXEC_LOCAL_SIZE

    mov r12, rdi                ; request
    mov rbx, rsi                ; handler context
    lea r13, [rsp]              ; local prepared Context
    test r12, r12
    jz .exec_invalid

    mov rdi, r12
    call bot_irc_privmsg_command_process
    cmp eax, 1
    jne .exec_return
    mov rax, [r12 + 88]
    test rax, rax
    jz .exec_invalid
    mov r15, [rax]              ; selected handler
    test r15, r15
    jz .exec_invalid

    ; Rebuild the prepared Context for the synchronous handler invocation.
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    mov rdx, [r12 + 16]
    mov rcx, [r12 + 24]
    mov r8,  [r12 + 32]
    mov r9, r13
    call bot_irc_privmsg_context
    cmp eax, 1
    jne .exec_invalid

    mov r14, [r12 + 72]         ; normalized arguments
    test r14, r14
    jz .exec_invalid
    mov rcx, [r12 + 80]         ; capacity
    test rcx, rcx
    jz .exec_invalid
    xor edx, edx
.args_len:
    cmp rdx, rcx
    jae .exec_invalid
    cmp byte [r14 + rdx], 0
    je .invoke
    inc rdx
    jmp .args_len

.invoke:
    mov rdi, rbx
    mov rsi, r13
    mov rcx, rdx
    mov rdx, r14
    call r15
    jmp .exec_return

.exec_invalid:
    mov eax, -1
.exec_return:
    add rsp, EXEC_LOCAL_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
