; ---------------------------------------------------------------------------
; Colours, ColorInfo, RealizeObject
;
; Physical colours are dwords: the pixel (element) value in the low bytes and
; the mono value (0/1) in byte MONOB.  16 colours: index | mono<<8.
; 256 colours: palette index | mono<<8 | 0xFF000000.  HiColor: 16-bit pixel
; | mono<<16.  TrueColor: 0x00RRGGBB | mono<<24.
; ---------------------------------------------------------------------------
BRF_SOLID       equ 2

; cref_to_phys: eax = COLORREF -> ebx = physical colour.
; 256 colours: a palette index (high byte 0xFF, or 0x01 as GDI sometimes
; passes PALETTEINDEX) is used as it is.
cref_to_phys:
%if BPP = 8
        push    eax
        shr     eax, 24
        cmp     al, 0xFF
        je      .idx
        cmp     al, 0x01
        je      .idx
        pop     eax
%endif
        push    ax
        push    dx
        push    eax
        shr     eax, 16
        mov     dl, al
        pop     eax
        call    rgb_to_phys
        pop     dx
        pop     ax
        ret
%if BPP = 8
.idx:   pop     eax
        movzx   ebx, al
        call    phys_mono               ; mono value from the palette colour
        ret
%endif

; rgb_to_phys: al=R ah=G dl=B  ->  ebx = physical colour
; preserves eax, ecx, edx, esi, edi
rgb_to_phys:
        push    ecx
        push    si
        push    eax
%if BPP = 4
        call    nearest16               ; bl = index
        movzx   ebx, bl
%elif BPP = 8
        call    nearest16               ; bl = static colour number
        movzx   ebx, bl
        movzx   ebx, byte [cs:static_idx+bx]
        or      ebx, 0xFF000000
%elif BPP = 16
        movzx   ebx, al                 ; red
        shr     bx, 3
        movzx   ecx, ah                 ; green
        cmp     byte [pix_g6], 0
        je      .g5
        shl     bx, 6
        shr     cx, 2
        jmp     .gb
.g5:    shl     bx, 5
        shr     cx, 3
.gb:    or      bx, cx
        shl     bx, 5
        movzx   cx, dl                  ; blue
        shr     cx, 3
        or      bx, cx
%else
        movzx   ebx, al                 ; 0x00RRGGBB
        shl     ebx, 8
        mov     bl, ah
        shl     ebx, 8
        mov     bl, dl
%endif
        ; mono: white if R+G+B >= 382
        movzx   cx, al
        movzx   si, ah
        add     cx, si
        movzx   si, dl
        add     cx, si
        cmp     cx, 382
        jb      .r
        or      ebx, 1 << (MONOB*8)
.r:     pop     eax
        pop     si
        pop     ecx
        ret

%if BPP = 8
; phys_mono: ebx = physical colour (palette index in bl) -> mono bit set in
; ebx from the palette entry's brightness, 0xFF marker in the high byte
phys_mono:
        push    ax
        push    cx
        push    si
        movzx   si, bl
        shl     si, 2
        movzx   cx, byte [pal_rgb+si]
        movzx   ax, byte [pal_rgb+si+1]
        add     cx, ax
        movzx   ax, byte [pal_rgb+si+2]
        add     cx, ax
        and     ebx, 0xFF
        or      ebx, 0xFF000000
        cmp     cx, 382
        jb      .r
        or      ebx, 0x100
.r:     pop     si
        pop     cx
        pop     ax
        ret

; palette indices of the 20 static colours
static_idx:
        db      0, 1, 2, 3, 4, 5, 6, 7, 8, 9
        db      246, 247, 248, 249, 250, 251, 252, 253, 254, 255
%endif

%if BPP <= 8
; nearest16: al=R ah=G dl=B -> bl = number of the nearest colour in rgbtab
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
        mov     word [nt_tab], rgbtab
        mov     byte [nt_n], NCOLORS
%endif
; nearest_tabx: as nearest16x, over [nt_n] colours at cs:[nt_tab]
nearest_tabx:
        push    eax
        push    edx
        push    ebp
        mov     ebp, 0x7FFFFFFF         ; best distance
        xor     bx, bx                  ; best index in bl, counter in bh
.l:     push    bx
        movzx   bx, bh
        imul    bx, bx, 3
        add     bx, [nt_tab]
        movzx   eax, byte [cs:bx]
        sub     eax, ecx
        imul    eax, eax
        imul    eax, eax, 3
        movzx   edx, byte [cs:bx+1]
        sub     edx, esi
        imul    edx, edx
        shl     edx, 2
        add     eax, edx
        movzx   edx, byte [cs:bx+2]
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
        cmp     bh, [nt_n]
        jb      .l
        pop     ebp
        pop     edx
        pop     eax
        ret

; nearest_vga: al=R ah=G dl=B -> bl = nearest of the 16 VGA colours (vga16)
nearest_vga:
        push    ecx
        push    esi
        push    edi
        movzx   ecx, al
        movzx   esi, ah
        movzx   edi, dl
        mov     word [nt_tab], vga16
        mov     byte [nt_n], 16
        call    nearest_tabx
        pop     edi
        pop     esi
        pop     ecx
        ret

%if BPP <= 8

; dither16: al=R ah=G dl=B -> d16_plan[64] = colour numbers sorted by
; luminance (Knoll pattern dithering: error-accumulating nearest-colour picks)
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

; rgb of each colour number (8-bit components): the 16 VGA colours, or the
; 20 static colours of the 256-colour palette (also used for HiColor /
; TrueColor brushes)
rgbtab:
%if BPP = 4
vga16:
        db        0,  0,  0,  128,  0,  0,    0,128,  0,  128,128,  0
        db        0,  0,128,  128,  0,128,    0,128,128,  192,192,192
        db      128,128,128,  255,  0,  0,    0,255,  0,  255,255,  0
        db        0,  0,255,  255,  0,255,    0,255,255,  255,255,255
%else
        db        0,  0,  0,  128,  0,  0,    0,128,  0,  128,128,  0
        db        0,  0,128,  128,  0,128,    0,128,128,  192,192,192
        db      192,220,192,  164,200,240
        db      255,251,240,  160,160,164,  128,128,128,  255,  0,  0
        db        0,255,  0,  255,255,  0,    0,  0,255,  255,  0,255
        db        0,255,255,  255,255,255
vga16:                                  ; the 16 VGA colours (4 bpp DIBs)
        db        0,  0,  0,  128,  0,  0,    0,128,  0,  128,128,  0
        db        0,  0,128,  128,  0,128,    0,128,128,  192,192,192
        db      128,128,128,  255,  0,  0,    0,255,  0,  255,255,  0
        db        0,  0,255,  255,  0,255,    0,255,255,  255,255,255
%endif

; is_mono_dev: es:si -> BITMAP/PDEVICE.  ZF=1 if mono memory bitmap.
is_mono_dev:
        cmp     word [es:si+bmType], 0
        jne     .no
%if PACKED
        cmp     word [es:si+bmPlanes], 0x0101
%else
        cmp     byte [es:si+bmPlanes], 1
%endif
        ret
.no:    push    ax
        mov     al, 1
        or      al, al
        pop     ax
        ret

; phys_to_rgb: ebx = physical colour, es:si = device -> dx:ax = RGB
phys_to_rgb:
        call    is_mono_dev
        jne     .color
        xor     ax, ax
        xor     dx, dx
        test    ebx, 1 << (MONOB*8)
        jz      .r
        mov     ax, 0xFFFF
        mov     dx, 0x00FF
.r:     ret
.color:
        push    ebx
%if BPP = 4
        and     bx, CMASK
        imul    bx, bx, 3
        mov     ax, [cs:rgbtab+bx]
        movzx   dx, byte [cs:rgbtab+bx+2]
%elif BPP = 8
        movzx   bx, bl
        shl     bx, 2
        mov     ax, [pal_rgb+bx]
        movzx   dx, byte [pal_rgb+bx+2]
%elif BPP = 16
        call    pix16_rgb
%else
        mov     al, bl                  ; 0x00RRGGBB -> R in al, G ah, B dl
        mov     dl, al
        mov     ah, bh
        shr     ebx, 16
        mov     al, bl
        xor     dh, dh
%endif
        pop     ebx
        ret

%if BPP = 16
; pix16_rgb: bx = 16-bit pixel -> al=R ah=G dl=B, dh=0 (components widened
; by replicating their top bits)
pix16_rgb:
        push    cx
        mov     dl, bl                  ; blue: bits 0-4
        and     dl, 0x1F
        shl     dl, 3
        mov     cl, dl
        shr     cl, 5
        or      dl, cl
        xor     dh, dh
        mov     cx, bx
        cmp     byte [pix_g6], 0
        je      .g5
        shr     cx, 5                   ; green: 6 bits
        and     cl, 0x3F
        shl     cl, 2
        mov     ah, cl
        shr     cl, 6
        or      ah, cl
        mov     cx, bx
        shr     cx, 11                  ; red: bits 11-15
        jmp     .r
.g5:    shr     cx, 5                   ; green: 5 bits
        and     cl, 0x1F
        shl     cl, 3
        mov     ah, cl
        shr     cl, 5
        or      ah, cl
        mov     cx, bx
        shr     cx, 10                  ; red: bits 10-14
.r:     and     cl, 0x1F
        shl     cl, 3
        mov     al, cl
        shr     cl, 5
        or      al, cl
        pop     cx
        ret
%endif

; elem_mono: eax = pixel value -> al = mono value (0/1) by brightness
elem_mono:
        push    ebx
        push    dx
%if BPP = 4
        and     al, CMASK
%endif
        mov     ebx, eax
        call    phys_to_rgb.color       ; (needs no device)
        movzx   bx, al
        movzx   ax, ah
        add     bx, ax
        movzx   ax, dl
        add     bx, ax
        xor     eax, eax
        cmp     bx, 382
        jb      .r
        inc     ax
.r:     pop     dx
        pop     ebx
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
        mov     eax, [bp+10]
        call    cref_to_phys
        mov     [es:di], ebx
        jmp     .ret
.fromphys:
        mov     ebx, [bp+10]
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
        mov     eax, [si+6]
        call    cref_to_phys
        mov     [es:di+PEN_COLOR], ebx
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
        mov     eax, [si+2]
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
        mov     eax, [si+2]
        call    cref_to_phys
        mov     eax, ebx
        and     eax, PIXMASK
        mov     [es:di+BR_FG], eax
        shr     ebx, MONOB*8
        and     bl, 1
        mov     [es:di+BR_FGMONO], bl
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
        mov     [es:di+BR_MONO+bx], al  ; the hatch bits
        inc     si
        inc     dx
        cmp     dx, 8
        jb      .hrow
        push    di                      ; colour pattern: foreground everywhere
        add     di, BR_COLOR            ; (build_prow takes the hatch bits)
        mov     cx, 64
        mov     eax, [es:di+BR_FG-BR_COLOR]
        rep     STOSE
        pop     di
        jmp     .rotate
.pattern:
        mov     byte [es:di+BR_STYLE], 3
        lds     si, [si+2]              ; lbColor is a far pointer to the BITMAP
        mov     dx, [si+bmWidthBytes]   ; row stride (all planes)
        mov     cx, dx                  ; plane stride: planes are interleaved
        mov     al, [si+bmPlanes]       ; by scan line
%if PACKED
        cmp     word [si+bmPlanes], 0x0101
        je      .pm
        mov     al, 0xFF                ; packed colour pattern
.pm:
%else
        push    ax
        movzx   ax, al
        imul    dx, ax
        pop     ax
%endif
        push    ds
        mov     ds, [cs:dataseg]
        mov     [pat_planes], al
        pop     ds
        lds     si, [si+bmBits]
        push    di
        push    cx
        add     di, BR_COLOR
        mov     cx, 64*ELEM/2
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
; bx = row number, es:di -> brush.  Uses [pat_planes] (in our DGROUP):
; 1 = mono, 0xFF = packed colour, else planar colour.
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
.m:     push    eax
        shl     al, 1
        sbb     eax, eax
        and     eax, WHITE
        push    bx
        shl     bx, ESHIFT
        mov     [es:di+BR_COLOR+bx], EA
        pop     bx
        pop     eax
        shl     al, 1
        inc     bx
        dec     ah
        jnz     .m
        jmp     .r
.color:
%if PACKED
        push    cx                      ; packed: copy 8 pixels
        push    di
        mov     ax, dx
        shl     ax, ESHIFT
        add     di, ax
        add     di, BR_COLOR
        mov     cx, 8*ELEM
        rep     movsb
        pop     di
        pop     cx
%else
        ; planar colour pattern: combine the bitmap's planes
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
        cmp     al, 3                   ; 8-colour pattern: full-intensity colours
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
.c16:   pop     bp
%endif
        ; mono version: pixel == white -> 1
        mov     bx, dx
        xor     al, al
        mov     ah, 8
.mm:    shl     al, 1
        push    bx
        shl     bx, ESHIFT
        cmp     ESZ [es:di+BR_COLOR+bx], WHITE
        pop     bx
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

; dither_brush: eax = COLORREF, es:di -> brush.  DS = DGROUP.
dither_brush:
        push    eax
        push    edx
        mov     [db_cref], eax
        push    eax
        shr     eax, 16
        mov     dl, al                  ; dl = B
        pop     eax                     ; al = R, ah = G
%if BPP = 8
        mov     ebx, [db_cref]          ; a palette index: a solid brush
        shr     ebx, 24
        cmp     bl, 0xFF
        je      .solid
        cmp     bl, 0x01
        je      .solid
%endif
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
%if BPP <= 8
        call    dither16                ; -> d16_plan (colour numbers)
%else
        call    rgb_to_phys             ; HiColor / TrueColor: no dithering
        and     ebx, PIXMASK
        mov     [d16_solid], ebx
%endif
        xor     bx, bx
.l:     mov     al, [cs:bayer+bx]
        push    bx
%if BPP = 4
        movzx   bx, al
        movzx   eax, byte [d16_plan+bx]
%elif BPP = 8
        movzx   bx, al
        movzx   bx, byte [d16_plan+bx]
        movzx   eax, byte [cs:static_idx+bx]
%else
        mov     eax, [d16_solid]
%endif
        pop     bx
        push    bx
        shl     bx, ESHIFT
        mov     [es:di+BR_COLOR+bx], EA
        pop     bx
        ; mono
        mov     al, [cs:bayer+bx]
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
        pop     edx
        pop     eax
        ret
%if BPP = 8
.solid: mov     eax, [db_cref]
        call    cref_to_phys
        push    di
        push    cx
        add     di, BR_COLOR
        mov     al, bl
        mov     cx, 64
        rep     stosb
        pop     cx
        pop     di
        shr     ebx, 8                  ; mono pattern: all set or all clear
        and     bl, 1
        neg     bl
        mov     dword [es:di+BR_MONO], 0
        mov     dword [es:di+BR_MONO+4], 0
        or      bl, bl
        jz      .sd
        mov     dword [es:di+BR_MONO], 0xFFFFFFFF
        mov     dword [es:di+BR_MONO+4], 0xFFFFFFFF
.sd:    pop     edx
        pop     eax
        ret
%endif

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
        ; copy colour pattern + mono pattern to tmp_pat
        push    ds
        push    es
        pop     ds
        lea     si, [di+BR_COLOR]
        push    es
        mov     es, [cs:dataseg]
        push    di
        mov     di, tmp_pat
        push    cx
        mov     cx, 64*ELEM+8
        rep     movsb
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
        mov     al, [tmp_pat+64*ELEM+si]
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
        shl     si, ESHIFT
        mov     EA, [tmp_pat+si]
        push    bx
        shl     bx, ESHIFT
        mov     [es:di+BR_COLOR+bx], EA
        pop     bx
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

; check_solid: set BRF_SOLID / BR_FG if all colour pixels are equal (not hatched)
check_solid:
        test    byte [es:di+BR_FLAGS], BRF_HATCH
        jnz     .no
        mov     EA, [es:di+BR_COLOR]
        xor     bx, bx
.l:     cmp     [es:di+BR_COLOR+bx], EA
        jne     .no
        add     bx, ELEM
        cmp     bx, 64*ELEM
        jb      .l
        mov     al, [es:di+BR_MONO]
        xor     bx, bx
.m:     cmp     [es:di+BR_MONO+bx], al
        jne     .no
        inc     bx
        cmp     bx, 8
        jb      .m
        or      byte [es:di+BR_FLAGS], BRF_SOLID
        mov     eax, [es:di+BR_COLOR]
        and     eax, PIXMASK
        mov     [es:di+BR_FG], eax
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
