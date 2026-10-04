; ---------------------------------------------------------------------------
; Output(lpDestDev, wStyle, wCount, lpPoints, lpPPen, lpPBrush, lpDrawMode,
;        lpClipRect)
; ---------------------------------------------------------------------------
op_lpDst        equ 0x1e
op_style        equ 0x1c
op_count        equ 0x1a
op_lpPoints     equ 0x16
op_lpPen        equ 0x12
op_lpBrush      equ 0x0e
op_lpDM         equ 0x0a
op_lpClip       equ 0x06

OS_SCANLINES    equ 4
OS_POLYLINE     equ 18
R2_NOP          equ 11

Output:
        PROLOG
        DBG     'Output '
        DBGX    [bp+op_style]
        DBGX    [bp+op_count]
        DBG     13,10
        les     si, [bp+op_lpDst]
        mov     bx, dst
        call    load_surf
        les     si, [bp+op_lpDM]
        call    get_dm_colors
        les     si, [bp+op_lpClip]
        call    set_clip
        mov     ax, 1
        cmp     word [g_rop2], R2_NOP
        je      .done
        mov     ax, [bp+op_style]
        cmp     ax, OS_SCANLINES
        je      .scan
        cmp     ax, OS_POLYLINE
        je      .poly
        xor     ax, ax
        jmp     .done
.scan:  call    do_scanlines
        jmp     .ok
.poly:  call    do_polyline
.ok:    mov     ax, 1
.done:  EPILOG  28

; ---------------------------------------------------------------------------
do_scanlines:
        mov     ax, [g_rop2]
        call    rop2_to_rop3
        mov     [g_rop], al
        call    rop_flags
        and     ah, ~ROPF_S
        mov     [g_ropf], ah
        ; pattern: brush, or pen colour if no brush
        les     si, [bp+op_lpBrush]
        mov     ax, es
        or      ax, si
        jz      .pen
        call    build_prow
        jc      .r
        jmp     .pat
.pen:   les     si, [bp+op_lpPen]
        mov     ax, es
        or      ax, si
        jz      .r
        cmp     word [es:si+PEN_STYLE], 5
        je      .r
        call    pen_value
        call    solid_prow
.pat:   ; transparent hatch?
        mov     byte [g_transp], 0
        cmp     byte [g_hatch], 0
        je      .nt
        cmp     word [g_bkmode], OPAQUE
        je      .nt
        mov     byte [g_transp], 1
        or      byte [g_ropf], ROPF_D
.nt:    les     si, [bp+op_lpPoints]
        mov     cx, [bp+op_count]
        dec     cx
        jle     .r
        mov     ax, [es:si+2]           ; y
        cmp     ax, [clip_y0]
        jl      .r
        cmp     ax, [clip_y1]
        jge     .r
        mov     [g_y], ax
        mov     word [g_h], 1
        add     si, 4
        mov     [sc_ptr], si
        mov     [sc_cnt], cx
        ; exclusion: whole row span of the clip rectangle
        mov     byte [g_excl], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .ne
        mov     ax, [clip_x0]
        mov     bx, [g_y]
        mov     cx, [clip_x1]
        mov     dx, bx
        inc     dx
        call    excl_begin
        mov     byte [g_excl], 1
.ne:    mov     al, [g_rop]
        call    build_rop_table
.seg:   les     si, [bp+op_lpPoints]
        mov     si, [sc_ptr]
        mov     ax, [es:si]             ; x left
        mov     cx, [es:si+2]           ; x right (exclusive)
        add     word [sc_ptr], 4
        cmp     ax, [clip_x0]
        jge     .a
        mov     ax, [clip_x0]
.a:     cmp     cx, [clip_x1]
        jle     .b
        mov     cx, [clip_x1]
.b:     sub     cx, ax
        jle     .nx
        mov     [g_x], ax
.sch:   mov     [g_w], cx
        cmp     cx, MAXW
        jle     .slast
        mov     word [g_w], MAXW
        push    cx
        call    scan_span
        pop     cx
        sub     cx, MAXW
        add     word [g_x], MAXW
        jmp     .sch
.slast: call    scan_span
.nx:    dec     word [sc_cnt]
        jnz     .seg
        call    blt_unexclude
.r:     ret

; scan_span: draw one span g_x..g_x+g_w on row g_y using prow and roptab
scan_span:
        mov     al, [g_rop]
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .gen
        cmp     byte [g_transp], 0
        jne     .gen
        cmp     al, 0xF0
        jne     .gen
        cmp     byte [g_psolid], 0
        je      .gen
        mov     eax, [g_pval]
        mov     [fill_val], eax
        mov     bx, dst
        mov     ax, [g_y]
        mov     cx, [g_x]
        mov     dx, [g_w]
        call    fill_row_val
        ret
.gen:   mov     ax, [g_y]
        call    fill_pb
        mov     bx, dst
        mov     cx, [g_x]
        mov     dx, [g_w]
        test    byte [g_ropf], ROPF_D
        jz      .nod
        mov     di, DBUF
        call    read_row
.nod:   cmp     byte [g_transp], 0
        je      .ev
        ; keep a copy of the destination
        push    cx
        push    si
        push    di
        push    es
        push    ds
        pop     es
        mov     si, DBUF
        mov     di, SBUF
        mov     cx, dx
        shl     cx, ESHIFT
        rep     movsb
        pop     es
        pop     di
        pop     si
        pop     cx
.ev:    push    ax
        push    bx
        push    cx
        mov     si, PBUF
        mov     bx, SBUF
        mov     di, DBUF
        mov     cx, dx
        call    rop_eval
        pop     cx
        pop     bx
        pop     ax
        cmp     byte [g_transp], 0
        je      .w
        ; restore pixels where the hatch is background
        push    ax
        push    bx
        push    cx
        push    dx
        and     ax, 7
        shl     ax, 3
        mov     bx, ax                  ; pmask row base
        mov     cx, [g_x]
        xor     di, di
.tl:    push    bx
        mov     ax, cx
        and     ax, 7
        add     bx, ax
        cmp     byte [pmask+bx], 0
        pop     bx
        jne     .tk
        mov     EA, [SBUF+di]
        mov     [DBUF+di], EA
.tk:    inc     cx
        add     di, ELEM
        dec     dx
        jnz     .tl
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.w:     mov     si, DBUF
        call    write_row
        ret

; ---------------------------------------------------------------------------
; Polylines
; ---------------------------------------------------------------------------
do_polyline:
        les     si, [bp+op_lpPen]
        mov     ax, es
        or      ax, si
        jz      .r
        mov     ax, [es:si+PEN_STYLE]
        cmp     ax, 5
        je      .r
        mov     [ln_style], ax
        call    pen_value
        mov     [ln_fgval], eax
        mov     eax, [g_bk]
        cmp     byte [dst+SURF.kind], SK_MONO
        jne     .c
        movzx   eax, byte [g_bkm]
.c:     mov     [ln_bkval], eax
        mov     ax, [g_rop2]
        call    rop2_to_rop3
        mov     [ln_rop3], al
%if BITROP
        call    build_rop_table
%else
        mov     dl, [ln_fgval]
        call    make_pen_table          ; pentab = f(pen, D)
        ; copy to fgtab, build bktab for styled gaps
        push    es
        push    ds
        pop     es
        mov     si, pentab
        mov     di, fgtab
        mov     cx, NCOLORS
        rep     movsb
        pop     es
        mov     al, [ln_rop3]
        mov     dl, [ln_bkval]
        call    make_pen_table
        push    es
        push    ds
        pop     es
        mov     si, pentab
        mov     di, bktab
        mov     cx, NCOLORS
        rep     movsb
        pop     es
%endif
        ; style pattern
        mov     bx, [ln_style]
        shl     bx, 2
        mov     eax, [cs:stylemasks+bx]
        mov     [ln_mask], eax
        mov     dword [ln_bit], 0
        ; exclusion
        mov     byte [g_excl], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .ne
        call    excl_all
        mov     byte [g_excl], 1
.ne:    mov     cx, [bp+op_count]
        dec     cx
        jle     .done
        mov     [pl_cnt], cx
        mov     si, [bp+op_lpPoints]
        mov     [pl_ptr], si
.seg:   les     si, [bp+op_lpPoints]
        mov     si, [pl_ptr]
        mov     ax, [es:si]
        mov     [ln_x0], ax
        mov     ax, [es:si+2]
        mov     [ln_y0], ax
        mov     ax, [es:si+4]
        mov     [ln_x1], ax
        mov     ax, [es:si+6]
        mov     [ln_y1], ax
        add     word [pl_ptr], 4
        call    draw_line
        dec     word [pl_cnt]
        jnz     .seg
.done:  call    blt_unexclude
.r:     ret

; draw_line: ln_x0,ln_y0 -> ln_x1,ln_y1, last point excluded
draw_line:
        mov     ax, [ln_x1]
        sub     ax, [ln_x0]
        mov     word [ln_sx], 1
        jge     .1
        neg     ax
        mov     word [ln_sx], -1
.1:     mov     [ln_dx], ax
        mov     ax, [ln_y1]
        sub     ax, [ln_y0]
        mov     word [ln_sy], 1
        jge     .2
        neg     ax
        mov     word [ln_sy], -1
.2:     mov     [ln_dy], ax
        mov     cx, [ln_x0]
        mov     ax, [ln_y0]
        mov     bx, [ln_dx]
        cmp     bx, [ln_dy]
        jl      .ymaj
        ; x major: steps = dx
        mov     si, bx                  ; steps
        or      si, si
        jz      .r
        mov     dx, bx
        neg     dx
        sar     dx, 1                   ; err = -dx/2
.xl:    call    plot
        add     cx, [ln_sx]
        add     dx, [ln_dy]
        jl      .xn
        add     ax, [ln_sy]
        sub     dx, [ln_dx]
.xn:    dec     si
        jnz     .xl
        ret
.ymaj:  mov     si, [ln_dy]
        or      si, si
        jz      .r
        mov     dx, si
        neg     dx
        sar     dx, 1
.yl:    call    plot
        add     ax, [ln_sy]
        add     dx, [ln_dx]
        jl      .yn
        add     cx, [ln_sx]
        sub     dx, [ln_dy]
.yn:    dec     si
        jnz     .yl
.r:     ret

; plot: cx = x, ax = y.  Applies style mask, clip, pen table.
plot:
        push    bx
        push    edx
        ; style
%if BITROP
        mov     bx, ln_fgval
%else
        mov     bx, fgtab
%endif
        mov     edx, [ln_mask]
        push    cx
        mov     cl, [ln_bit]
        bt      edx, ecx
        pop     cx
        jc      .on
%if BITROP
        mov     bx, ln_bkval
%else
        mov     bx, bktab
%endif
        cmp     word [g_bkmode], OPAQUE
        jne     .skip
.on:    cmp     cx, [clip_x0]
        jl      .skip
        cmp     cx, [clip_x1]
        jge     .skip
        cmp     ax, [clip_y0]
        jl      .skip
        cmp     ax, [clip_y1]
        jge     .skip
        push    ax
        push    bx
        mov     bx, dst
        call    get_pixel
        pop     bx
%if BITROP
        mov     edx, eax                ; D
        mov     eax, [bx]               ; pen / gap colour
        call    rop_px
        mov     edx, eax
%else
        and     al, CMASK
        xlatb
        mov     dl, al
%endif
        pop     ax
        push    bx
        mov     bx, dst
        call    put_pixel
        pop     bx
.skip:  inc     byte [ln_bit]
        cmp     byte [ln_bit], 24
        jb      .r
        mov     byte [ln_bit], 0
.r:     pop     edx
        pop     bx
        ret

; pen_value: es:si -> physical pen -> eax = its value for the destination
; (mono bit, or the pixel, palette-translated on the screen)
pen_value:
        mov     eax, [es:si+PEN_COLOR]
; phys_value: eax = physical colour -> eax = value for the destination
phys_value:
        cmp     byte [dst+SURF.kind], SK_MONO
        jne     .c
        shr     eax, MONOB*8
        and     eax, 1
        ret
.c:     and     eax, PIXMASK
%if PALMGR
        cmp     byte [g_xlat], 0
        je      .r
        push    bx
        movzx   bx, al
        mov     al, [pal_xlat+bx]
        pop     bx
.r:
%endif
        ret

; style masks, 24-pixel cycle (bit n = pixel n drawn with pen)
stylemasks:
        dd      0x00FFFFFF              ; PS_SOLID
        dd      0x0003FFFF              ; PS_DASH        18 on, 6 off
        dd      0x00E38E38              ; PS_DOT         3 on, 3 off
        dd      0x001C01FF              ; PS_DASHDOT     9 on, 6 off, 3 on, 6 off
        dd      0x0011C71FF & 0xFFFFFF  ; PS_DASHDOTDOT  9 on,3 off,3 on,3 off,3 on,3 off
