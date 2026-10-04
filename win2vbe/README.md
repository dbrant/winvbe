# VESA/VBE display driver for Windows 2.x (800x600 up to 1920x1080)

Dmitry Brant, 2026.
https://dmitrybrant.com

Display driver for Windows 2.x that runs Windows at 1024x768 and higher. It works on
any video adapter whose BIOS supports **VESA VBE 1.2 or later** and offers a
banked 256-colour mode at the chosen resolution. It also works on QEMU's
standard VGA adapter.

| Driver             | Resolution | Colours |
|--------------------|------------|---------|
| VBE800 / VBE800C   | 800x600    | 8 / 16  |
| VBE1024 / VBE1024C | 1024x768   | 8 / 16  |
| VBE1152 / VBE1152C | 1152x864   | 8 / 16  |
| VBE1280 / VBE1280C | 1280x1024  | 8 / 16  |
| VBE1600 / VBE1600C | 1600x1200  | 8 / 16  |
| VBE1920 / VBE1920C | 1920x1080  | 8 / 16  |

The 8-colour drivers behave like the stock Windows 2.03 VGA driver (3 planes,
dithered greys). The `C` drivers have 16 colours: they use the standard EGA/VGA
palette and dither 16-colour brushes.

## Where it runs

At startup the driver asks the video BIOS (INT 10h, AX=4F00h/4F01h) for a
256-colour packed-pixel mode at its resolution and sets it with 4F02h. It then
switches banks through the BIOS window function (or 4F05h), using the card's
window granularity and size, its separate read/write windows if it has them,
and its scanline pitch. Scanlines may cross bank boundaries. If the BIOS has no
such mode, the driver falls back to the Bochs/QEMU "DISPI" registers when they
exist. QEMU uses this fallback for 1920x1080. If neither works, a text-mode
message explains the problem.

Tested on:

* QEMU `-vga std`: through SeaBIOS VBE for 800x600 to 1600x1200 (including
  non-power-of-two pitches), and through DISPI for 1920x1080;
* QEMU `-vga cirrus` (Cirrus VBE BIOS, 16 KB bank granularity);
* 86Box with the S3 Trio32 PCI (Phoenix BIOS, VBE 1.2, 2 MB) at 1024x768.

Which resolutions a card supports is up to its BIOS. Run `VBELIST.COM` from the
floppy (or `drivers\`) in DOS to see the list. The emulated S3 Trio32 offers
256-colour modes at 640x480, 800x600, 1024x768 and 1280x1024, so VBE800,
VBE1024 and VBE1280 work there. Cards without a VESA BIOS (for example an
original Tseng ET4000) need a VBE TSR such as UniVBE loaded before Windows.

## Installing

`win2vbe.img` is a 1.44 MB floppy image with every driver, `VBELIST.COM`
and a short README.

1. Boot the machine to DOS, then insert the floppy image.
2. Run Windows 2.0 setup, and when selecting the display, choose
   **Other (requires disk provided by a hardware manufacturer)**, select `A:`,
   and pick a resolution, e.g. *VESA/VBE 1024x768 (16 colors)*.
3. When SETUP finishes, run `copy /y win.old win.ini` in `C:\WINDOWS`, since SETUP
   replaces your WIN.INI, and this will restore it.

## Why the 800x600 patch could not simply be extended

The Windows 2 VGA driver draws in 16-colour planar mode through the 64 KB VGA
window. 800x600 needs 800*600/8 = 60,000 bytes per plane, which still fits
(that is why `win2vesa` works). 1024x768 needs 98,304 bytes per plane. QEMU
cannot display planar memory beyond 64 KB per plane, and in its VBE 4-bpp modes
it drops CPU writes. Real cards usually need card-specific banking for planar
modes anyway. This driver therefore uses the universal 256-colour banked modes,
and it was written from scratch rather than by patching the VGA driver.

## How it works

* The screen is a **256-colour (8 bpp) banked frame buffer**, reached through the
  64 KB window at A000 (or whatever window the BIOS reports).
* Towards GDI it is a normal **planar device** (3 or 4 planes, 1 bpp). Memory
  bitmaps use the same format as the VGA driver, including bitmaps over 64 KB.
  Windows 2 programs that build bitmaps themselves keep working.
* The drawing primitives use a common row engine. Each operation reads rows of the
  source, destination and pattern into byte-per-pixel buffers (from the screen,
  a colour bitmap or a mono bitmap), applies the ROP3/ROP2 through a cached
  lookup table, and writes the row back. This covers BitBlt (all 256 ROPs,
  mono to/from colour conversion), FastBorder, Output (scan lines and styled
  polylines), ExtTextOut/StrBlt (Windows 2 raster fonts), Pixel and ScanLR
  (flood fill). Solid fills and screen-to-screen copies have fast paths.
* The software cursor is 32x32 with save-under. A semaphore guards it, so
  MoveCursor can safely be called at interrupt time while other code is drawing.
* The cursors, icons, system bitmaps and OEMBIN resources are copied from the
  stock `IBMPS250.DRV`, because USER loads them from the display driver.
* Each driver uses 16–24 KB of memory. The VGA driver uses about 25 KB.

## Tested

MS-DOS Executive, menus and dialogs, Paint (lines, shapes, text, flood fill),
Write (proportional fonts, scrolling), Reversi, Clock, Calculator, Excel 2
(sheets, charts), PC Paintbrush (PCX loading), and exiting Windows to DOS. See
`screenshots\`.

## Known limitations

* No hardware acceleration: on a slow emulated CPU (e.g. a 486 in 86Box),
  large redraws at high resolutions take a moment.
* Full-screen DOS programs could not be tested. This installation says "Not
  enough memory to run" for COMMAND.COM even with the original VGA driver.
* In the 16-colour drivers, programs written for the 8-colour Windows 2 VGA
  driver can look different. For example, PC Paintbrush shows its toolbox
  icons in black and white. Use the 8-colour drivers for the most authentic
  behaviour.

## Building

Needs Python 3 and NASM (https://www.nasm.us).

    cd src
    python build.py --nasm C:\path\to\nasm.exe --floppy ..\win2vbe.img

The script writes all twelve drivers, `VBELIST.COM` and `README.TXT` to
`src\drivers\`. It needs `IBMPS250.DRV`, `EGAHIRES.GRB` and `CGA.LGO` from the
Windows 2 setup files, and extracts them from `..\..\c_130_16_63_win203.img`
automatically (`--image` or `--template` override this). `mkne.py` is a small NE linker.
`mkfloppy.py` writes the FAT12 floppy image.

Source files: `vbe.asm` (entry points), `enable.asm` (GDIINFO, Enable/Disable),
`screen.asm` (VESA/DISPI mode setting, banking, span access), `color.asm`
(ColorInfo, RealizeObject, dithering), `surf.asm` (screen/bitmap row access),
`rop.asm`, `bitblt.asm`, `output.asm`, `text.asm`, `pixel.asm`, `cursor.asm`,
`stubs.asm`, `data.asm`, plus `vbelist.asm` (the mode-listing tool).

Inspired by [John Elliott](https://www.seasip.info/DOS/Win1/win2vesa.html)'s `win2vesa` (VGA2VESA/EGA2VESA).
