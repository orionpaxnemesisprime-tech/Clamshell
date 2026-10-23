@ Clamshell smoke-test ROM, ARM7 side: idle forever.
@ SPDX-License-Identifier: GPL-3.0-or-later

    .syntax unified
    .arch armv4t
    .arm
    .text
    .global _start
_start:
idle:
    b       idle
