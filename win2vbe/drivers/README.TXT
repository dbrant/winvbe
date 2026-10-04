VESA/VBE display drivers for Windows 2.x
=======================================
Dmitry Brant, 2026
https://dmitrybrant.com

VBExxxx  = 8 colours  (like the Windows 2.03 VGA driver)
VBExxxxC = 16 colours
VBExxxxP = 256 colours (fixed palette)

Install: run SETUP from the Windows setup files, choose
"Other (requires disk provided by a hardware manufacturer)"
for the display, enter A:\ (or the directory holding these
files) and pick a resolution.  SETUP replaces WIN.INI; to keep
your settings type  COPY /Y WIN.OLD WIN.INI  in C:\WINDOWS
afterwards.

Requirements: a VESA BIOS (VBE 1.2+) that offers a banked
256-colour mode at the chosen resolution, or the Bochs/QEMU
VBE adapter (QEMU -vga std).

VBELIST.COM lists the modes your video BIOS offers.
