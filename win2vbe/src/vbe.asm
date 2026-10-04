; ---------------------------------------------------------------------------
; VBE.DRV - Windows 2.x display driver for the QEMU/Bochs VBE adapter
; 8bpp banked frame buffer.  BPP=4: presented to GDI as a planar device
; (3 or 4 planes); BPP=8: 256 colours with a fixed palette.
; Dmitry Brant, 2026
; ---------------------------------------------------------------------------
[map symbols out/vbe.map]
        bits    16
        cpu     486
%include "defs.inc"

        section CODE vstart=0
; ---------------------------------------------------------------------------
; Jump table: order must match EXPORTS in mkne.py (3 bytes per entry)
; ---------------------------------------------------------------------------
        jmp     near LibInit
        jmp     near BitBlt
        jmp     near ColorInfo
        jmp     near Control
        jmp     near Disable
        jmp     near Enable
        jmp     near EnumDFonts
        jmp     near EnumObj
        jmp     near Output
        jmp     near Pixel
        jmp     near RealizeObject
        jmp     near StrBlt
        jmp     near ScanLR
        jmp     near DeviceMode
        jmp     near ExtTextOut
        jmp     near GetCharWidth
        jmp     near DeviceBitmap
        jmp     near FastBorder
        jmp     near SetAttribute
        jmp     near Output             ; Do_Polylines
        jmp     near Output             ; Do_Scanlines
        jmp     near Inquire
        jmp     near SetCursor
        jmp     near MoveCursor
        jmp     near CheckCursor

dataseg         dw      0               ; our DGROUP, stored by LibInit

; ---------------------------------------------------------------------------
; Library initialisation: DS = data segment
; ---------------------------------------------------------------------------
LibInit:
        mov     [cs:dataseg], ds
        DBG     'VBE: LibInit',13,10
        mov     ax, 1
        retf

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
%if FIXED
        times CODE_SIZE-($-$$) db 0
%else
        align   16, db 0
%endif

; ---------------------------------------------------------------------------
        section DATA follows=CODE vstart=0
%include "data.asm"
%if FIXED
        times DATA_SIZE-($-$$) db 0
%else
        align   16, db 0
%endif
