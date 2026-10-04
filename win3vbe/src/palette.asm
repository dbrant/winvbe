; ---------------------------------------------------------------------------
; Palette manager support (256 colours): SetPalette, GetPalette,
; SetPaletteTranslate, GetPaletteTranslate, UpdateColors
;
; pal_rgb holds the hardware palette (R, G, B, flags per entry).  GDI's
; translate table maps the indices of the foreground palette to hardware
; indices: colours drawn on the screen (pens, brushes, text, and bitmaps
; copied from memory) go through it, bitmaps read back from the screen go
; through its inverse.
; ---------------------------------------------------------------------------

; SetPalette(wStartIndex, wNumEntries, lpPalette)
SetPalette:
        PROLOG
        mov     ax, [bp+12]             ; start
        mov     cx, [bp+10]             ; count
        call    pal_range
        jcxz    .r
        push    ax
        push    cx
        push    ds
        pop     es
        mov     di, ax
        shl     di, 2
        add     di, pal_rgb
        push    ds
        lds     si, [bp+6]
        shl     cx, 1
        rep     movsw
        pop     ds
        pop     cx
        pop     ax
        cmp     byte [enabled], 0       ; in the background: set on return
        je      .r
        call    dac_load
.r:     EPILOG  8

; GetPalette(wStartIndex, wNumEntries, lpPalette)
GetPalette:
        PROLOG
        mov     ax, [bp+12]
        mov     cx, [bp+10]
        call    pal_range
        jcxz    .r
        les     di, [bp+6]
        mov     si, ax
        shl     si, 2
        add     si, pal_rgb
        shl     cx, 1
        rep     movsw
.r:     EPILOG  8

; pal_range: ax = start, cx = count -> cx clipped to the 256 entries
pal_range:
        cmp     ax, 256
        jae     .none
        mov     dx, 256
        sub     dx, ax
        cmp     cx, dx
        jbe     .r
        mov     cx, dx
.r:     ret
.none:  xor     cx, cx
        ret

; SetPaletteTranslate(lpTranslate): 256 WORD hardware indices, NULL = identity
SetPaletteTranslate:
        PROLOG
        les     si, [bp+6]
        mov     dx, es
        or      dx, si                  ; dx = 0: NULL
        xor     bx, bx
        mov     byte [pal_mod], 0
.l:     mov     al, bl                  ; identity
        or      dx, dx
        jz      .s
        mov     al, [es:si]
        add     si, 2
.s:     mov     [pal_xlat+bx], al
        cmp     al, bl
        je      .n
        mov     byte [pal_mod], 1
.n:     inc     bx
        cmp     bx, 256
        jb      .l
        ; the inverse: hardware index -> palette index (identity where unused)
        xor     bx, bx
.i:     mov     [pal_inv+bx], bl
        inc     bx
        cmp     bx, 256
        jb      .i
        mov     bx, 255
.v:     movzx   di, byte [pal_xlat+bx]
        mov     [pal_inv+di], bl
        dec     bx
        jns     .v
        mov     ax, 1
        EPILOG  4

; GetPaletteTranslate(lpTranslate)
GetPaletteTranslate:
        PROLOG
        les     di, [bp+6]
        mov     ax, es
        or      ax, di
        jz      .r
        xor     bx, bx
        xor     ah, ah
.l:     mov     al, [pal_xlat+bx]
        stosw
        inc     bx
        cmp     bx, 256
        jb      .l
.r:     mov     ax, 1
        EPILOG  4

; UpdateColors(wStartX, wStartY, wExtX, wExtY, lpTranslate): remap the
; screen pixels of the rectangle through lpTranslate (256 WORDs)
uc_x            equ 16
uc_y            equ 14
uc_w            equ 12
uc_h            equ 10
uc_lpTrans      equ 6

UpdateColors:
        PROLOG
        cmp     byte [enabled], 0
        je      .r
        les     si, [bp+uc_lpTrans]
        mov     ax, es
        or      ax, si
        jz      .r
        xor     bx, bx                  ; WORD table -> byte table
.t:     mov     al, [es:si]
        add     si, 2
        mov     [upd_tab+bx], al
        inc     bx
        cmp     bx, 256
        jb      .t
        ; clip to the screen
        mov     ax, [bp+uc_x]
        mov     cx, ax
        add     cx, [bp+uc_w]
        mov     bx, [bp+uc_y]
        mov     dx, bx
        add     dx, [bp+uc_h]
        or      ax, ax
        jns     .1
        xor     ax, ax
.1:     or      bx, bx
        jns     .2
        xor     bx, bx
.2:     cmp     cx, XRES
        jle     .3
        mov     cx, XRES
.3:     cmp     dx, YRES
        jle     .4
        mov     dx, YRES
.4:     cmp     ax, cx
        jge     .r
        cmp     bx, dx
        jge     .r
        mov     [g_x], ax
        mov     [g_y], bx
        sub     cx, ax
        mov     [g_w], cx
        sub     dx, bx
        mov     [g_h], dx
        mov     byte [dst+SURF.kind], SK_SCREEN
        call    blt_exclude
        mov     ax, [g_y]
.row:   mov     cx, [g_x]
        mov     dx, [g_w]
.ch:    push    dx
        cmp     dx, MAXW
        jbe     .cw
        mov     dx, MAXW
.cw:    mov     bx, dst
        mov     di, DBUF
        call    read_row
        push    cx
        mov     si, DBUF
        mov     cx, dx
        mov     bx, upd_tab
        call    xlat_row
        pop     cx
        mov     bx, dst
        call    write_row
        add     cx, dx
        mov     si, dx
        pop     dx
        sub     dx, si
        jnz     .ch
        inc     ax
        dec     word [g_h]
        jnz     .row
        call    blt_unexclude
.r:     mov     ax, 1
        EPILOG  12
