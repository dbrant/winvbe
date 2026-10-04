# VESA/VBE display driver for Windows 3.0 (800x600 up to 1920x1080)

Dmitry Brant, 2026.
https://dmitrybrant.com

Display driver for Windows 3.0 that runs Windows at 1024x768 and higher with 16
colours, in **real, standard and 386 enhanced mode**. It works on any video
adapter whose BIOS supports **VESA VBE 1.2 or later** and offers a banked
256-colour mode at the chosen resolution. It also works on QEMU's standard VGA
adapter.

Windows 3.0 shipped with drivers for VGA (640x480) and a handful of specific
Super VGA cards; there was no generic VESA driver. (Windows 3.1 has SVGA256 and,
more recently, VBESVGA.DRV; those do not load in 3.0.)

| Driver      | Resolution | Colours |
|-------------|------------|---------|
| VBE800.DRV  | 800x600    | 16      |
| VBE1024.DRV | 1024x768   | 16      |
| VBE1152.DRV | 1152x864   | 16      |
| VBE1280.DRV | 1280x1024  | 16      |
| VBE1600.DRV | 1600x1200  | 16      |
| VBE1920.DRV | 1920x1080  | 16      |

## Installing

The drivers are in `drivers\`, and `win3vbe.img` is a 1.44 MB floppy image with
the same files: the six drivers, an `OEMSETUP.INF` for Windows Setup,
`VBELIST.COM`, a short README, and the stock Windows 3.0 VGA companion files
that Setup installs with a display driver (the grabbers `VGACOLOR.GR2` and
`VGA.GR3`, the startup logo `VGALOGO.LGO`/`VGALOGO.RLE` and the fonts
`VGASYS.FON`, `VGAFIX.FON` and `VGAOEM.FON`).

**With Windows Setup:**

1. From DOS, run `SETUP` in `C:\WINDOWS`.
2. Select **Display**, then **Other (Requires disk provided by a hardware
   manufacturer)** at the end of the list.
3. Enter the path of the floppy (`A:\`) or of the `drivers` directory, and pick a
   resolution, e.g. *VESA/VBE 1024x768 (16 colors)*.
4. Choose **Accept the configuration shown above**.

**By hand:**

1. Copy the driver for the resolution you want (e.g. `VBE1024.DRV`) into
   `C:\WINDOWS\SYSTEM`.
2. In `C:\WINDOWS\SYSTEM.INI`, section `[boot]`, change the display driver:

       display.drv=vbe1024.drv

   Leave everything else as the VGA installation had it: the grabbers
   (`386grabber=vga.gr3`, `286grabber=vgacolor.gr2`), the fonts (`vgasys.fon`,
   `vgafix.fon`, `vgaoem.fon`) and `display=*vddvga` under `[386Enh]`.
3. Start Windows (`win`, `win /2` or `win /r`, as usual).

To go back, select VGA in Setup, or set `display.drv=vga.drv` again from DOS. If
the video BIOS has no 256-colour mode at the driver's resolution, Windows does
not start. Instead, a message on the text screen says so.

## Where it runs

At startup the driver asks the video BIOS (INT 10h, AX=4F00h/4F01h) for a
256-colour packed-pixel mode at its resolution and sets it with 4F02h. It
honours the card's window granularity and size, separate read/write windows
and scanline pitch. If the BIOS has no such mode, the driver falls back to the
Bochs/QEMU "DISPI" registers when they exist. QEMU uses this fallback for
1920x1080.

Tested on:

* QEMU `-vga std`: real, standard and enhanced mode at every resolution
  (SeaBIOS VBE up to 1600x1200, DISPI for 1920x1080);
* QEMU `-vga cirrus` (Cirrus VBE BIOS, 16 KB bank granularity);
* 86Box with the S3 Trio32 PCI (VBE 1.2, 2 MB): real, standard and enhanced mode
  at 1024x768 and 1280x1024, including DOS sessions.

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

## How it works

The drawing engine is the same as in the [Windows 2.x driver](../win2vbe):

* The screen is a **256-colour (8 bpp) banked frame buffer**. Towards GDI the
  device has **4 planes at 1 bpp**, the format of the VGA driver.
* A common row engine reads rows from the screen, colour or mono bitmaps into
  byte-per-pixel buffers, applies ROP3/ROP2 through a cached lookup table and
  writes them back. This covers BitBlt, FastBorder, Output (scan lines, styled
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
  (SetDIBitsToDevice) handle uncompressed 1, 4, 8 and 24 bpp DIBs, in both
  BITMAPINFO and BITMAPCOREHEADER form. Icons, cursors, wallpapers and
  Paintbrush BMP files all use these paths.
* Colour bitmaps store their planes **interleaved by scanline**, as Windows
  3.0 expects (Windows 2 used one plane after another).
* `UserRepaintDisable` and the INT 2Fh screen-switch protocol described above.
* Cursors, icons, system bitmaps and OEM resources are copied from the stock
  3.0 `VGA.DRV`, because USER loads them from the display driver.

## Tested

Program Manager, File Manager, Control Panel (colour schemes, desktop), Write
(Helv, Tms Rmn, Terminal, bold/italic/underline, large sizes), Paintbrush
(loading BMP files, and saving them as monochrome, 16-colour, 256-colour and
24-bit BMP and reloading), Solitaire, Reversi, Clock, Calculator, Cardfile,
wallpapers, full-screen and windowed DOS sessions, and exiting to DOS. See
`screenshots\`.

## Known limitations

* No hardware acceleration. On slow emulated CPUs, large redraws at high
  resolutions take a moment. In enhanced mode on real VESA hardware, every bank
  switch is an INT 10h call reflected to the BIOS.
* `SaveScreenBitmap` is not implemented, so USER redraws what menus and
  dialogs covered instead of restoring it from off-screen memory, as the stock
  driver does.
* 16 colours only. The 8-colour variants of the Windows 2 driver are not built
  for 3.0, since 3.0 applications expect the 16-colour VGA palette.

## Building

Needs Python 3 and NASM (https://www.nasm.us).

    cd src
    python build.py --nasm C:\path\to\nasm.exe --floppy ..\win3vbe.img

The script writes the six drivers, `OEMSETUP.INF`, `VBELIST.COM`, `README.TXT`
and the VGA companion files to `drivers\`.
It needs, in `src\`, the stock Windows 3.0 `VGA.DRV` (its resources are copied
into the drivers) and the VGA companion files listed above. `--debug 1` builds drivers
that log to the Bochs/QEMU debug port (0xE9).

Source files: `vbe.asm` (library init, includes), `enable.asm` (GDIINFO,
Enable/Disable, INT 2Fh switching, repaint), `screen.asm` (VESA/DISPI mode
setting through DPMI, banking, span access), `dib.asm` (DIB conversion),
`color.asm`, `surf.asm`, `rop.asm`, `bitblt.asm`, `output.asm`, `text.asm`,
`pixel.asm`, `cursor.asm`, `stubs.asm`, `data.asm`, `defs.inc` (structures,
prologue and import macros), `vbelist.asm`, and `mkne.py` (NE linker with
import relocations).
