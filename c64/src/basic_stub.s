;==============================================================================
; basic_stub.s - .prg load address and BASIC line 10 SYS 2061
;==============================================================================

        .import Start

        .segment "LOADADDR"
        .word   $0801

        .segment "EXEHDR"
        .word   NextLine                ; link to next line
        .word   10                      ; line number
        .byte   $9E                     ; SYS token
        .byte   "2061"                  ; = $080D
        .byte   0
NextLine:
        .word   0                       ; end of program
        jmp     Start                   ; $080D: the game image follows
