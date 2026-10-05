# VESA/VBE display driver for Windows 3.0 (800x600 up to 1920x1080)

Dmitry Brant, 2026.
https://dmitrybrant.com

Display driver for Windows 3.0 that runs Windows at 1024x768 and higher with
16 colors, 256 colors (with the palette manager), HiColor or TrueColor, in
real, standard and 386 enhanced mode. It works on any video adapter whose
BIOS supports **VESA VBE 1.2 or later** and offers a banked mode of the right
depth at the chosen resolution. It also works on QEMU's standard VGA adapter.

Windows 3.0 shipped with drivers for VGA (640x480) and a handful of specific
Super VGA cards; there was no generic VESA driver. (Windows 3.1 has SVGA256 and,
more recently, VBESVGA.DRV; those do not load in 3.0.)

| Driver         | Colors                    | Video mode used |
|----------------|----------------------------|-----------------|
| `VBExxxx.DRV`  | 16                         | 8 bpp           |
| `VBExxxxP.DRV` | 256, palette manager       | 8 bpp           |
| `VBExxxxH.DRV` | HiColor: 65536 (or 32768)  | 16 (or 15) bpp  |
| `VBExxxxT.DRV` | TrueColor: 16.7 million    | 32 bpp          |

`xxxx` is the horizontal resolution: 800 (800x600), 1024 (1024x768), 1152
(1152x864), 1280 (1280x1024), 1600 (1600x1200) or 1920 (1920x1080), 24 drivers
in all.

Here is Windows 3.0 running in 1600x1200 resolution, with TrueColor:

![Screenshot](screenshots/win30_1600_16m.png)

## Installing

The drivers are in `drivers\`, and `win3vbe.img` is a 1.44 MB floppy image with
the same files: the 24 drivers, an `OEMSETUP.INF` for Windows Setup,
`VBELIST.COM`, a short README, and the stock Windows 3.0 VGA companion files
that Setup installs with a display driver (the grabbers `VGACOLOR.GR2` and
`VGA.GR3`, the startup logo `VGALOGO.LGO`/`VGALOGO.RLE` and the fonts
`VGASYS.FON`, `VGAFIX.FON` and `VGAOEM.FON`).

**With Windows Setup:**

1. From DOS, run `SETUP` in `C:\WINDOWS`.
2. Select **Display**, then **Other (Requires disk provided by a hardware
   manufacturer)** at the end of the list.
3. Enter the path of the floppy (`A:\`) or of the `drivers` directory, and pick a
   resolution and color depth, e.g. *VESA/VBE 1024x768 (256 colors)*.
4. Choose **Accept the configuration shown above**.

**By hand:**

1. Copy the driver you want (e.g. `VBE1024P.DRV`) into `C:\WINDOWS\SYSTEM`.
2. In `C:\WINDOWS\SYSTEM.INI`, section `[boot]`, change the display driver:

       display.drv=vbe1024p.drv

   Leave everything else as the VGA installation had it: the grabbers
   (`386grabber=vga.gr3`, `286grabber=vgacolor.gr2`), the fonts (`vgasys.fon`,
   `vgafix.fon`, `vgaoem.fon`) and `display=*vddvga` under `[386Enh]`.
3. Start Windows (`win`, `win /2` or `win /r`, as usual).

To go back, select VGA in Setup, or set `display.drv=vga.drv` again from DOS. If
the video BIOS has no suitable mode at the driver's resolution, Windows does
not start. Instead, a message on the text screen says so.

## Where it runs

At startup the driver asks the video BIOS (INT 10h, AX=4F00h/4F01h) for a mode
at its resolution and sets it with 4F02h:

* 16 and 256 colors: an 8 bpp packed-pixel mode;
* HiColor: a 16 bpp (5:6:5) direct-color mode, or a 15 bpp (5:5:5) one if the
  BIOS has no 16 bpp mode at that resolution. The layout is taken from the
  mode's bit count and green mask size;
* TrueColor: a 32 bpp direct-color mode with red, green and blue at bits 16, 8
  and 0. Cards whose true-color modes are 24 bpp (3 bytes per pixel) are not
  supported.

It honours the card's window granularity and size, separate read/write windows
and scanline pitch. If the BIOS has no such mode, the driver falls back to the
Bochs/QEMU "DISPI" registers when they exist. QEMU uses this fallback for
1920x1080.

Tested on:

* QEMU `-vga std`: real, standard and enhanced mode at every resolution
  (SeaBIOS VBE up to 1600x1200, DISPI for 1920x1080);
* QEMU `-vga cirrus` (Cirrus VBE BIOS, 16 KB bank granularity);
* 86Box with the S3 Trio32 PCI (VBE 1.2, 2 MB): real, standard and enhanced mode
  at 1024x768 and 1280x1024, including DOS sessions. Its BIOS has 8 bpp modes
  only;
* 86Box with the S3 Trio64 PCI (VBE 1.2, 4 MB): 256 colors, HiColor (in its
  15 bpp mode, before the driver preferred 16 bpp) and TrueColor at 1024x768.

Which resolutions a card supports is up to its BIOS. Run `VBELIST.COM` in DOS
to see the list. Cards without a VESA BIOS need a VBE TSR such as UniVBE
loaded before Windows.

## DOS sessions

* **Standard mode:** the task switcher calls the driver's Disable/Enable, and
  the stock `VGACOLOR.GR2` grabber saves and restores the DOS screen. Switching
  back and forth works as with the VGA driver.
* **386 enhanced mode:** full-screen and windowed DOS sessions work with the
  stock `*vddvga` device (tested on 86Box). The driver tells the VDD that it
  repaints its own screen (INT 2Fh 4000h). When Windows goes to the background
  (4001h), it stops drawing and puts the adapter back into standard text mode.
  This matters because VDDVGA restores only the standard VGA registers, so
  leftover SVGA state would blank the DOS screen. When Windows returns (4002h),
  the driver sets its mode again and asks USER to repaint everything.

Under QEMU, a full-screen DOS session's screen comes back garbled or blank
after a switch in enhanced mode, **with the stock VGA driver as well**. QEMU's
VGA emulation does not cooperate with VDDVGA's save/restore. Standard mode is
fine there.

## Color depths

* **16 colors** (`VBExxxx`): the screen is an 8 bpp banked frame buffer, but
  towards GDI the device has **4 planes at 1 bpp**, the format of the VGA
  driver. Colors are the 16 VGA colors; others are dithered.
* **256 colors** (`VBExxxxP`): a palette device (`RC_PALETTE`) with 20 static
  colors (the Windows 3.x system palette, at indices 0-9 and 246-255) and 236
  that applications set through palettes. The driver implements the palette
  functions: SetPalette and GetPalette (the hardware palette),
  SetPaletteTranslate and GetPaletteTranslate (the table that maps the
  foreground palette's indices to hardware indices) and UpdateColors (remapping
  the pixels of background windows). Pens, brushes, text and bitmaps copied
  from memory go through the translation. Bitmaps read back from the screen go
  through its inverse. RGB colors map to the nearest static color, or to a
  dither of them for brushes. As with the 3.1 drivers, DIB color tables arrive
  from GDI as palette indices.
* **HiColor** (`VBExxxxH`) and **TrueColor** (`VBExxxxT`): RGB colors are
  stored directly in the pixels, so pens, brushes and text are exact, and
  24 bpp DIBs (photos) keep all their colors. These two also implement
  **StretchBlt**. Without it, Windows 3.0's GDI stretches through 24 bpp DIBs
  and gets the rows wrong. (Paintbrush stretches its toolbox, which came out as
  noise.)

All four share one drawing engine, the one from the
[Windows 2.x driver](../win2vbe), generalised to 1, 2 or 4 bytes per pixel:

* A common row engine reads rows from the screen, color or mono bitmaps into
  pixel buffers, applies ROP3/ROP2 (through a cached lookup table for 16
  colors, bitwise for the others) and writes them back. This covers BitBlt, FastBorder, Output (scan lines, styled
  polylines), ExtTextOut/StrBlt (raster fonts), Pixel and ScanLR.
* The software 32x32 cursor is protected by a semaphore against interrupt-time
  MoveCursor calls. Redraws at interrupt time run on the driver's own stack
  with interrupts disabled, because the mouse and timer interrupts can call
  them on very small stacks and let mouse interrupts nest.

What is new for 3.0:

* **Protected mode.** The frame buffer is reached through KERNEL's `__A000H`
  selector (`__B000H` if the BIOS window is at B000). The NE file imports from
  KERNEL, and `mkne.py` emits the relocations. The exported functions use the
  standard `mov ax,ds / nop` prologue, which the loader patches to load the
  data segment. VBE calls that pass buffers (4F00h, 4F01h) go through DPMI
  "simulate real-mode interrupt" with a `GlobalDosAlloc` buffer. This works under
  WIN386 and under standard mode's DOSX. Banks are switched with INT 10h
  4F05h in protected mode, with the BIOS window function in real mode, or
  directly through the DISPI bank register on QEMU/Bochs.
* **GDIINFO version 3.0** and **device-independent bitmaps:**
  `DeviceBitmapBits` (SetDIBits/GetDIBits) and `DIBScreenBlt`
  (SetDIBitsToDevice) handle uncompressed 1, 4, 8 and 24 bpp DIBs at every
  color depth, in both
  BITMAPINFO and BITMAPCOREHEADER form. Icons, cursors, wallpapers and
  Paintbrush BMP files all use these paths.
* Color bitmaps store their planes **interleaved by scanline**, as Windows
  3.0 expects (Windows 2 used one plane after another).
* `UserRepaintDisable` and the INT 2Fh screen-switch protocol described above.
* Cursors, icons, system bitmaps and OEM resources are copied from the stock
  3.0 `VGA.DRV`, because USER loads them from the display driver.

## Tested

Program Manager, File Manager, Control Panel (color schemes, desktop), Write
(Helv, Tms Rmn, Terminal, bold/italic/underline, large sizes), Paintbrush
(loading BMP files, and saving them as monochrome, 16-color, 256-color and
24-bit BMP and reloading), Solitaire, Reversi, Clock, Calculator, Cardfile,
wallpapers, full-screen and windowed DOS sessions, and exiting to DOS. See
`screenshots\`.

At 256 colors, HiColor and TrueColor, the tests also covered: Paintbrush
drawing (filled shapes, lines, text) and a 24-bit BMP, and a palette test
program. That program realises a 256-entry logical palette and draws it with
`PALETTEINDEX` brushes, an 8 bpp DIB, a 24 bpp DIB and StretchDIBits. The tests
also covered full-screen DOS sessions in enhanced mode (the palette and the
screen come back) and standard and real mode.

## Known limitations

* No hardware acceleration. On slow emulated CPUs, large redraws at high
  resolutions take a moment. In enhanced mode on real VESA hardware, every bank
  switch is an INT 10h call reflected to the BIOS.
* `SaveScreenBitmap` is not implemented, so USER redraws what menus and
  dialogs covered instead of restoring it from off-screen memory, as the stock
  driver does.
* The 8-color variants of the Windows 2 driver are not built for 3.0, since
  3.0 applications expect the 16-color VGA palette.
* At HiColor and TrueColor, Program Manager and other applications show the
  **8-color versions of icons** (brighter, EGA-style art) instead of the
  16-color ones. This is Windows 3.0's USER, not the driver: it picks the
  icon image by comparing the color counts in the icon with
  `1 << (planes * bits per pixel)`, computed in 16 bits. At 16 bpp that is 0,
  and at 32 bpp it is 1 (the 386 masks the shift count), so the
  lowest-color image wins.
* Program Manager keeps a copy of each icon in its group files (`.GRP`) in
  the display's pixel format, and reuses it as long as the number of planes
  and bits per pixel match. It cannot tell a 5:5:5 HiColor display from a
  5:6:5 one, so icons saved in one show wrong colors in the other (white turns
  light cyan). This happens after running an older build of the HiColor
  drivers, which chose 5:5:5 modes at some resolutions. To refresh the icons,
  start Windows once with a driver of another color depth (for example the
  16-color one) and exit Windows; the next HiColor session saves fresh icons.
* No 24 bpp (3 bytes per pixel) modes; TrueColor needs a 32 bpp mode.
* The 256-color driver matches RGB colors (for example in 24 bpp DIBs) to the
  20 static colors, not to the whole hardware palette.

## Building

Needs Python 3 and NASM (https://www.nasm.us).

    cd src
    python build.py --nasm C:\path\to\nasm.exe --floppy ..\win3vbe.img

The script writes the 24 drivers, `OEMSETUP.INF`, `VBELIST.COM`, `README.TXT`
and the VGA companion files to `drivers\`. Each color depth is a separate
build of the same sources (`-DBPP=4`, `8`, `16` or `32`).
It needs, in `src\`, the stock Windows 3.0 `VGA.DRV` (its resources are copied
into the drivers) and the VGA companion files listed above. `--debug 1` builds drivers
that log to the Bochs/QEMU debug port (0xE9).

Source files: `vbe.asm` (library init, includes), `enable.asm` (GDIINFO,
Enable/Disable, INT 2Fh switching, repaint), `screen.asm` (VESA/DISPI mode
setting through DPMI, banking, span access), `dib.asm` (DIB conversion),
`palette.asm` (palette functions, 256 colors), `stretch.asm` (StretchBlt,
HiColor and TrueColor),
`color.asm`, `surf.asm`, `rop.asm`, `bitblt.asm`, `output.asm`, `text.asm`,
`pixel.asm`, `cursor.asm`, `stubs.asm`, `data.asm`, `defs.inc` (structures,
prologue and import macros), `vbelist.asm`, and `mkne.py` (NE linker with
import relocations).
