VESA/VBE display drivers for Windows 3.0
=======================================
Dmitry Brant, 2026
https://dmitrybrant.com

Drivers for 800x600 up to 1920x1080, for real, standard and 386
enhanced mode.  A 386 or later CPU is required.

  VBExxxx   16 colors
  VBExxxxP  256 colors, with palette manager support
  VBExxxxH  HiColor, 32768 or 65536 colors (15/16 bpp mode)
  VBExxxxT  TrueColor, 16.7 million colors (32 bpp mode)

Install with Windows Setup: run SETUP in C:\WINDOWS from DOS,
select "Display", then "Other (requires disk provided by a
hardware manufacturer)", enter the drive or directory holding
these files (e.g. A:\) and pick a resolution and color depth.

Or by hand:
 1. Copy the driver you want (e.g. VBE1024P.DRV) into
    C:\WINDOWS\SYSTEM.
 2. In C:\WINDOWS\SYSTEM.INI, section [boot], set
        display.drv=vbe1024p.drv
    (keep the VGA grabbers, fonts and display=*vddvga lines).
 3. Start Windows.  If the video BIOS has no suitable mode at that
    resolution, a message on the text screen says so; set
    display.drv=vga.drv again from DOS.

Requirements: a VESA BIOS (VBE 1.2+) that offers a banked mode at
the chosen resolution: 8 bpp packed pixel for the 16- and 256-color
drivers, 15 or 16 bpp for HiColor, 32 bpp for TrueColor (cards with
only 24 bpp modes cannot use TrueColor).  The Bochs/QEMU VBE adapter
(QEMU -vga std) works too.

VBELIST.COM lists the modes your video BIOS offers.
