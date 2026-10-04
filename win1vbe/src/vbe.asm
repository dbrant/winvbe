; ---------------------------------------------------------------------------
; VBE.DRV - Windows 1.0x display driver for VESA VBE (and QEMU/Bochs) adapters
; 8bpp banked frame buffer internally; presents a planar device to GDI.
; Dmitry Brant, 2026
; ---------------------------------------------------------------------------
[map symbols out/vbe.map]
        bits    16
        cpu     486
%include "defs.inc"

        section CODE vstart=0

; Our DGROUP.  Windows 1 has no library initialisation call; every exported
; function's prologue is patched by KERNEL to load DGROUP and stores it here
; for code that needs it after calling out (callbacks, interrupt time).
dataseg         dw      0

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
%include "debug.asm"
code_end:
        align   16, db 0

; ---------------------------------------------------------------------------
        section DATA follows=CODE vstart=0
%include "data.asm"
        align   16, db 0
