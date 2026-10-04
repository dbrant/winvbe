; ---------------------------------------------------------------------------
; Common definitions for the Bochs/QEMU VBE display driver for Windows 2.x
; ---------------------------------------------------------------------------

%ifndef XRES
%define XRES 1024
%endif
%ifndef YRES
%define YRES 768
%endif
%ifndef NPLANES
%define NPLANES 3               ; planes in GDI-visible color bitmaps
%endif
%ifndef DEBUG
%define DEBUG 1
%endif

%if NPLANES = 3
NCOLORS         equ 8
%else
NCOLORS         equ 16
%endif
CMASK           equ NCOLORS-1

; Scanline pitch in video memory: a power of two so every scanline lies in a
; single 64K bank.
%if XRES <= 1024
PSHIFT          equ 10
%elif XRES <= 2048
PSHIFT          equ 11
%else
PSHIFT          equ 12
%endif
PITCH           equ (1 << PSHIFT)
LSHIFT          equ (16 - PSHIFT)       ; log2(lines per bank)
LPBMASK         equ ((1 << LSHIFT) - 1)

%ifndef FIXED
%define FIXED 0                         ; 1 = pad segments to fixed sizes (in-place patch testing)
%endif
CODE_SIZE       equ 0x6000
DATA_SIZE       equ 0x3800

; Bochs DISPI interface
VBE_INDEX       equ 0x1CE
VBE_DATA        equ 0x1CF
VBEI_ID         equ 0
VBEI_XRES       equ 1
VBEI_YRES       equ 2
VBEI_BPP        equ 3
VBEI_ENABLE     equ 4
VBEI_BANK       equ 5
VBEI_VWIDTH     equ 6
VBEI_VHEIGHT    equ 7

VK_NONE         equ 0
VK_DISPI        equ 1
VK_VBE          equ 2

; GDI BITMAP / PDEVICE structure
bmType          equ 0
bmWidth         equ 2
bmHeight        equ 4
bmWidthBytes    equ 6
bmPlanes        equ 8
bmBitsPixel     equ 9
bmBits          equ 10
bmWidthPlanes   equ 14
bmlpPDevice     equ 18
bmSegmentIndex  equ 22
bmScanSegment   equ 24
bmFillBytes     equ 26

; DRAWMODE
dmRop2          equ 0
dmBkMode        equ 2
dmBkColor       equ 4
dmTextColor     equ 8
dmTBreakExtra   equ 0x0C
dmBreakExtra    equ 0x0E
dmBreakErr      equ 0x10
dmBreakRem      equ 0x12
dmBreakCount    equ 0x14
dmCharExtra     equ 0x16

OPAQUE          equ 2

; Physical colour: byte 0 = colour index, byte 1 = mono value (0/1)
; Physical pen (6 bytes)
PEN_COLOR       equ 0           ; dword physical colour
PEN_STYLE       equ 4
PEN_SIZE        equ 6

; Physical brush
BR_COLOR        equ 0           ; 64 bytes: 8 rows x 8 pixel indices
BR_MONO         equ 64          ; 8 bytes: mono pattern, bit 7 = leftmost
BR_STYLE        equ 72          ; 0 solid, 1 hollow, 2 hatched, 3 pattern
BR_FLAGS        equ 73
BR_FG           equ 74          ; hatched: foreground index
BR_FGMONO       equ 75          ; hatched: foreground mono value
BR_SIZE         equ 76

BRF_HATCH       equ 1

; Surface descriptor (built in the data segment for source / destination)
struc SURF
  .kind     resb 1      ; 0 = screen, 1 = mono memory, 2 = colour memory
  .planes   resb 1
  .width    resw 1
  .height   resw 1
  .wbytes   resw 1
  .boff     resw 1
  .bseg     resw 1
  .wplanes  resw 1      ; plane stride (small bitmaps)
  .segidx   resw 1      ; huge bitmaps: segment increment
  .scanseg  resw 1      ;               scans per segment
  .sstride  resw 1      ; huge bitmaps: bytes per scan (all planes)
endstruc
SK_SCREEN       equ 0
SK_MONO         equ 1
SK_COLOR        equ 2

ROWBUF          equ ((XRES + 64 + 15) & ~15)
%ifdef TESTMAXW
MAXW            equ TESTMAXW
%else
MAXW            equ (ROWBUF - 64)          ; widest span processed at once
%endif

; ---------------------------------------------------------------------------
; Macros
; ---------------------------------------------------------------------------
%macro PROLOG 0
        inc     bp
        push    bp
        mov     bp, sp
        push    ds
        mov     ds, [cs:dataseg]
        push    si
        push    di
        cld
%endmacro

%macro EPILOG 1
        lea     sp, [bp-6]
        pop     di
        pop     si
        pop     ds
        pop     bp
        dec     bp
        retf    %1
%endmacro

%if DEBUG
%macro DBG 1+
        call    dbg_inline
        db      %1, 0
%endmacro
%macro DBGX 1                   ; print a 16-bit register/value in hex
        push    ax
        mov     ax, %1
        call    dbg_hex
        pop     ax
%endmacro
%else
%macro DBG 1+
%endmacro
%macro DBGX 1
%endmacro
%endif
