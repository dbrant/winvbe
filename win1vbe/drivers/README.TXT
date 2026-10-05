VESA/VBE display drivers for Windows 1.0x
=========================================
Dmitry Brant, 2026
https://dmitrybrant.com

VBExxxx  = 8 colors  (like the Windows 1.0x EGA driver)
VBExxxxC = 16 colors
A 386 or later CPU is required.

Windows 1.0x SETUP builds the display driver into WIN100.BIN,
so the driver is installed with SETUP:

 1. Copy all files from the Windows 1.0x setup disks into one
    directory, e.g. C:\WINSETUP, and copy the driver's .DRV,
    .GRB and .LGO files from this disk there as well.
 2. In that directory run MKSETUP with the driver's name:
        MKSETUP VBE1024C
    This writes VBESETUP.EXE, a copy of SETUP.EXE whose
    "EGA (more than 64K)" entry installs the VBE driver.
 3. To update an existing Windows installation run
        VBESETUP /Q C:\WINDOWS USA.DRV MOUSE.DRV VBE1024C.DRV
    (with your keyboard and mouse drivers), or run VBESETUP
    for a new installation and choose "VESA/VBE display driver".

Requirements: a VESA BIOS (VBE 1.2+) that offers a banked
256-color mode at the chosen resolution, or the Bochs/QEMU
VBE adapter (QEMU -vga std).

VBELIST.COM lists the modes your video BIOS offers.
