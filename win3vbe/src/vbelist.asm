; VBELIST.COM - list the 256-colour (and other) VESA modes offered by the video BIOS.
; Dmitry Brant, 2026.
; Output: one line per mode: mode, width x height, bits/pixel, memory model,
; window granularity / size (K), bytes per scan line.     nasm -f bin -o VBELIST.COM vbelist.asm
        bits    16
        cpu     386
        org     0x100

        mov     ax, 0x4F00
        mov     di, info
        int     0x10
        cmp     ax, 0x004F
        jne     novbe
        mov     dx, hdr
        call    puts
        mov     ax, [info+4]            ; VBE version
        call    hexw
        mov     dx, mem
        call    puts
        mov     ax, [info+0x12]         ; memory in 64K units
        shl     ax, 6
        call    decw
        mov     dx, kb
        call    puts
        ; copy mode list
        push    ds
        lds     si, [info+0x0E]
        mov     di, modes
        mov     cx, 255
.cp:    lodsw
        stosw
        cmp     ax, 0xFFFF
        je      .cpd
        loop    .cp
        mov     word [es:di], 0xFFFF
.cpd:   pop     ds
        mov     si, modes
.next:  lodsw
        cmp     ax, 0xFFFF
        je      done
        mov     [cur], ax
        push    si
        mov     cx, ax
        mov     ax, 0x4F01
        mov     di, minfo
        int     0x10
        cmp     ax, 0x004F
        jne     .skip
        test    byte [minfo], 1         ; supported?
        jz      .skip
        mov     ax, [cur]
        call    hexw
        mov     al, ' '
        call    putc
        mov     ax, [minfo+0x12]
        call    decw
        mov     al, 'x'
        call    putc
        mov     ax, [minfo+0x14]
        call    decw
        mov     al, 'x'
        call    putc
        movzx   ax, byte [minfo+0x19]
        call    decw
        mov     dx, model
        call    puts
        movzx   ax, byte [minfo+0x1B]
        call    decw
        mov     dx, gran
        call    puts
        mov     ax, [minfo+4]
        call    decw
        mov     al, '/'
        call    putc
        mov     ax, [minfo+6]
        call    decw
        mov     dx, pitch
        call    puts
        mov     ax, [minfo+0x10]
        call    decw
        mov     dx, crlf
        call    puts
.skip:  pop     si
        jmp     .next
novbe:  mov     dx, nomsg
        call    puts
done:   mov     ax, 0x4C00
        int     0x21

puts:   mov     ah, 9
        int     0x21
        ret
putc:   push    dx
        mov     dl, al
        mov     ah, 2
        int     0x21
        pop     dx
        ret
hexw:   mov     cx, 4
.l:     rol     ax, 4
        push    ax
        and     al, 15
        add     al, '0'
        cmp     al, '9'
        jbe     .o
        add     al, 7
.o:     call    putc
        pop     ax
        loop    .l
        ret
decw:   xor     cx, cx
        mov     bx, 10
.d:     xor     dx, dx
        div     bx
        push    dx
        inc     cx
        or      ax, ax
        jnz     .d
.p:     pop     ax
        add     al, '0'
        call    putc
        loop    .p
        ret

hdr     db      'VBE version $'
mem     db      ', video memory $'
kb      db      'K', 13, 10, 'mode  resolution   model  gran/win(K)  pitch', 13, 10, '$'
model   db      '  model $'
gran    db      '  win $'
pitch   db      'K  pitch $'
crlf    db      13, 10, '$'
nomsg   db      'No VESA BIOS found.', 13, 10, '$'
cur     dw      0
info    times 512 db 0
minfo   times 256 db 0
modes   times 512 db 0
