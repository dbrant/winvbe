# VESA/VBE display driver for Windows 2.x (800x600 up to 1920x1080)

Dmitry Brant, 2026.
https://dmitrybrant.com

Display driver for Windows 2.x that runs Windows at 1024x768 and higher. It works on
any video adapter whose BIOS supports **VESA VBE 1.2 or later** and offers a
banked 256-colour mode at the chosen resolution. It also works on QEMU's
standard VGA adapter.

| Driver                       | Resolution | Colours       |
|------------------------------|------------|---------------|
| VBE800 / VBE800C / VBE800P    | 800x600    | 8 / 16 / 256  |
| VBE1024 / VBE1024C / VBE1024P | 1024x768   | 8 / 16 / 256  |
| VBE1152 / VBE1152C / VBE1152P | 1152x864   | 8 / 16 / 256  |
| VBE1280 / VBE1280C / VBE1280P | 1280x1024  | 8 / 16 / 256  |
| VBE1600 / VBE1600C / VBE1600P | 1600x1200  | 8 / 16 / 256  |
| VBE1920 / VBE1920C / VBE1920P | 1920x1080  | 8 / 16 / 256  |

The 8-colour drivers behave like the stock Windows 2.03 VGA driver (3 planes,
dithered greys). The `C` drivers have 16 colours: they use the standard 16-colour
palette, with the colour numbering of the Windows EGA/VGA drivers (bit 0 red,
bit 1 green, bit 2 blue, bit 3 bright), so programs that write bitmap bits
directly get the right colours. They also dither 16-colour brushes.

The `P` drivers have **256 colours**. Windows 2 has no palette manager, so the
palette is fixed (see [256 colours](#256-colours) below). Pens, text and
brushes get the nearest of the 256 colours, and brushes between them are
dithered over the colour cube.

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
* 86Box with the S3 Trio32 PCI (Phoenix BIOS, VBE 1.2, 2 MB) at 1024x768,
  including the 256-colour driver.

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
   and pick a resolution and colour count, e.g. *VESA/VBE 1024x768 (256 colors)*.
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

## 256 colours

Windows 2 knows nothing of palettes: applications ask for RGB colours and the
driver picks device colours. The `P` drivers therefore load a fixed palette:

* 0–15: the 16 EGA/VGA colours, numbered as in PCX files and the EGA (bit 0
  blue, bit 1 green, bit 2 red, bit 3 bright);
* 20–235: a 6x6x6 colour cube (levels 0, 51, 102, 153, 204, 255);
* the rest: the complements of 0–19 (entry 255−i is the complement of entry i)
  and a few greys.

Entry i and entry 255−i are always complementary colours, so the inverting
raster operations (the cursor, selection highlights, XOR drawing) turn every
colour into its complement, and black into white.

Towards GDI, the 256-colour device has **8 planes at 1 bit per pixel**, not 1
plane at 8 bits. Windows 2 applications that handle bitmaps themselves are
written for planar displays. PC Paintbrush is one: it loads images into bitmaps
with as many planes as the display has, and on a 1-plane display it shows
16-colour PCX files in black and white. With 8 planes, its 8- and 16-colour
pictures appear in colour, in the low planes, which is why the 16 basic colours
are numbered in PCX/EGA order. Memory bitmaps hold one plane after another, as
with the other drivers; the screen itself is still an 8 bpp frame buffer.

The driver also answers the `GETCOLORTABLE` escape with the palette entries
and accepts `SETCOLORTABLE`, which lets an application change palette entries
(that turns off the cube dithering, since the cube may be gone).

## How it works

* The screen is a **256-colour (8 bpp) banked frame buffer**, reached through the
  64 KB window at A000 (or whatever window the BIOS reports).
* Towards GDI it is a normal **planar device** (3, 4 or 8 planes, 1 bpp). Memory
  bitmaps use the same format as the VGA driver, including bitmaps over 64 KB.
  Windows 2 programs that build bitmaps themselves keep working.
* The drawing primitives use a common row engine. Each operation reads rows of the
  source, destination and pattern into byte-per-pixel buffers (from the screen,
  a colour bitmap or a mono bitmap), applies the ROP3/ROP2 (through a cached
  lookup table with 8 and 16 colours, bitwise on the pixel values with 256),
  and writes the row back. This covers BitBlt (all 256 ROPs,
  mono to/from colour conversion), FastBorder, Output (scan lines and styled
  polylines), ExtTextOut/StrBlt (Windows 2 raster fonts), Pixel and ScanLR
  (flood fill). Solid fills and screen-to-screen copies have fast paths.
* The software cursor is 32x32 with save-under. A semaphore guards it, so
  MoveCursor can safely be called at interrupt time while other code is drawing. Redraws at
  interrupt time run on the driver's own stack with interrupts disabled:
  Windows calls the cursor routines from the mouse and timer interrupts on
  stacks of only a few hundred bytes, and lets mouse interrupts nest.
* The cursors, icons, system bitmaps and OEMBIN resources are copied from the
  stock `IBMPS250.DRV`, because USER loads them from the display driver.
* Each driver uses 16–24 KB of memory. The VGA driver uses about 25 KB.

## Tested

MS-DOS Executive, menus and dialogs, Paint (lines, shapes, text, flood fill),
Write (proportional fonts, scrolling), Reversi, Clock, Calculator, Excel 2
(sheets, charts), PC Paintbrush (PCX loading), and exiting Windows to DOS. See
`screenshots\`.

With 256 colours: MS-DOS Executive, Control Panel, Reversi, Write, Calculator,
Paint, Clock, Cardfile and PC Paintbrush (EAGLE, PARROT and CAMERA.PCX, and
drawing on them), in QEMU and in 86Box with the S3 Trio32.

## Known limitations

* No hardware acceleration: on a slow emulated CPU (e.g. a 486 in 86Box),
  large redraws at high resolutions take a moment.
* Full-screen DOS programs could not be tested. This installation says "Not
  enough memory to run" for COMMAND.COM even with the original VGA driver.
* In the 16- and 256-colour drivers, programs written for the 8-colour Windows 2
  VGA driver can look different. For example, PC Paintbrush shows its toolbox
  icons in black and white. Use the 8-colour drivers for the most authentic
  behaviour.
* PC Paintbrush loads 256-colour PCX files without their palette (it writes
  the colour numbers as they are), so their colours are wrong with the
  256-colour drivers. Its 8- and 16-colour files look as they do with the
  16-colour drivers.
* Memory bitmaps with 8 planes take twice the memory of 16-colour ones, and in
  real mode Windows 2 has little of it.

## Building

Needs Python 3 and NASM (https://www.nasm.us).

    cd src
    python build.py --nasm C:\path\to\nasm.exe --floppy ..\win2vbe.img

The script writes all 18 drivers, `VBELIST.COM` and `README.TXT` to
`src\drivers\` (`--only VBE1024P` builds just one). Each colour count is a
separate build of the same sources (`-DBPP=4 -DNPLANES=3` or `4`, or
`-DBPP=8`). It needs `IBMPS250.DRV`, `EGAHIRES.GRB` and `CGA.LGO` from the
Windows 2 setup files, and extracts them from `..\..\c_130_16_63_win203.img`
automatically (`--image` or `--template` override this). `mkne.py` is a small NE linker.
`mkfloppy.py` writes the FAT12 floppy image.

`bitblt.asm`, `color.asm`, `output.asm`, `pixel.asm`, `rop.asm`, `stubs.asm`
and `text.asm` are the same files as in the [Windows 3.0 driver](../win3vbe).
Switches in `defs.inc` select the Windows 2 behaviour (`FIXPAL`: fixed 256-colour
palette; 3.0 uses `PALMGR`, the palette manager).

Source files: `vbe.asm` (entry points), `enable.asm` (GDIINFO, Enable/Disable),
`screen.asm` (VESA/DISPI mode setting, banking, span access), `color.asm`
(ColorInfo, RealizeObject, dithering), `surf.asm` (screen/bitmap row access),
`rop.asm`, `bitblt.asm`, `output.asm`, `text.asm`, `pixel.asm`, `cursor.asm`,
`stubs.asm`, `data.asm`, plus `vbelist.asm` (the mode-listing tool).

Inspired by [John Elliott](https://www.seasip.info/DOS/Win1/win2vesa.html)'s `win2vesa` (VGA2VESA/EGA2VESA).
