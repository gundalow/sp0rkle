default rel

global irc_line_length

section .text
; size_t irc_line_length(const char *line)
; Return bytes before NUL, CR or LF. Network parsing will use explicit lengths.
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
