; ---------------------------------------------------------------------------
; StretchBlt (HiColor / TrueColor builds)
;
; Without it GDI simulates stretching through 24 bpp DIBs, which Windows 3.0
; gets wrong (its rows come out skewed).  The row engine of BitBlt does the
; work: with g_stretch set, blt_rows1 takes each source row from stretch_row,
; which picks the source pixel nearest to the centre of every destination
; pixel (COLORONCOLOR).
; ---------------------------------------------------------------------------

; StretchBlt(lpDestDev, DestX, DestY, DestXext, DestYext, lpSrcDev, SrcX, SrcY,
;            SrcXext, SrcYext, Rop3, lpPBrush, lpDrawMode, lpClipRect)
sb_lpDst        equ 42
sb_dx           equ 40
sb_dy           equ 38
sb_dw           equ 36
sb_dh           equ 34
sb_lpSrc        equ 30
sb_sx           equ 28
sb_sy           equ 26
sb_sw           equ 24
sb_sh           equ 22
sb_rop          equ 18
sb_lpBrush      equ 14
sb_lpDM         equ 10
sb_lpClip       equ 6

StretchBlt:
        PROLOG
        mov     al, [bp+sb_rop+2]
        mov     [g_rop], al
        call    rop_flags
        mov     [g_ropf], ah
        les     si, [bp+sb_lpDst]
        mov     bx, dst
        call    load_surf
        ; normalise the rectangles to positive extents; a negative extent
        ; mirrors (as in Wine: x += ext, ext = -ext)
        xor     dx, dx                  ; dl: mirror x, dh: mirror y
        mov     ax, [bp+sb_dx]
        mov     cx, [bp+sb_dw]
        call    .norm
        mov     [st_dx0], ax
        mov     [st_dw], cx
        xchg    dl, dh
        mov     ax, [bp+sb_dy]
        mov     cx, [bp+sb_dh]
        call    .norm
        mov     [st_dy0], ax
        mov     [st_dh], cx
        xchg    dl, dh
        cmp     word [st_dw], 0
        je      .ok
        cmp     word [st_dh], 0
        je      .ok
        mov     byte [g_conv], 0
        test    byte [g_ropf], ROPF_S
        jz      .nosrc
        les     si, [bp+sb_lpSrc]
        mov     ax, es
        or      ax, si
        jz      .fail
        push    dx
        mov     bx, src
        call    load_surf
        pop     dx
        mov     ax, [bp+sb_sx]
        mov     cx, [bp+sb_sw]
        call    .norm
        mov     [st_sx0], ax
        mov     [st_sw], cx
        xchg    dl, dh
        mov     ax, [bp+sb_sy]
        mov     cx, [bp+sb_sh]
        call    .norm
        mov     [st_sy0], ax
        mov     [st_sh], cx
        xchg    dl, dh
        cmp     word [st_sw], 0
        je      .ok
        cmp     word [st_sh], 0
        je      .ok
        mov     al, [src+SURF.kind]     ; mono <-> colour conversion
        mov     ah, [dst+SURF.kind]
        cmp     al, SK_MONO
        jne     .s1
        cmp     ah, SK_MONO
        je      .nosrc
        mov     byte [g_conv], 1
        jmp     .nosrc
.s1:    cmp     ah, SK_MONO
        jne     .nosrc
        mov     byte [g_conv], 2
.nosrc: mov     [st_mx], dl
        mov     [st_my], dh
        ; the destination rectangle, clipped
        les     si, [bp+sb_lpClip]
        call    set_clip
        mov     ax, [st_dx0]
        mov     bx, [st_dy0]
        mov     cx, ax
        add     cx, [st_dw]
        mov     dx, bx
        add     dx, [st_dh]
        call    clip_rect
        jc      .ok
        les     si, [bp+sb_lpDM]
        call    get_dm_colors
        test    byte [g_ropf], ROPF_P
        jz      .nopat
        les     si, [bp+sb_lpBrush]
        mov     ax, es
        or      ax, si
        jz      .ok
        call    build_prow
        jc      .ok
.nopat: mov     byte [g_excl], 0        ; exclusion: the whole screen
        cmp     byte [dst+SURF.kind], SK_SCREEN
        je      .ex
        test    byte [g_ropf], ROPF_S
        jz      .nex
        cmp     byte [src+SURF.kind], SK_SCREEN
        jne     .nex
.ex:    call    excl_all
        mov     byte [g_excl], 1
.nex:   test    byte [g_ropf], ROPF_S
        jz      .go
        mov     byte [g_stretch], 1
.go:    call    blt_rows
        mov     byte [g_stretch], 0
        call    blt_unexclude
.ok:    mov     ax, 1
        EPILOG  40
.fail:  xor     ax, ax
        EPILOG  40
; .norm: ax = origin, cx = extent -> normalised, dl ^= 1 if it was negative
.norm:  or      cx, cx
        jns     .nr
        add     ax, cx
        neg     cx
        xor     dl, 1
.nr:    ret

; st_map: eax = destination offset (0 .. dext-1), ebx = dext, ecx = sext,
; dl = mirror  ->  eax = source offset: the pixel under the centre of the
; destination pixel
st_map:
        push    edx
        push    esi
        movzx   esi, dl
        lea     eax, [eax*2+1]
        mul     ecx
        shl     ebx, 1
        div     ebx
        shr     ebx, 1
        or      si, si
        jz      .r
        neg     eax                     ; mirrored: sext-1 - offset
        lea     eax, [eax+ecx-1]
.r:     pop     esi
        pop     edx
        ret

; stretch_row: ax = row of the clipped destination rectangle -> SBUF holds the
; source pixels for destination columns g_x .. g_x+g_w-1
stretch_row:
        pushad
        push    es
        ; source row
        add     ax, [g_y]
        sub     ax, [st_dy0]
        movzx   eax, ax
        movzx   ebx, word [st_dh]
        movzx   ecx, word [st_sh]
        mov     dl, [st_my]
        call    st_map
        add     ax, [st_sy0]
        call    .clampy
        mov     [st_row], ax
        mov     word [st_wn], 0         ; no source pixels loaded yet
        push    ds
        pop     es
        mov     di, SBUF
        mov     si, [g_x]               ; destination x
        mov     bp, [g_w]
.px:    mov     ax, si
        sub     ax, [st_dx0]
        movzx   eax, ax
        movzx   ebx, word [st_dw]
        movzx   ecx, word [st_sw]
        mov     dl, [st_mx]
        call    st_map
        add     ax, [st_sx0]
        ; clamp to the source
        or      ax, ax
        jns     .c1
        xor     ax, ax
.c1:    cmp     ax, [src+SURF.width]
        jb      .c2
        mov     ax, [src+SURF.width]
        dec     ax
.c2:    ; in the loaded window?
        mov     bx, ax
        sub     bx, [st_wx]
        jb      .load
        cmp     bx, [st_wn]
        jb      .have
.load:  call    .window                 ; ax = source x
        mov     bx, ax
        sub     bx, [st_wx]
.have:  shl     bx, ESHIFT
        mov     EA, [XBUF+bx]
        STOSE
        inc     si
        dec     bp
        jnz     .px
        pop     es
        popad
        ret
; .window: load source pixels around x = ax into XBUF.  Preserves ax.
.window:
        pushad
        push    es
        mov     cx, ax                  ; window start: x, or x-MAXW+1 when
        cmp     byte [st_mx], 0         ; mirrored (columns run right to left)
        je      .w1
        sub     cx, MAXW-1
        jns     .w1
        xor     cx, cx
.w1:    mov     dx, [src+SURF.width]
        sub     dx, cx
        cmp     dx, MAXW
        jbe     .w2
        mov     dx, MAXW
.w2:    mov     [st_wx], cx
        mov     [st_wn], dx
        mov     ax, [st_row]
        mov     bx, src
        mov     di, XBUF
        call    read_row
        pop     es
        popad
        ret
.clampy:
        or      ax, ax
        jns     .y1
        xor     ax, ax
.y1:    cmp     ax, [src+SURF.height]
        jb      .y2
        mov     ax, [src+SURF.height]
        dec     ax
.y2:    ret
