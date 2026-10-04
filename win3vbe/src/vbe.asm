; ---------------------------------------------------------------------------
; VBE.DRV - Windows 3.0 display driver for VESA VBE (and QEMU/Bochs) adapters
; Banked VBE frame buffer.  BPP=4: an 8 bpp mode, presented to GDI as a
; 4-plane, 16-colour device.  BPP=8: 256 colours with the palette manager.
; BPP=16 / 32: HiColor (5:6:5 or 5:5:5) / TrueColor (8:8:8 in 32 bits).
; Runs in real, standard and 386 enhanced mode (386 CPU required).
; Dmitry Brant, 2026
; ---------------------------------------------------------------------------
[map symbols out/vbe.map]
        bits    16
        cpu     486
%include "defs.inc"

; KERNEL ordinals
%define K_GETMODULEHANDLE 47
%define K_GETPROCADDRESS 50
%define K_AHINCR 114
%define K_ALLOCCSTODSALIAS 170
%define K_A000H 174
%define K_FREESELECTOR 176
%define K_WINFLAGS 178
%define K_B000H 181
%define K_GLOBALDOSALLOC 184
%define K_GLOBALDOSFREE 185

WF_PMODE                equ 0x0001
WF_ENHANCED             equ 0x0020

        section CODE vstart=0

dataseg         dw      0               ; our DGROUP selector, stored by LibInit
old2f           dd      0               ; previous INT 2Fh handler

; ---------------------------------------------------------------------------
; Library initialisation: DS = data segment
; ---------------------------------------------------------------------------
LibInit:
        push    ds
        mov     ax, ds
        mov     bx, dataseg
        call    cs_write_word
        pop     ds
        KCONST  ax, KERNEL, K_WINFLAGS
        mov     [winflags], ax
        KCONST  ax, KERNEL, K_A000H
        mov     [sel_a000], ax
        KCONST  ax, KERNEL, K_B000H
        mov     [sel_b000], ax
        KCONST  ax, KERNEL, K_AHINCR
        mov     [ahincr], ax
        DBG     'VBE: LibInit flags='
        DBGX    [winflags]
        DBG     13,10
        mov     ax, 1
        retf

; cs_write_word: store ax at offset bx of our (read-only) code segment,
; through a temporary data alias.  Preserves all but ax, bx.
cs_write_word:
        push    cx
        push    dx
        push    es
        push    ax
        push    bx
        push    cs
        KCALL   KERNEL, K_ALLOCCSTODSALIAS
        mov     es, ax
        pop     bx
        pop     cx                      ; value
        mov     [es:bx], cx
        xor     dx, dx
        mov     es, dx
        push    ax
        KCALL   KERNEL, K_FREESELECTOR
        pop     es
        pop     dx
        pop     cx
        ret

%include "enable.asm"
%include "color.asm"
%include "stubs.asm"
%include "screen.asm"
%include "surf.asm"
%include "rop.asm"
%include "cursor.asm"
%include "bitblt.asm"
%include "output.asm"
%include "text.asm"
%include "pixel.asm"
%include "dib.asm"
%if BPP = 8
%include "palette.asm"
%endif
%if BPP > 8
%include "stretch.asm"
%endif
%include "debug.asm"
code_end:
        align   16, db 0

; ---------------------------------------------------------------------------
        section DATA follows=CODE vstart=0
%include "data.asm"
        align   16, db 0
