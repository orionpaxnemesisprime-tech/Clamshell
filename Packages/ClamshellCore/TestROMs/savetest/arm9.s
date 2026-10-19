@ Clamshell save test ROM, ARM9 side: a boot counter in the cartridge EEPROM.
@ SPDX-License-Identifier: GPL-3.0-or-later
@
@ Build as a cartridge image so melonDS gives it a 64 Kbit EEPROM:
@   Scripts/make-test-rom.py <dir> savetest.nds --game-code ZCLS --arm9-offset 0x8000
@
@ At boot: read EEPROM byte 0 (0xFF = blank -> 0), store it at 0x02200010, then write
@ (value + 1) back and signal 0xC1A55E11 at 0x02200000.
@ References: GBATEK "DS Cartridge Backup" and "DS Cartridge I/O Ports" (AUXSPICNT,
@ AUXSPIDATA), "DS Memory Control" (EXMEMCNT).

    .syntax unified
    .arch armv5te
    .arm
    .text
    .global _start
_start:
    ldr     r9, =0x02200000

    @ EXMEMCNT bit 11 = 0: the NDS slot belongs to the ARM9.
    ldr     r0, =0x04000204
    ldrh    r1, [r0]
    bic     r1, r1, #0x800
    strh    r1, [r0]

    ldr     r8, =0x040001A0         @ AUXSPICNT; AUXSPIDATA at +2
    ldr     r10, =0xA040            @ slot enable | SPI mode | hold chip select
    ldr     r11, =0xA000            @ same, releasing chip select after the byte

    @ READ byte 0: 03 00 00 <data>
    strh    r10, [r8]
    mov     r0, #0x03
    mov     lr, pc
    b       xfer
    mov     r0, #0
    mov     lr, pc
    b       xfer
    mov     r0, #0
    mov     lr, pc
    b       xfer
    strh    r11, [r8]
    mov     r0, #0
    mov     lr, pc
    b       xfer
    cmp     r0, #0xFF
    moveq   r0, #0
    mov     r7, r0
    str     r7, [r9, #0x10]

    @ WREN
    strh    r11, [r8]
    mov     r0, #0x06
    mov     lr, pc
    b       xfer

    @ WRITE byte 0: 02 00 00 <count + 1>
    strh    r10, [r8]
    mov     r0, #0x02
    mov     lr, pc
    b       xfer
    mov     r0, #0
    mov     lr, pc
    b       xfer
    mov     r0, #0
    mov     lr, pc
    b       xfer
    strh    r11, [r8]
    add     r0, r7, #1
    and     r0, r0, #0xFF
    mov     lr, pc
    b       xfer

    ldr     r1, =0xC1A55E11
    str     r1, [r9]
idle:
    b       idle

@ r0 = byte to send; returns the received byte in r0. Clobbers r2.
xfer:
    strh    r0, [r8, #2]
1:  ldrh    r2, [r8]
    tst     r2, #0x80
    bne     1b
    ldrh    r0, [r8, #2]
    and     r0, r0, #0xFF
    bx      lr

    .pool
