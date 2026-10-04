; ---------------------------------------------------------------------------
; Common definitions for the VESA/VBE display driver for Windows 2.x
; ---------------------------------------------------------------------------

%ifndef XRES
%define XRES 1024
%endif
%ifndef YRES
%define YRES 768
%endif
%ifndef BPP
%define BPP 4                   ; 4: 8 or 16 colours, planar towards GDI
%endif                          ; 8: 256 colours, fixed palette
%ifndef DEBUG
%define DEBUG 1
%endif

; Pixel elements: the row engine handles one element per pixel.  ELEM is its
; size in bytes, and the macros below name registers / string instructions of
; that width.  Physical colours are dwords: the pixel value in the low ELEM
; bytes (low 3 for TrueColor), the mono value (0/1) in byte MONOB.
%if BPP = 4
%ifndef NPLANES
%define NPLANES 3               ; planes in GDI-visible colour bitmaps (3 or 4)
%endif
PACKED          equ 0
NCOLORS         equ (1 << NPLANES)
ELEM            equ 1
PIXMASK         equ NCOLORS-1
%elif BPP = 8
%undef NPLANES
%define NPLANES 8               ; 256 colours as 8 planes towards GDI (planar
PACKED          equ 0           ; applications such as PC Paintbrush need that)
NCOLORS         equ 16                  ; the VGA colours (EnumObj)
ELEM            equ 1
PIXMASK         equ 0xFF
%elif BPP = 16
%define NPLANES 1
PACKED          equ 1
NCOLORS         equ 20
ELEM            equ 2
PIXMASK         equ 0xFFFF
%elif BPP = 32
%define NPLANES 1
PACKED          equ 1
NCOLORS         equ 20
ELEM            equ 4
PIXMASK         equ 0x00FFFFFF
%else
%error BPP must be 4, 8, 16 or 32
%endif
CMASK           equ PIXMASK
BITROP          equ (BPP > 4)           ; ROPs evaluated bitwise on pixel values (else by table)
PALMGR          equ 0                   ; 256 colours through the palette manager (3.0)
FIXPAL          equ (BPP = 8)           ; 256 colours, fixed palette
FP_CUBE         equ 20                  ; fixed palette: first entry of the 6x6x6 cube
WHITE           equ PIXMASK             ; pixel value of white (all bits set)
%if ELEM = 1
MONOB           equ 1
%define EA al
%define EB bl
%define EC cl
%define ED dl
%define ESZ byte
%define STOSE stosb
%define LODSE lodsb
%define MOVSE movsb
ESHIFT          equ 0
%elif ELEM = 2
MONOB           equ 2
%define EA ax
%define EB bx
%define EC cx
%define ED dx
%define ESZ word
%define STOSE stosw
%define LODSE lodsw
%define MOVSE movsw
ESHIFT          equ 1
%else
MONOB           equ 3
%define EA eax
%define EB ebx
%define EC ecx
%define ED edx
%define ESZ dword
%define STOSE stosd
%define LODSE lodsd
%define MOVSE movsd
ESHIFT          equ 2
%endif

; Scanline pitch in video memory: a power of two so every scanline lies in a
; single 64K bank.
%if XRES <= 1024
PSHIFT          equ 10
%elif XRES <= 2048
PSHIFT          equ 11
%else
PSHIFT          equ 12
%endif
PITCH           equ (1 << PSHIFT)       ; DISPI scan line, in pixels
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
BR_COLOR        equ 0           ; 64 elements: 8 rows x 8 pixels
BR_MONO         equ 64*ELEM     ; 8 bytes: mono pattern (hatch bits), bit 7 = leftmost
BR_STYLE        equ BR_MONO+8   ; 0 solid, 1 hollow, 2 hatched, 3 pattern
BR_FLAGS        equ BR_MONO+9
BR_FG           equ BR_MONO+10  ; dword: solid / hatch foreground pixel
BR_FGMONO       equ BR_MONO+14  ; its mono value
BR_SIZE         equ BR_MONO+16

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

ROWPIX          equ ((XRES + 64 + 15) & ~15)    ; pixels per row buffer
ROWBUF          equ ROWPIX*ELEM                 ; bytes
%ifdef TESTMAXW
MAXW            equ TESTMAXW
%else
MAXW            equ (ROWPIX - 64)          ; widest span processed at once
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
