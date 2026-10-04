VESA/VBE display drivers for Windows 3.0
=======================================
Dmitry Brant, 2026
https://dmitrybrant.com

16-colour drivers for 800x600 up to 1920x1080, for real, standard
and 386 enhanced mode.  A 386 or later CPU is required.

Install with Windows Setup: run SETUP in C:\WINDOWS from DOS,
select "Display", then "Other (requires disk provided by a
hardware manufacturer)", enter the drive or directory holding
these files (e.g. A:\) and pick a resolution.

Or by hand:
 1. Copy the VBExxxx.DRV file for the resolution you want into
    C:\WINDOWS\SYSTEM.
 2. In C:\WINDOWS\SYSTEM.INI, section [boot], set
        display.drv=vbe1024.drv
    (keep the VGA grabbers, fonts and display=*vddvga lines).
 3. Start Windows.  If the video BIOS has no 256-colour mode at that
    resolution, a message on the text screen says so; set
    display.drv=vga.drv again from DOS.

Requirements: a VESA BIOS (VBE 1.2+) that offers a banked 256-colour
mode at the chosen resolution, or the Bochs/QEMU VBE adapter
(QEMU -vga std).

VBELIST.COM lists the modes your video BIOS offers.
