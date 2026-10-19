@ Clamshell I/O test ROM, ARM9 side: a paint canvas on the bottom (touch) screen.
@ SPDX-License-Identifier: GPL-3.0-or-later
@
@ Engine A shows VRAM bank A on the bottom screen (dark grey); the ARM9 paints a white 3x3
@ dot wherever the ARM7 reports the pen. Engine B fills the top screen with green.
@ Writes 0xC1A55E11 to 0x02200000 once setup has finished.

    .syntax unified
    .arch armv5te
    .arm
    .text
    .global _start
_start:
    @ POWCNT1: LCDs and both 2D engines; bit 15 clear puts engine A on the bottom screen.
    ldr     r0, =0x04000304
    ldr     r1, =0x0203
    strh    r1, [r0]

    ldr     r0, =0x04000240         @ VRAMCNT_A: LCDC mode
    mov     r1, #0x80
    strb    r1, [r0]

    ldr     r0, =0x04000000         @ DISPCNT (A): VRAM display, bank A
    mov     r1, #0x00020000
    str     r1, [r0]

    ldr     r0, =0x04001000         @ DISPCNT (B): backdrop only
    mov     r1, #0x00010000
    str     r1, [r0]
    ldr     r0, =0x05000400         @ engine B backdrop = green
    ldr     r1, =0x03E0
    strh    r1, [r0]

    @ Clear the canvas to dark grey.
    ldr     r0, =0x06800000
    ldr     r1, =0x2108
    ldr     r2, =(256 * 192)
clear:
    strh    r1, [r0], #2
    subs    r2, r2, #1
    bne     clear

    ldr     r0, =0x02200000
    ldr     r1, =0xC1A55E11
    str     r1, [r0]

    ldr     r9, =0x02300000         @ ARM7 results
    ldr     r7, =0x06800000
    ldr     r6, =0x7FFF             @ white
loop:
    ldr     r0, [r9, #0x00]
    cmp     r0, #0
    beq     loop

    ldr     r1, [r9, #0x04]         @ x = clamp(rawX >> 4, 1, 254)
    mov     r1, r1, lsr #4
    cmp     r1, #1
    movlt   r1, #1
    cmp     r1, #254
    movgt   r1, #254
    ldr     r2, [r9, #0x08]         @ y = clamp(rawY >> 4, 1, 190)
    mov     r2, r2, lsr #4
    cmp     r2, #1
    movlt   r2, #1
    cmp     r2, #190
    movgt   r2, #190

    @ Paint the 3x3 block centred on (x, y).
    sub     r2, r2, #1
    mov     r3, #3                  @ rows
row:
    add     r4, r1, r2, lsl #8      @ y * 256 + x
    add     r4, r7, r4, lsl #1
    strh    r6, [r4, #-2]
    strh    r6, [r4]
    strh    r6, [r4, #2]
    add     r2, r2, #1
    subs    r3, r3, #1
    bne     row
    b       loop

    .pool
