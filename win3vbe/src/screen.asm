; ---------------------------------------------------------------------------
; Video hardware: mode setting (VESA BIOS, or Bochs/QEMU DISPI registers),
; bank switching and split-aware access to spans of the 8bpp frame buffer.
;
; Protected mode notes: the frame buffer window is reached through KERNEL's
; __A000H / __B000H selectors.  VBE calls that pass buffers go through DPMI
; "simulate real mode interrupt" with a GlobalDosAlloc'd buffer; register-only
; calls (set mode, bank switch) are plain INT 10h, which Windows reflects.
; In protected mode the BIOS window function (a real-mode far pointer) cannot
; be called directly, so banks are switched with INT 10h 4F05h, or directly
; through the DISPI registers when the adapter has them.
; ---------------------------------------------------------------------------
%if XRES = 640 && YRES = 480
STDMODE         equ 0x101
%elif XRES = 800 && YRES = 600
STDMODE         equ 0x103
%elif XRES = 1024 && YRES = 768
STDMODE         equ 0x105
%elif XRES = 1280 && YRES = 1024
STDMODE         equ 0x107
%else
STDMODE         equ 0
%endif
MAXMODES        equ (ROWBUF / 2 - 2)
DOSBUF_SIZE     equ 1024                ; 512 info block + 256 mode info + slack

; set_video_mode: find (first time only) and set the mode.  CF=1 if none.
set_video_mode:
        cmp     byte [vmode_kind], VK_NONE
        jne     .known
        call    try_vbe
        jnc     .found
        call    try_dispi
        jc      .r
.found:
%if DEBUG
        DBG     'mode kind='
        movzx   ax, byte [vmode_kind]
        DBGX    ax
        DBG     'vbe='
        DBGX    [vbe_mode]
        DBG     'pitch='
        DBGX    [scr_pitch]
        DBG     'mult='
        DBGX    [bank_mult]
        DBG     'shift='
        movzx   ax, byte [bank_shift]
        DBGX    ax
        DBG     'segs='
        DBGX    [win_rseg]
        DBGX    [win_wseg]
        DBG     'both='
        movzx   ax, byte [win_both]
        DBGX    ax
        DBG     'dispibank='
        movzx   ax, byte [dispi_bank]
        DBGX    ax
        DBG     13,10
%endif
.known: call    restore_video_mode
        clc
.r:     ret

; restore_video_mode: (re)program the mode found earlier.  Register-only BIOS
; calls, so it may also be used from the INT 2Fh handler.
restore_video_mode:
        cmp     byte [vmode_kind], VK_DISPI
        jne     .vbe
        call    dispi_set
        jmp     .common
.vbe:   mov     ax, 0x4F02
        mov     bx, [vbe_mode]
        int     0x10
        mov     ds, [cs:dataseg]
        cmp     byte [dispi_bank], 0
        je      .common
        mov     dx, VBE_INDEX           ; DISPI banking: park the index on BANK
        mov     ax, VBEI_BANK
        out     dx, ax
.common:
        mov     word [cur_bank], -1
        call    set_palette
        call    clear_screen
        ret

; leave_video_mode: undo DISPI state before going back to text mode
leave_video_mode:
        cmp     byte [vmode_kind], VK_DISPI
        jne     .r
        mov     dx, VBE_INDEX
        mov     ax, VBEI_ENABLE
        out     dx, ax
        inc     dx
        xor     ax, ax
        out     dx, ax
.r:     ret

; ---------------------------------------------------------------------------
; Calling the VESA BIOS with a buffer
; ---------------------------------------------------------------------------
; vbe_call: ax = function, bx, cx = arguments; ES:DI = dosbuf:di_off
; (real-mode address of our conventional memory buffer + [vbe_di]).
; Returns ax.  Clobbers bx, cx, dx, si, di, es.
vbe_call:
        test    word [winflags], WF_PMODE
        jnz     .pm
        mov     es, [dos_rseg]
        mov     di, [vbe_di]
        int     0x10
        mov     ds, [cs:dataseg]
        ret
.pm:    push    ax
        push    ds
        pop     es
        mov     di, rmregs
        push    cx
        mov     cx, 25
        xor     ax, ax
        rep     stosw
        pop     cx
        pop     ax
        mov     [rmregs+0x1C], ax       ; EAX
        mov     [rmregs+0x10], bx       ; EBX
        mov     [rmregs+0x18], cx       ; ECX
        mov     ax, [vbe_di]
        mov     [rmregs+0x00], ax       ; EDI
        mov     ax, [dos_rseg]
        mov     [rmregs+0x22], ax       ; ES
        mov     di, rmregs
        mov     bx, 0x0010              ; INT 10h
        xor     cx, cx
        mov     ax, 0x0300              ; DPMI: simulate real mode interrupt
        int     0x31
        mov     ds, [cs:dataseg]
        jc      .fail
        mov     ax, [rmregs+0x1C]
        ret
.fail:  mov     ax, 0xFFFF
        ret

; rm_ptr_sel: dx = real-mode segment -> es = selector for it (PM), or the
; segment itself in real mode.  CF=1 if no selector could be made.
rm_ptr_sel:
        test    word [winflags], WF_PMODE
        jnz     .pm
        mov     es, dx
        clc
        ret
.pm:    cmp     dx, [dos_rseg]
        jne     .d
        mov     es, [dos_psel]
        clc
        ret
.d:     push    ax
        push    bx
        mov     bx, dx
        mov     ax, 0x0002              ; DPMI: segment to descriptor
        int     0x31
        jc      .f
        mov     es, ax
        pop     bx
        pop     ax
        clc
        ret
.f:     pop     bx
        pop     ax
        stc
        ret

; ---------------------------------------------------------------------------
; VESA BIOS extensions
; ---------------------------------------------------------------------------
try_vbe:
        ; conventional memory buffer for the BIOS
        push    word 0
        push    word DOSBUF_SIZE
        KCALL   KERNEL, K_GLOBALDOSALLOC
        or      ax, ax
        jz      .nobuf
        mov     [dos_psel], ax
        mov     [dos_rseg], dx
        call    try_vbe_body
        pushf
        push    word [dos_psel]
        KCALL   KERNEL, K_GLOBALDOSFREE
        popf
        ret
.nobuf: stc
        ret

try_vbe_body:
        mov     es, [dos_psel]          ; clear the buffer
        xor     di, di
        mov     cx, DOSBUF_SIZE/2
        xor     ax, ax
        rep     stosw
        mov     word [vbe_di], 0
        mov     ax, 0x4F00
        call    vbe_call
        cmp     ax, 0x004F
        jne     .fail
        ; copy the info block into DBUF
        push    ds
        pop     es
        mov     di, DBUF
        push    ds
        mov     ds, [dos_psel]
        xor     si, si
        mov     cx, 256
        rep     movsw
        pop     ds
        cmp     dword [DBUF], 'VESA'
        jne     .fail
        ; copy the mode list (it may live inside the info block)
        mov     dx, [DBUF+0x10]         ; segment of VideoModePtr
        call    rm_ptr_sel
        jc      .fail
        mov     si, [DBUF+0x0E]
        mov     di, SBUF
        mov     cx, MAXMODES
.cp:    mov     ax, [es:si]
        add     si, 2
        mov     [di], ax
        add     di, 2
        cmp     ax, 0xFFFF
        je      .cpd
        loop    .cp
        mov     word [di], 0xFFFF
.cpd:   mov     si, SBUF
.next:  lodsw
        cmp     ax, 0xFFFF
        je      .std
        mov     [vbe_mode], ax
        call    vbe_check_mode
        jnc     .found
        jmp     .next
.std:
%if STDMODE
        mov     word [vbe_mode], STDMODE
        call    vbe_check_mode
        jnc     .found
%endif
.fail:  stc
        ret
.found: ; choose the window(s): PBUF holds the ModeInfoBlock
        mov     al, [PBUF+2]            ; window A attributes
        mov     ah, [PBUF+3]            ; window B attributes
        mov     bx, [PBUF+8]            ; window A segment
        mov     dx, [PBUF+0x0A]         ; window B segment
        mov     byte [win_first], 0
        mov     byte [win_both], 0
        mov     cl, al
        and     cl, 7
        cmp     cl, 7                   ; A: exists, readable, writeable
        jne     .w2
        mov     [win_rseg], bx
        mov     [win_wseg], bx
        jmp     .wok
.w2:    mov     cl, ah
        and     cl, 7
        cmp     cl, 7                   ; B alone
        jne     .w3
        mov     [win_rseg], dx
        mov     [win_wseg], dx
        mov     byte [win_first], 1
        jmp     .wok
.w3:    mov     byte [win_both], 1      ; separate read and write windows
        mov     cl, al
        and     cl, 5
        cmp     cl, 5
        jne     .w4
        mov     cl, ah
        and     cl, 3
        cmp     cl, 3
        jne     .fail
        mov     [win_wseg], bx
        mov     [win_rseg], dx
        jmp     .wok
.w4:    mov     cl, al
        and     cl, 3
        cmp     cl, 3
        jne     .fail
        mov     cl, ah
        and     cl, 5
        cmp     cl, 5
        jne     .fail
        mov     [win_rseg], bx
        mov     [win_wseg], dx
.wok:   ; real-mode window segments -> selectors
        mov     ax, [win_rseg]
        call    win_sel
        jc      .fail
        mov     [win_rseg], ax
        mov     ax, [win_wseg]
        call    win_sel
        jc      .fail
        mov     [win_wseg], ax
        ; window size (power of two, at most 64K) and granularity
        mov     ax, [PBUF+6]
        cmp     ax, 64
        jbe     .ws
        mov     ax, 64
.ws:    or      ax, ax
        jz      .fail
        bsf     cx, ax
        mov     dx, 1
        shl     dx, cl
        cmp     dx, ax
        jne     .fail
        add     cl, 10
        mov     [bank_shift], cl
        movzx   eax, ax
        shl     eax, 10
        dec     eax
        mov     [win_mask], eax
        mov     ax, [PBUF+6]
        cmp     ax, 64
        jbe     .wg
        mov     ax, 64
.wg:    mov     cx, [PBUF+4]            ; granularity (K)
        or      cx, cx
        jnz     .gd
        mov     cx, ax
.gd:    xor     dx, dx
        div     cx
        or      dx, dx
        jnz     .fail
        or      ax, ax
        jz      .fail
        mov     [bank_mult], ax
        mov     eax, [PBUF+0x0C]
        mov     [win_func], eax
        movzx   eax, word [PBUF+0x10]   ; bytes per scan line
        cmp     ax, XRES
        jb      .fail
        mov     [scr_pitch], eax
        mov     byte [vmode_kind], VK_VBE
        ; QEMU/Bochs: switch banks through the DISPI register (much cheaper
        ; than INT 10h from protected mode).  Only with 64K granularity.
        mov     byte [dispi_bank], 0
        test    word [winflags], WF_PMODE
        jz      .ok
        cmp     word [bank_mult], 1
        jne     .ok
        cmp     byte [bank_shift], 16
        jne     .ok
        cmp     byte [win_both], 0
        jne     .ok
        call    dispi_present
        jc      .ok
        mov     byte [dispi_bank], 1
.ok:    clc
        ret

; win_sel: ax = real-mode window segment -> ax = selector.  CF=1 if unsupported.
win_sel:
        test    word [winflags], WF_PMODE
        jz      .ok
        cmp     ax, 0xA000
        jne     .b
        mov     ax, [sel_a000]
        jmp     .ok
.b:     cmp     ax, 0xB000
        jne     .no
        mov     ax, [sel_b000]
.ok:    clc
        ret
.no:    stc
        ret

; vbe_check_mode: [vbe_mode] -> CF=0 if it is XRES x YRES in our pixel format
; (8 bpp packed; 15/16 bpp direct for HiColor; 32 bpp x8r8g8b8 for TrueColor).
; Leaves the ModeInfoBlock in PBUF.  Preserves si.
vbe_check_mode:
        push    si
        mov     es, [dos_psel]
        mov     di, 512
        mov     cx, 128
        xor     ax, ax
        rep     stosw
        mov     word [vbe_di], 512
        mov     ax, 0x4F01
        mov     cx, [vbe_mode]
        call    vbe_call
        push    ax
        push    ds
        pop     es
        mov     di, PBUF
        push    ds
        mov     ds, [dos_psel]
        mov     si, 512
        mov     cx, 128
        rep     movsw
        pop     ds
        pop     ax
        cmp     ax, 0x004F
        jne     .no
        mov     ax, [PBUF]              ; mode attributes
        test    al, 0x01                ; supported by the hardware
        jz      .no
        test    al, 0x10                ; graphics mode
        jz      .no
        test    al, 0x02                ; resolution information present?
        jz      .noext
        cmp     word [PBUF+0x12], XRES
        jne     .no
        cmp     word [PBUF+0x14], YRES
        jne     .no
        cmp     byte [PBUF+0x18], 1     ; planes
        jne     .no
%if BPP <= 8
        cmp     byte [PBUF+0x19], 8     ; bits per pixel
        jne     .no
        cmp     byte [PBUF+0x1B], 4     ; packed pixel
        jne     .no
%else
        mov     al, [PBUF+0x1B]         ; memory model: direct color (or packed)
        cmp     al, 6
        je      .dc
        cmp     al, 4
        jne     .no
.dc:
%if BPP = 16
        mov     byte [pix_g6], 1
        cmp     byte [PBUF+0x19], 16
        je      .m16
        cmp     byte [PBUF+0x19], 15
        jne     .no
        mov     byte [pix_g6], 0        ; 5:5:5
        jmp     .yes
.m16:   test    byte [PBUF], 0x02
        jz      .yes
        cmp     byte [PBUF+0x21], 5     ; green mask size 5: 5:5:5 after all
        jne     .yes
        mov     byte [pix_g6], 0
%else
        cmp     byte [PBUF+0x19], 32
        jne     .no
        cmp     byte [PBUF+0x20], 16    ; red at bit 16, green 8, blue 0
        jne     .no
        cmp     byte [PBUF+0x22], 8
        jne     .no
        cmp     byte [PBUF+0x24], 0
        jne     .no
%endif
%endif
        jmp     .yes
.noext:
%if BPP > 8
        jmp     .no
%endif
        cmp     word [vbe_mode], STDMODE
        jne     .no
        cmp     word [vbe_mode], 0
        je      .no
.yes:   pop     si
        clc
        ret
.no:    pop     si
        stc
        ret

; vbe_setwin: bx = window (0 = A, 1 = B), position = cur_bank * bank_mult
vbe_setwin:
        mov     ds, [cs:dataseg]
        mov     ax, [cur_bank]
        mul     word [bank_mult]
        mov     dx, ax
        test    word [winflags], WF_PMODE
        jnz     .int
        cmp     dword [win_func], 0
        je      .int
        pushf                           ; the window function may leave interrupts
        call    far [win_func]          ; disabled (SeaVGABIOS starts with CLI and
        popf                            ; returns with RETF)
        ret
.int:   mov     ax, 0x4F05
        int     0x10
        ret

; ---------------------------------------------------------------------------
; Bochs / QEMU DISPI registers
; ---------------------------------------------------------------------------
%macro VBEOUT 2
        mov     dx, VBE_INDEX
        mov     ax, %1
        out     dx, ax
        inc     dx
        mov     ax, %2
        out     dx, ax
%endmacro

; dispi_present: CF=0 if the Bochs DISPI interface answers
dispi_present:
        mov     dx, VBE_INDEX
        mov     ax, VBEI_ID
        out     dx, ax
        inc     dx
        in      ax, dx
        cmp     ax, 0xB0C0
        jb      .no
        cmp     ax, 0xB0CF
        ja      .no
        clc
        ret
.no:    stc
        ret

try_dispi:
        call    dispi_present
        jc      .no
        mov     byte [vmode_kind], VK_DISPI
        mov     dword [scr_pitch], PITCH*ELEM
%if BPP = 16
        mov     byte [pix_g6], 1        ; DISPI 16 bpp is 5:6:5
%endif
        mov     ax, [sel_a000]
        test    word [winflags], WF_PMODE
        jnz     .s
        mov     ax, 0xA000
.s:     mov     [win_rseg], ax
        mov     [win_wseg], ax
        mov     byte [bank_shift], 16
        mov     dword [win_mask], 0xFFFF
        mov     word [bank_mult], 1
        clc
        ret
.no:    stc
        ret

dispi_set:
        mov     ax, 0x0013
        int     0x10
        mov     ds, [cs:dataseg]
        VBEOUT  VBEI_ENABLE, 0
        VBEOUT  VBEI_XRES, XRES
        VBEOUT  VBEI_YRES, YRES
%if BPP <= 8
        VBEOUT  VBEI_BPP, 8
%else
        VBEOUT  VBEI_BPP, BPP
%endif
        VBEOUT  VBEI_ENABLE, 1
        VBEOUT  VBEI_VWIDTH, PITCH
        VBEOUT  VBEI_BANK, 0            ; leaves the index register at BANK
        ret

; ---------------------------------------------------------------------------
; Bank switching: ax = bank (window-size units).  Preserves all registers.
; ---------------------------------------------------------------------------
set_bank:
        cmp     ax, [cur_bank]
        jne     .sw
        ret
.sw:    mov     [cur_bank], ax
        cmp     byte [vmode_kind], VK_DISPI
        je      .dispi
        cmp     byte [dispi_bank], 0
        jne     .dispi
        pushad
        push    es
        push    ds
        movzx   bx, byte [win_first]
        call    vbe_setwin
        mov     ds, [cs:dataseg]
        cmp     byte [win_both], 0
        je      .d
        movzx   bx, byte [win_first]
        xor     bl, 1
        call    vbe_setwin
.d:     pop     ds
        pop     es
        popad
        ret
.dispi: push    dx
        mov     dx, VBE_DATA
        out     dx, ax
        pop     dx
        ret

; scr_span: ax = y, cx = x, dx = w (> 0).  Selects the bank holding (x, y),
; returns di = offset in the window and cx = number of bytes (<= w) that are
; contiguous there.  Preserves ax, bx, dx, si.
scr_span:
        push    eax
        push    ebx
        push    edx
        movzx   ebx, dx
        movzx   eax, ax
        imul    eax, [scr_pitch]
        movzx   ecx, cx
        add     eax, ecx                ; linear offset
        mov     edx, eax
        mov     cl, [bank_shift]
        shr     edx, cl
        push    eax
        mov     ax, dx
        call    set_bank
        pop     eax
        and     eax, [win_mask]
        mov     di, ax
        mov     ecx, [win_mask]
        inc     ecx
        sub     ecx, eax                ; bytes left in the window
        cmp     ecx, ebx
        jbe     .ok
        mov     ecx, ebx
.ok:    pop     edx
        pop     ebx
        pop     eax
        ret

; scr_read: ax = y, cx = x, dx = w (pixels), di -> buffer (DS).  Preserves registers.
scr_read:
        cmp     byte [enabled], 0       ; in the background: the screen is not ours
        je      .off
        pushad
%if ESHIFT
        shl     cx, ESHIFT              ; pixels -> bytes
        shl     dx, ESHIFT
%endif
        push    es
        push    ds
        pop     es
        mov     bx, di
.l:     push    cx
        call    scr_span
        mov     bp, cx
        push    ds
        mov     si, di
        mov     di, bx
        mov     ds, [win_rseg]
        push    cx
        shr     cx, 2
        rep     movsd
        pop     cx
        and     cx, 3
        rep     movsb
        pop     ds
        mov     bx, di
        pop     cx
        add     cx, bp
        sub     dx, bp
        jnz     .l
        pop     es
        popad
.off:   ret

; scr_write: ax = y, cx = x, dx = w (pixels), si -> buffer (DS).  Preserves registers.
scr_write:
        cmp     byte [enabled], 0
        je      .off
        pushad
%if ESHIFT
        shl     cx, ESHIFT
        shl     dx, ESHIFT
%endif
        push    es
        mov     bx, si
.l:     push    cx
        call    scr_span
        mov     bp, cx
        mov     es, [win_wseg]
        mov     si, bx
        push    cx
        shr     cx, 2
        rep     movsd
        pop     cx
        and     cx, 3
        rep     movsb
        mov     bx, si
        pop     cx
        add     cx, bp
        sub     dx, bp
        jnz     .l
        pop     es
        popad
.off:   ret

; scr_fill: ax = y, cx = x, dx = w (pixels), pixel value in [fill_val].
; Preserves registers.
scr_fill:
        cmp     byte [enabled], 0
        je      .off
        pushad
        push    es
%if ESHIFT
        shl     cx, ESHIFT
        shl     dx, ESHIFT
%endif
        push    eax                     ; fill_pat: the pixel repeated over a dword
        mov     eax, [fill_val]
%if ELEM = 1
        mov     ah, al
%endif
%if ELEM <= 2
        push    ax
        shl     eax, 16
        pop     ax
%endif
        mov     [fill_pat], eax
        pop     eax
.l:     push    cx
        call    scr_span
        mov     bp, cx
        mov     es, [win_wseg]
        push    eax
        mov     eax, [fill_pat]
        push    cx
        shr     cx, 2
        rep     stosd
        pop     cx
        and     cx, 3
        jz      .nb
.rb:    stosb                           ; spans start on a pixel, so the
        shr     eax, 8                  ; pattern phase is right
        loop    .rb
.nb:    pop     eax
        pop     cx
        add     cx, bp
        sub     dx, bp
        jnz     .l
        pop     es
        popad
.off:   ret

; scr_getpix: ax = y, cx = x -> EA (pixel).  scr_putpix: ax = y, cx = x,
; ED = pixel.
scr_getpix:
        cmp     byte [enabled], 0
        je      .off
        push    cx
        push    dx
        push    di
        push    es
        mov     dx, ELEM
%if ESHIFT
        shl     cx, ESHIFT
%endif
        call    scr_span
        mov     es, [win_rseg]
        mov     EA, [es:di]
        pop     es
        pop     di
        pop     dx
        pop     cx
        ret
.off:   xor     EA, EA
        ret

scr_putpix:
        cmp     byte [enabled], 0
        je      .off
        push    cx
        push    dx
        push    di
        push    es
%if ELEM = 4
        push    edx
%else
        push    dx
%endif
        mov     dx, ELEM
%if ESHIFT
        shl     cx, ESHIFT
%endif
        call    scr_span
%if ELEM = 4
        pop     edx
%else
        pop     dx
%endif
        mov     es, [win_wseg]
        mov     [es:di], ED
        pop     es
        pop     di
        pop     dx
        pop     cx
.off:   ret

clear_screen:
        pushad
        push    es
        mov     eax, [scr_pitch]
        imul    eax, eax, YRES
        add     eax, [win_mask]
        mov     cl, [bank_shift]
        shr     eax, cl
        mov     bx, ax                  ; number of banks
        xor     si, si
.b:     mov     ax, si
        call    set_bank
        mov     es, [win_wseg]
        xor     di, di
        mov     ecx, [win_mask]
        inc     ecx
        shr     ecx, 2
        xor     eax, eax
        rep     stosd
        inc     si
        cmp     si, bx
        jb      .b
        pop     es
        popad
        ret

set_palette:
%if BPP = 4
        mov     dx, 0x3C8
        xor     al, al
        out     dx, al
        inc     dx
        mov     si, palette6
        mov     cx, NCOLORS*3
.l:     mov     al, [cs:si]
        out     dx, al
        inc     si
        loop    .l
%elif BPP = 8
        xor     ax, ax                  ; the whole palette from pal_rgb
        mov     cx, 256
        call    dac_load
%endif
        ret

%if BPP = 8
; dac_load: program DAC entries ax .. ax+cx-1 from pal_rgb.  Preserves si.
dac_load:
        push    si
        mov     dx, 0x3C8
        out     dx, al
        inc     dx
        movzx   si, al
        shl     si, 2
        add     si, pal_rgb
.l:     mov     al, [si]                ; red
        shr     al, 2
        out     dx, al
        mov     al, [si+1]
        shr     al, 2
        out     dx, al
        mov     al, [si+2]
        shr     al, 2
        out     dx, al
        add     si, 4
        loop    .l
        pop     si
        ret
%endif

palette6:                               ; Windows VGA 16-color order (plane 0 = red)
        db       0,  0,  0
        db      32,  0,  0
        db       0, 32,  0
        db      32, 32,  0
        db       0,  0, 32
        db      32,  0, 32
        db       0, 32, 32
        db      48, 48, 48
        db      32, 32, 32
        db      63,  0,  0
        db       0, 63,  0
        db      63, 63,  0
        db       0,  0, 63
        db      63,  0, 63
        db       0, 63, 63
        db      63, 63, 63
