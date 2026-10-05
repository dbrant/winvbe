; ---------------------------------------------------------------------------
; Colors, ColorInfo, RealizeObject
; ---------------------------------------------------------------------------
BRF_SOLID       equ 2

; rgb_to_phys: al=R ah=G dl=B  ->  bl = color index, bh = mono value
; preserves ax, cx, dx, si, di
rgb_to_phys:
        push    cx
        push    si
%if NPLANES = 3
        xor     bl, bl
        test    al, 0x80
        jz      .g
        or      bl, 1
.g:     test    ah, 0x80
        jz      .b
        or      bl, 2
.b:     test    dl, 0x80
        jz      .m
        or      bl, 4
.m:
%else
        call    nearest16
%endif
        movzx   cx, al
        movzx   si, ah
        add     cx, si
        movzx   si, dl
        add     cx, si
        xor     bh, bh
        cmp     cx, 382
        jb      .r
        inc     bh
.r:     pop     si
        pop     cx
        ret

%if NPLANES = 4
; nearest16: al=R ah=G dl=B -> bl = index of nearest palette color
nearest16:
        push    ecx
        push    esi
        push    edi
        movzx   ecx, al
        movzx   esi, ah
        movzx   edi, dl
        call    nearest16x
        pop     edi
        pop     esi
        pop     ecx
        ret

; nearest16x: ecx=R esi=G edi=B (signed 32-bit) -> bl.  Weighted distance 3:4:2.
nearest16x:
        push    eax
        push    edx
        push    ebp
        mov     ebp, 0x7FFFFFFF         ; best distance
        xor     bx, bx                  ; best index in bl, counter in bh
.l:     push    bx
        movzx   bx, bh
        imul    bx, bx, 3
        movzx   eax, byte [cs:rgbtab+bx]
        sub     eax, ecx
        imul    eax, eax
        imul    eax, eax, 3
        movzx   edx, byte [cs:rgbtab+bx+1]
        sub     edx, esi
        imul    edx, edx
        shl     edx, 2
        add     eax, edx
        movzx   edx, byte [cs:rgbtab+bx+2]
        sub     edx, edi
        imul    edx, edx
        shl     edx, 1
        add     eax, edx
        pop     bx
        cmp     eax, ebp
        jae     .n
        mov     ebp, eax
        mov     bl, bh
.n:     inc     bh
        cmp     bh, 16
        jb      .l
        pop     ebp
        pop     edx
        pop     eax
        ret
%endif

%if NPLANES = 4
; dither16: al=R ah=G dl=B -> d16_plan[64] = palette indices sorted by luminance
; (Knoll pattern dithering: error-accumulating nearest-color picks)
dither16:
        pushad
        movzx   ecx, al
        mov     [d16_t], ecx
        movzx   ecx, ah
        mov     [d16_t+4], ecx
        movzx   ecx, dl
        mov     [d16_t+8], ecx
        xor     eax, eax
        mov     [d16_e], eax
        mov     [d16_e+4], eax
        mov     [d16_e+8], eax
        xor     di, di                  ; plan index
.pick:  ; attempt = T + err*3/4
        mov     ecx, [d16_e]
        imul    ecx, ecx, 3
        sar     ecx, 2
        add     ecx, [d16_t]
        mov     esi, [d16_e+4]
        imul    esi, esi, 3
        sar     esi, 2
        add     esi, [d16_t+4]
        push    di
        mov     edi, [d16_e+8]
        imul    edi, edi, 3
        sar     edi, 2
        add     edi, [d16_t+8]
        call    nearest16x              ; bl = index
        pop     di
        mov     [d16_plan+di], bl
        ; err += T - pal[c]
        movzx   bx, bl
        imul    bx, bx, 3
        xor     si, si
.er:    movzx   eax, byte [cs:rgbtab+bx]
        inc     bx
        neg     eax
        add     eax, [d16_t+si]
        add     [d16_e+si], eax
        add     si, 4
        cmp     si, 12
        jb      .er
        inc     di
        cmp     di, 64
        jb      .pick
        ; insertion sort by luminance
        mov     si, 1
.s1:    cmp     si, 64
        jae     .done
        mov     al, [d16_plan+si]
        call    .lum
        mov     ecx, edx                ; key luminance
        mov     bl, al                  ; key
        mov     di, si
.s2:    or      di, di
        jz      .s3
        mov     al, [d16_plan+di-1]
        call    .lum
        cmp     edx, ecx
        jbe     .s3
        mov     [d16_plan+di], al
        dec     di
        jmp     .s2
.s3:    mov     [d16_plan+di], bl
        inc     si
        jmp     .s1
.done:  popad
        ret
; .lum: al = index -> edx = luminance (preserves eax, ebx, ecx, si, di)
.lum:   push    ebx
        push    eax
        movzx   bx, al
        imul    bx, bx, 3
        movzx   edx, byte [cs:rgbtab+bx]
        imul    edx, edx, 299
        movzx   eax, byte [cs:rgbtab+bx+1]
        imul    eax, eax, 587
        add     edx, eax
        movzx   eax, byte [cs:rgbtab+bx+2]
        imul    eax, eax, 114
        add     edx, eax
        pop     eax
        pop     ebx
        ret
%endif

; rgb of each color index (8-bit components)
rgbtab:
%if NPLANES = 3
        db        0,  0,  0,  255,  0,  0,    0,255,  0,  255,255,  0
        db        0,  0,255,  255,  0,255,    0,255,255,  255,255,255
%else                                   ; Windows VGA order: bit 0 red, 1 green, 2 blue, 3 bright
        db        0,  0,  0,  128,  0,  0,    0,128,  0,  128,128,  0
        db        0,  0,128,  128,  0,128,    0,128,128,  192,192,192
        db      128,128,128,  255,  0,  0,    0,255,  0,  255,255,  0
        db        0,  0,255,  255,  0,255,    0,255,255,  255,255,255
%endif

; is_mono_dev: es:si -> BITMAP/PDEVICE.  ZF=1 if mono memory bitmap.
is_mono_dev:
        cmp     word [es:si+bmType], 0
        jne     .no
        cmp     word [es:si+bmPlanes], 0x0101
        ret
.no:    or      si, si                  ; ZF=0 (si is never 0... force NZ)
        push    ax
        mov     al, 1
        or      al, al
        pop     ax
        ret

; phys_to_rgb: bl = index, bh = mono, es:si = device -> dx:ax = RGB
phys_to_rgb:
        call    is_mono_dev
        jne     .color
        xor     ax, ax
        xor     dx, dx
        or      bh, bh
        jz      .r
        mov     ax, 0xFFFF
        mov     dx, 0x00FF
.r:     ret
.color: push    bx
        and     bx, CMASK
        imul    bx, bx, 3
        mov     ax, [cs:rgbtab+bx]
        movzx   dx, byte [cs:rgbtab+bx+2]
        pop     bx
        ret

; ---------------------------------------------------------------------------
; ColorInfo(lpDestDev, dwColorIn, lpPhysBits)
; ---------------------------------------------------------------------------
ColorInfo:
        PROLOG
        les     di, [bp+6]
        mov     ax, es
        or      ax, di
        jz      .fromphys
        mov     ax, [bp+10]
        mov     dl, [bp+12]
        call    rgb_to_phys
        mov     [es:di], bl
        mov     [es:di+1], bh
        mov     word [es:di+2], 0
        jmp     .ret
.fromphys:
        mov     bx, [bp+10]
.ret:   les     si, [bp+14]
        call    phys_to_rgb
        EPILOG  12

; ---------------------------------------------------------------------------
; RealizeObject(lpDestDev, Style, lpInObj, lpOutObj, lpTextXForm)
; ---------------------------------------------------------------------------
ro_lpDestDev    equ 20
ro_Style        equ 18
ro_lpIn         equ 14
ro_lpOut        equ 10
ro_lpXForm      equ 6

RealizeObject:
        PROLOG
        mov     bx, [bp+ro_Style]
        mov     ax, 1
        or      bx, bx
        js      .done                   ; deleting an object: nothing to do
        xor     ax, ax
        cmp     bx, 2
        ja      .done                   ; fonts: no device fonts
        les     di, [bp+ro_lpOut]
        mov     cx, es
        or      cx, di
        jz      .size
        cmp     bx, 1
        je      .pen
        call    realize_brush
        jmp     .size
.pen:   call    realize_pen
.size:  mov     ax, PEN_SIZE
        cmp     word [bp+ro_Style], 1
        je      .done
        mov     ax, BR_SIZE
.done:  EPILOG  18

; es:di -> output pen
realize_pen:
        push    ds
        lds     si, [bp+ro_lpIn]
        mov     cx, [si]                ; style
        mov     ax, [si+6]
        mov     dl, [si+8]
        call    rgb_to_phys
        mov     [es:di+PEN_COLOR], bl
        mov     [es:di+PEN_COLOR+1], bh
        mov     word [es:di+PEN_COLOR+2], 0
        cmp     cx, 5
        je      .st
        jb      .w
        xor     cx, cx
.w:     cmp     word [si+2], 1
        jbe     .st
        xor     cx, cx                  ; wide pens are drawn solid by GDI
.st:    mov     [es:di+PEN_STYLE], cx
        pop     ds
        ret

; es:di -> output brush
realize_brush:
        push    ds
        lds     si, [bp+ro_lpIn]
        mov     cx, [si]                ; lbStyle
        mov     byte [es:di+BR_FLAGS], 0
        cmp     cx, 1
        je      .hollow
        cmp     cx, 2
        je      .hatch
        cmp     cx, 3
        je      .pattern
        ; ---- solid (dithered) brush
        mov     byte [es:di+BR_STYLE], 0
        mov     ax, [si+2]
        mov     dl, [si+4]
        pop     ds
        call    dither_brush
        jmp     .rotate
.hollow:
        mov     byte [es:di+BR_STYLE], 1
        pop     ds
        ret
.hatch:
        mov     byte [es:di+BR_STYLE], 2
        mov     byte [es:di+BR_FLAGS], BRF_HATCH
        mov     ax, [si+2]
        mov     dl, [si+4]
        call    rgb_to_phys
        mov     [es:di+BR_FG], bl
        mov     [es:di+BR_FGMONO], bh
        mov     bx, [si+6]              ; hatch style
        pop     ds
        cmp     bx, 5
        jbe     .hok
        xor     bx, bx
.hok:   shl     bx, 3
        lea     si, [hatchtab+bx]
        xor     dx, dx                  ; dx = row
.hrow:  mov     al, [cs:si]
        mov     bx, dx
        mov     [es:di+BR_MONO+bx], al
        shl     bx, 3
        mov     cx, 8
.hpix:  mov     ah, 0xFF                ; background placeholder
        shl     al, 1
        jnc     .hbg
        mov     ah, [es:di+BR_FG]
.hbg:   mov     [es:di+BR_COLOR+bx], ah
        inc     bx
        loop    .hpix
        inc     si
        inc     dx
        cmp     dx, 8
        jb      .hrow
        jmp     .rotate
.pattern:
        mov     byte [es:di+BR_STYLE], 3
        lds     si, [si+2]              ; lbColor is a far pointer to the BITMAP
        mov     dx, [si+bmWidthBytes]
        mov     cx, [si+bmWidthPlanes]
        mov     al, [si+bmPlanes]
        push    ds
        mov     ds, [cs:dataseg]
        mov     [pat_planes], al
        pop     ds
        lds     si, [si+bmBits]
        push    di
        push    cx
        add     di, BR_COLOR
        mov     cx, 32
        xor     ax, ax
        rep     stosw
        pop     cx
        pop     di
        xor     bx, bx
.prow:  call    pattern_row
        add     si, dx
        inc     bx
        cmp     bx, 8
        jb      .prow
        pop     ds
        jmp     .rotate

.rotate:
        call    rotate_brush
        call    check_solid
        ret

; pattern_row: ds:si -> plane 0 byte of the row, cx = plane stride,
; bx = row number, es:di -> brush.  Uses [pat_planes] (in our DGROUP).
pattern_row:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        mov     dx, bx
        shl     dx, 3                   ; dx = row*8
        push    ds
        mov     ds, [cs:dataseg]
        mov     al, [pat_planes]
        pop     ds
        cmp     al, 1
        jne     .color
        ; mono pattern: 1 = white, 0 = black
        mov     al, [si]
        mov     [es:di+BR_MONO+bx], al
        mov     bx, dx
        mov     ah, 8
.m:     shl     al, 1
        sbb     cl, cl
        and     cl, CMASK
        mov     [es:di+BR_COLOR+bx], cl
        inc     bx
        dec     ah
        jnz     .m
        jmp     .r
.color: ; color pattern: combine the bitmap's planes
        push    bp
        push    ax                      ; al = number of planes
        mov     bp, 1                   ; plane bit
        mov     ah, al
.pl:    mov     al, [si]
        mov     bx, dx
        push    ax
        mov     ah, 8
.px:    shl     al, 1
        jnc     .z
        push    ax
        mov     ax, bp
        or      [es:di+BR_COLOR+bx], al
        pop     ax
.z:     inc     bx
        dec     ah
        jnz     .px
        pop     ax
        add     si, cx
        shl     bp, 1
        dec     ah
        jnz     .pl
        pop     ax
%if NPLANES = 4
        cmp     al, 3                   ; 8-color pattern: full-intensity colors
        jne     .c16
        mov     bx, dx
        mov     ah, 8
.c8:    push    bx
        movzx   bp, byte [es:di+BR_COLOR+bx]
        mov     al, [cs:c8to16+bp]
        pop     bx
        mov     [es:di+BR_COLOR+bx], al
        inc     bx
        dec     ah
        jnz     .c8
.c16:
%endif
        pop     bp
        ; mono version: pixel == white -> 1 (approximate with color index CMASK)
        mov     bx, dx
        xor     al, al
        mov     ah, 8
.mm:    shl     al, 1
        cmp     byte [es:di+BR_COLOR+bx], CMASK
        jne     .mz
        or      al, 1
.mz:    inc     bx
        dec     ah
        jnz     .mm
        mov     bx, dx
        shr     bx, 3
        mov     [es:di+BR_MONO+bx], al
.r:     pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; dither_brush: al=R ah=G dl=B, es:di -> brush.  DS = DGROUP.
dither_brush:
        push    ax
        push    dx
        ; levels 0..64
        movzx   cx, al
        call    level
        mov     [lvl_r], cl
        movzx   cx, ah
        call    level
        mov     [lvl_g], cl
        movzx   cx, dl
        call    level
        mov     [lvl_b], cl
        ; luminance = (R*77 + G*151 + B*28) >> 8
        movzx   cx, al
        imul    cx, cx, 77
        movzx   si, ah
        imul    si, si, 151
        add     cx, si
        movzx   si, dl
        imul    si, si, 28
        add     cx, si
        shr     cx, 8
        call    level
        mov     [lvl_l], cl
%if NPLANES = 4
        pop     dx
        pop     ax
        push    ax
        push    dx
        call    dither16                ; -> d16_plan
%endif
        xor     bx, bx
.l:     mov     al, [cs:bayer+bx]
%if NPLANES = 3
        xor     ah, ah
        cmp     [lvl_r], al
        jbe     .1
        or      ah, 1
.1:     cmp     [lvl_g], al
        jbe     .2
        or      ah, 2
.2:     cmp     [lvl_b], al
        jbe     .3
        or      ah, 4
.3:
%else
        push    bx
        movzx   bx, al
        mov     ah, [d16_plan+bx]
        pop     bx
%endif
        mov     [es:di+BR_COLOR+bx], ah
        ; mono
        shl     dh, 1
        cmp     [lvl_l], al
        jbe     .4
        or      dh, 1
.4:     mov     si, bx
        and     si, 7
        cmp     si, 7
        jne     .5
        mov     si, bx
        shr     si, 3
        push    di
        add     di, si
        mov     [es:di+BR_MONO], dh
        pop     di
.5:     inc     bx
        cmp     bx, 64
        jb      .l
        pop     dx
        pop     ax
        ret

level:                                  ; cx = 0..255 -> cl = (cx*65)>>8
        imul    cx, cx, 65
        shr     cx, 8
        ret

; rotate_brush: rotate pattern by brush origin.  es:di -> brush
rotate_brush:
        mov     cx, [bp+ro_lpXForm]     ; x origin
        mov     dx, [bp+ro_lpXForm+2]   ; y origin
        and     cx, 7
        and     dx, 7
        mov     ax, cx
        or      ax, dx
        jz      .r
        ; copy color pattern to tmp_pat
        push    ds
        push    es
        pop     ds
        lea     si, [di+BR_COLOR]
        push    es
        mov     es, [cs:dataseg]
        push    di
        mov     di, tmp_pat
        push    cx
        mov     cx, 72
        rep     movsb                   ; color + mono
        pop     cx
        pop     di
        pop     es
        pop     ds
        ; new[r][c] = old[(r-dy)&7][(c-dx)&7]
        xor     bx, bx                  ; r
.row:   mov     si, bx
        sub     si, dx
        and     si, 7                   ; source row
        ; mono row
        mov     al, [tmp_pat+64+si]
        ror     al, cl
        mov     [es:di+BR_MONO+bx], al
        shl     si, 3
        push    bx
        shl     bx, 3
        xor     ax, ax                  ; c
.col:   push    si
        push    ax
        sub     al, cl
        and     ax, 7
        add     si, ax
        mov     al, [tmp_pat+si]
        mov     [es:di+BR_COLOR+bx], al
        pop     ax
        pop     si
        inc     bx
        inc     ax
        cmp     ax, 8
        jb      .col
        pop     bx
        inc     bx
        cmp     bx, 8
        jb      .row
.r:     ret

; check_solid: set BRF_SOLID / BR_FG if all color pixels are equal (not hatched)
check_solid:
        test    byte [es:di+BR_FLAGS], BRF_HATCH
        jnz     .no
        mov     al, [es:di+BR_COLOR]
        xor     bx, bx
.l:     cmp     [es:di+BR_COLOR+bx], al
        jne     .no
        inc     bx
        cmp     bx, 64
        jb      .l
        mov     al, [es:di+BR_MONO]
        xor     bx, bx
.m:     cmp     [es:di+BR_MONO+bx], al
        jne     .no
        inc     bx
        cmp     bx, 8
        jb      .m
        or      byte [es:di+BR_FLAGS], BRF_SOLID
        mov     al, [es:di+BR_COLOR]
        mov     [es:di+BR_FG], al
        mov     al, [es:di+BR_MONO]
        and     al, 1
        mov     [es:di+BR_FGMONO], al
.no:    ret

hatchtab:
        db      0x00,0x00,0x00,0x00,0xFF,0x00,0x00,0x00        ; HS_HORIZONTAL
        db      0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08        ; HS_VERTICAL
        db      0x80,0x40,0x20,0x10,0x08,0x04,0x02,0x01        ; HS_FDIAGONAL
        db      0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80        ; HS_BDIAGONAL
        db      0x08,0x08,0x08,0x08,0xFF,0x08,0x08,0x08        ; HS_CROSS
        db      0x81,0x42,0x24,0x18,0x18,0x24,0x42,0x81        ; HS_DIAGCROSS

bayer:
        db       0, 32,  8, 40,  2, 34, 10, 42
        db      48, 16, 56, 24, 50, 18, 58, 26
        db      12, 44,  4, 36, 14, 46,  6, 38
        db      60, 28, 52, 20, 62, 30, 54, 22
        db       3, 35, 11, 43,  1, 33,  9, 41
        db      51, 19, 59, 27, 49, 17, 57, 25
        db      15, 47,  7, 39, 13, 45,  5, 37
        db      63, 31, 55, 23, 61, 29, 53, 21
