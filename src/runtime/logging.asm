default rel

global log_info
global log_error
extern puts

; Minimal line logger. Caller owns the NUL-terminated message.
; Later milestones add levels, timestamps and stderr routing.
section .text
log_info:
    jmp puts
log_error:
    jmp puts
