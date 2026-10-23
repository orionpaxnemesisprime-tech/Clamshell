@ Clamshell smoke-test ROM, ARM9 side.
@ SPDX-License-Identifier: GPL-3.0-or-later
@
@ Top screen (engine A, VRAM display mode): pixel i = (i & 0x7FFF) as BGR555, so pixel 31 is
@ pure red. Bottom screen (engine B): backdrop pure blue. Results for the host test:
@   0x02200000  0xC1A55E11 once setup has finished
@   0x02200004  latest KEYINPUT value (active-low)
@   0x02200008  main-loop iteration counter
@ Register references: GBATEK "DS Display Control", "DS Memory Control - VRAM",
@ "DS Power Control", "DS Keypad".

    .syntax unified
    .arch armv5te
    .arm
    .text
    .global _start
_start:
    @ POWCNT1: LCDs, 2D engine A, 2D engine B; bit 15 puts engine A on the top screen.
    ldr     r0, =0x04000304
    ldr     r1, =0x8203
    strh    r1, [r0]

    @ VRAMCNT_A: bank A enabled in LCDC mode (mapped at 0x06800000).
    ldr     r0, =0x04000240
    mov     r1, #0x80
    strb    r1, [r0]

    @ DISPCNT (A): display mode 2, show VRAM bank A directly.
    ldr     r0, =0x04000000
    mov     r1, #0x00020000
    str     r1, [r0]

    @ DISPCNT (B): normal display with no layers, so the backdrop colour fills the screen.
    ldr     r0, =0x04001000
    mov     r1, #0x00010000
    str     r1, [r0]

    @ Engine B palette entry 0 (backdrop) = blue.
    ldr     r0, =0x05000400
    ldr     r1, =0x7C00
    strh    r1, [r0]

    @ Fill the top screen.
    ldr     r0, =0x06800000
    mov     r1, #0
    ldr     r2, =(256 * 192)
    ldr     r3, =0x7FFF
fill:
    and     r4, r1, r3
    strh    r4, [r0], #2
    add     r1, r1, #1
    cmp     r1, r2
    blo     fill

    @ Setup finished.
    ldr     r5, =0x02200000
    ldr     r1, =0xC1A55E11
    str     r1, [r5]

    @ Echo KEYINPUT and count iterations forever.
    ldr     r0, =0x04000130
    mov     r6, #0
loop:
    ldrh    r1, [r0]
    str     r1, [r5, #4]
    add     r6, r6, #1
    str     r6, [r5, #8]
    b       loop

    .pool
