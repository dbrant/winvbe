; ---------------------------------------------------------------------------
; Raster operations: a cached lookup table result = T[P,S,D] over color indices
; ---------------------------------------------------------------------------
%if NPLANES = 3
NB              equ 3
%else
NB              equ 4
%endif
ROPTAB_SIZE     equ (1 << (3*NB))

ROPF_P          equ 1
ROPF_S          equ 2
ROPF_D          equ 4

; rop_flags: al = rop3 -> ah = ROPF_* usage flags
rop_flags:
        push    cx
        xor     ah, ah
        mov     cl, al
        shr     cl, 4
        xor     cl, al
        test    cl, 0x0F
        jz      .s
        or      ah, ROPF_P
.s:     mov     cl, al
        shr     cl, 2
        xor     cl, al
        test    cl, 0x33
        jz      .d
        or      ah, ROPF_S
.d:     mov     cl, al
        shr     cl, 1
        xor     cl, al
        test    cl, 0x55
        jz      .r
        or      ah, ROPF_D
.r:     pop     cx
        ret

%if BITROP
; ---------------------------------------------------------------------------
; Packed pixels: ROPs are evaluated bitwise.  For each (P,S) combination the
; ROP is one of four functions of D: 0, D, ~D, 1, i.e. (D & mD) ^ mC.
; rop_m[2*ps] = mD, rop_m[2*ps+1] = mC, with ps = P*2 + S.
; ---------------------------------------------------------------------------
; build_rop_table: al = rop3.  Recomputes rop_m unless already cached.
build_rop_table:
        cmp     byte [rop_valid], 0
        je      .build
        cmp     al, [rop_cached]
        jne     .build
        ret
.build: push    ax
        push    bx
        push    cx
        push    edx
        mov     [rop_cached], al
        mov     byte [rop_valid], 1
        xor     bx, bx                  ; ps
        mov     ah, al
.l:     mov     cl, ah
        and     cl, 3                   ; bit 0: f(D=0), bit 1: f(D=1)
        xor     edx, edx
        test    cl, 1
        jz      .c0
        dec     edx
.c0:    mov     [rop_m+bx+4], edx       ; mC = f(0) ? ~0 : 0
        xor     edx, edx
        cmp     cl, 1
        je      .md
        cmp     cl, 2
        jne     .m0
.md:    dec     edx                     ; f(0) != f(1): depends on D
.m0:    mov     [rop_m+bx], edx
        shr     ah, 2
        add     bx, 8
        cmp     bx, 32
        jb      .l
        pop     edx
        pop     cx
        pop     bx
        pop     ax
        ret

; rop_eval: si -> P, bx -> S, di -> D (in/out), cx = count (pixels).
rop_eval:
        pushad
        shl     cx, ESHIFT
        add     cx, 3
        shr     cx, 2                   ; dwords (row buffers are padded)
        or      cx, cx
        jz      .r
        mov     [rop_cnt], cx
.l:     mov     eax, [si]               ; P
        mov     edx, [bx]               ; S
        mov     ebp, [di]               ; D
        mov     ecx, ebp                ; P=1 S=1
        and     ecx, [rop_m+24]
        xor     ecx, [rop_m+28]
        and     ecx, eax
        and     ecx, edx
        mov     [rop_acc], ecx
        not     edx                     ; P=1 S=0
        mov     ecx, ebp
        and     ecx, [rop_m+16]
        xor     ecx, [rop_m+20]
        and     ecx, eax
        and     ecx, edx
        or      [rop_acc], ecx
        not     eax                     ; P=0 S=0
        mov     ecx, ebp
        and     ecx, [rop_m+0]
        xor     ecx, [rop_m+4]
        and     ecx, eax
        and     ecx, edx
        or      [rop_acc], ecx
        not     edx                     ; P=0 S=1
        mov     ecx, ebp
        and     ecx, [rop_m+8]
        xor     ecx, [rop_m+12]
        and     ecx, eax
        and     ecx, edx
        or      ecx, [rop_acc]
        mov     [di], ecx
        add     si, 4
        add     bx, 4
        add     di, 4
        dec     word [rop_cnt]
        jnz     .l
.r:     popad
        ret

; rop_px: eax = pattern / pen pixel, edx = destination pixel -> eax = result
; (S = 0).  Uses the current rop_m.  Preserves the other registers.
rop_px:
        push    ecx
        mov     ecx, edx
        and     ecx, [rop_m+16]         ; P=1 S=0
        xor     ecx, [rop_m+20]
        and     ecx, eax
        not     eax
        and     edx, [rop_m+0]          ; P=0 S=0
        xor     edx, [rop_m+4]
        and     eax, edx
        or      eax, ecx
        pop     ecx
        ret

%else
; build_rop_table: al = rop3.  Rebuilds roptab unless already cached.
build_rop_table:
        cmp     byte [rop_valid], 0
        je      .build
        cmp     al, [rop_cached]
        jne     .build
        ret
.build: push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        mov     [rop_cached], al
        mov     byte [rop_valid], 1
        xor     di, di
.l:     xor     dl, dl                  ; result
        xor     cl, cl                  ; bit number
.b:     mov     si, di
        shr     si, cl
        xor     ch, ch                  ; k
        test    si, 1
        jz      .k1
        or      ch, 1
.k1:    test    si, 1 << NB
        jz      .k2
        or      ch, 2
.k2:    test    si, 1 << (2*NB)
        jz      .k3
        or      ch, 4
.k3:    push    cx
        mov     cl, ch
        mov     ah, [rop_cached]
        shr     ah, cl
        pop     cx
        and     ah, 1
        shl     ah, cl
        or      dl, ah
        inc     cl
        cmp     cl, NB
        jb      .b
        mov     [roptab+di], dl
        inc     di
        cmp     di, ROPTAB_SIZE
        jb      .l
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; rop_eval: si -> P, bx -> S, di -> D (in/out), cx = count.  Uses roptab.
rop_eval:
        push    eax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        jcxz    .r
.l:     movzx   ax, byte [si]
        and     al, CMASK
        shl     ax, NB
        mov     dl, [bx]
        and     dl, CMASK
        or      al, dl
        shl     ax, NB
        mov     dl, [di]
        and     dl, CMASK
        or      al, dl
        movzx   eax, ax
        mov     al, [roptab+eax]
        mov     [di], al
        inc     si
        inc     bx
        inc     di
        dec     cx
        jnz     .l
.r:     pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     eax
        ret

%endif

; rop2_to_rop3: al = R2_* (1..16) -> al = equivalent rop3 index
rop2_to_rop3:
        push    bx
        dec     al
        and     ax, 15
        mov     bx, ax
        mov     al, [cs:rop2tab+bx]
        pop     bx
        ret

rop2tab:
%assign t 0
%rep 16
 %assign r 0
 %assign k 0
 %rep 8
  %assign r r | (((t >> (((k >> 1) & 2) | (k & 1))) & 1) << k)
  %assign k k+1
 %endrep
        db      r
 %assign t t+1
%endrep

%if !BITROP
; make_pen_table: al = rop3, dl = pen value -> pentab[d] = result for all d
make_pen_table:
        push    ax
        push    bx
        push    cx
        call    build_rop_table
        movzx   bx, dl
        and     bl, CMASK
        shl     bx, 2*NB
        xor     cx, cx
.l:     mov     al, [roptab+bx]
        push    bx
        mov     bx, cx
        mov     [pentab+bx], al
        pop     bx
        inc     bx
        inc     cx
        cmp     cx, NCOLORS
        jb      .l
        pop     cx
        pop     bx
        pop     ax
        ret
%endif
