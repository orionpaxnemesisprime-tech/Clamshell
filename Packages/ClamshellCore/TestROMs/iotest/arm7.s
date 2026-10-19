@ Clamshell I/O test ROM, ARM7 side: touchscreen, sound and microphone.
@ SPDX-License-Identifier: GPL-3.0-or-later
@
@ Shared results in main RAM (base 0x02300000):
@   +0x00  1 while the pen is down, else 0
@   +0x04  last raw touch X (12-bit ADC value)
@   +0x08  last raw touch Y (12-bit ADC value)
@   +0x0C  last 12-bit microphone sample (sampled only while X is held)
@   +0x10  number of microphone samples taken
@   +0x14  ARM7 loop counter
@   +0x18  1 while the lid (hinge) is closed, else 0
@ A 440 Hz square wave plays on sound channel 8 while the pen is down.
@ Note: raw-to-pixel conversion normally uses the firmware's calibration data; tests and the
@ ARM9 side rely on melonDS's raw = pixel << 4 mapping.
@ References: GBATEK "DS Touch Screen Controller (TSC)", "DS Serial Peripheral Interface
@ Bus (SPI)", "DS Sound Channels", "DS Keypad" (EXTKEYIN).

    .syntax unified
    .arch armv4t
    .arm
    .text
    .global _start
_start:
    ldr     r9, =0x02300000
    mov     r8, #0                  @ previous pen state
    mov     r10, #0                 @ mic sample count
    mov     r11, #0                 @ loop counter

    @ POWCNT2 (ARM7): speakers on.
    ldr     r0, =0x04000304
    mov     r1, #1
    strh    r1, [r0]

    @ SOUNDCNT: master enable, master volume 127.
    ldr     r0, =0x04000500
    ldr     r1, =0x807F
    strh    r1, [r0]

loop:
    ldr     r0, =0x04000136         @ EXTKEYIN (active-low)
    ldrh    r4, [r0]
    mov     r0, r4, lsr #7          @ bit 7: hinge closed when set
    and     r0, r0, #1
    str     r0, [r9, #0x18]

    tst     r4, #0x40               @ bit 6: pen down when clear
    bne     pen_up

    mov     r0, #0xD0               @ TSC: measure X, 12-bit
    mov     lr, pc                  @ call without a relocation: lr = return address
    b       tsc_read
    str     r0, [r9, #0x04]
    mov     r0, #0x90               @ TSC: measure Y, 12-bit
    mov     lr, pc                  @ call without a relocation: lr = return address
    b       tsc_read
    str     r0, [r9, #0x08]
    mov     r0, #1
    str     r0, [r9, #0x00]

    cmp     r8, #0
    bne     mic
    mov     r8, #1
    @ Channel 8 (PSG): timer for 440 Hz = 16756991 / 8 / 440 ~= 4760, then start.
    ldr     r0, =0x04000488         @ SOUND8TMR
    ldr     r1, =(0x10000 - 4760)
    strh    r1, [r0]
    ldr     r0, =0x04000480         @ SOUND8CNT
    ldr     r1, =0xE340007F         @ start | PSG | 50% duty | pan 64 | volume 127
    str     r1, [r0]
    b       mic

pen_up:
    mov     r0, #0
    str     r0, [r9, #0x00]
    cmp     r8, #0
    beq     mic
    mov     r8, #0
    ldr     r0, =0x04000480         @ SOUND8CNT: stop
    mov     r1, #0
    str     r1, [r0]

mic:
    tst     r4, #0x01               @ bit 0: X held when clear
    bne     next
    mov     r0, #0xE4               @ TSC: microphone (AUX channel 6), 12-bit
    mov     lr, pc                  @ call without a relocation: lr = return address
    b       tsc_read
    str     r0, [r9, #0x0C]
    add     r10, r10, #1
    str     r10, [r9, #0x10]

next:
    add     r11, r11, #1
    str     r11, [r9, #0x14]
    b       loop

@ r0 = TSC control byte; returns the 12-bit conversion in r0. Clobbers r2, r3, r12.
tsc_read:
    ldr     r2, =0x040001C0         @ SPICNT; SPIDATA at +2
    ldr     r3, =0x8A01             @ enable | hold chip select | touchscreen | 2 MHz
    strh    r3, [r2]
    strh    r0, [r2, #2]
1:  ldrh    r3, [r2]
    tst     r3, #0x80
    bne     1b
    mov     r3, #0
    strh    r3, [r2, #2]
2:  ldrh    r3, [r2]
    tst     r3, #0x80
    bne     2b
    ldrh    r0, [r2, #2]
    and     r0, r0, #0xFF
    ldr     r3, =0x8201             @ last byte: release chip select
    strh    r3, [r2]
    mov     r3, #0
    strh    r3, [r2, #2]
3:  ldrh    r3, [r2]
    tst     r3, #0x80
    bne     3b
    ldrh    r12, [r2, #2]
    and     r12, r12, #0xFF
    orr     r0, r12, r0, lsl #8
    mov     r0, r0, lsr #3
    bx      lr

    .pool
