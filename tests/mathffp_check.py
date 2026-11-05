#!/usr/bin/env python3
"""tests/mathffp_check.py - case table, expected results and arithmetic model of tests/mathffp_probe.s.

Spec: docs/analysis/mathffp-v34.md (mathffp.library 34.1): the 202 test vectors of §7, the register/stack/A6/CCR
checks and the library vectors of §8.
  mathffp_check.py gen <file.i>      writes the case table included by the probe
  mathffp_check.py check <log.txt>   compares the probe output with the spec, one PASS/FAIL line per check
  mathffp_check.py model             checks the arithmetic model below against the 202 vectors (no emulator)

The model restates the rules of spec §4 as plain arithmetic, for self-checking this table and for random
cross-checks of an implementation; the vectors stay the authority.
SPCmp: only Z and the signed relation are part of the contract (spec §3.3); N and V alone are not compared.
"""
import sys

FIX, FLT, CMP, TST, ABS, NEG, ADD, SUB, MUL, DIV, FLOOR, CEIL = range(-30, -97, -6)
NAMES = {FIX: 'SPFix', FLT: 'SPFlt', CMP: 'SPCmp', TST: 'SPTst', ABS: 'SPAbs', NEG: 'SPNeg', ADD: 'SPAdd',
         SUB: 'SPSub', MUL: 'SPMul', DIV: 'SPDiv', FLOOR: 'SPFloor', CEIL: 'SPCeil'}
D1_KEPT = (ABS, NEG, ADD, SUB, MUL, DIV)       # spec §3.2: these leave D1 intact
STACK_MAX = 32                                 # spec §0: at most 32 bytes, return address included
TRAP = 'TRAP'

# (id, LVO, D0 in, D1 in, D0 out or TRAP, flags among N Z V) - spec §7, V1..V12
VECTORS = [
    ('X1', -30, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('X2', -30, 0x00000080, 0x00000000, 0x00000000, 'Z'),
    ('X3', -30, 0x80000041, 0x00000000, 0x00000001, ''),
    ('X4', -30, 0x800000C1, 0x00000000, 0xFFFFFFFF, 'N'),
    ('X5', -30, 0xC0000041, 0x00000000, 0x00000001, ''),
    ('X6', -30, 0xC00000C1, 0x00000000, 0xFFFFFFFF, 'N'),
    ('X7', -30, 0xA0000042, 0x00000000, 0x00000002, ''),
    ('X8', -30, 0xA00000C2, 0x00000000, 0xFFFFFFFE, 'N'),
    ('X9', -30, 0xFFFFFF40, 0x00000000, 0x00000000, 'Z'),
    ('X10', -30, 0x80000040, 0x00000000, 0x00000000, 'Z'),
    ('X11', -30, 0xFFFFFF58, 0x00000000, 0x00FFFFFF, ''),
    ('X12', -30, 0xFFFFFF5F, 0x00000000, 0x7FFFFF80, ''),
    ('X13', -30, 0xFFFFFFDF, 0x00000000, 0x80000080, 'N'),
    ('X14', -30, 0x800000E0, 0x00000000, 0x80000000, 'N'),
    ('X15', -30, 0x80000060, 0x00000000, 0x7FFFFFFF, 'V'),
    ('X16', -30, 0x800001E0, 0x00000000, 0x80000000, 'ZV'),
    ('X17', -30, 0xFFFFFF7F, 0x00000000, 0x7FFFFFFF, 'V'),
    ('X18', -30, 0xFFFFFFFF, 0x00000000, 0x80000000, 'ZV'),
    ('X19', -30, 0x80000001, 0x00000000, 0x00000000, 'Z'),
    ('X20', -30, 0x80000000, 0x00000000, 0x80000000, 'Z'),
    ('X21', -30, 0x12345600, 0x00000000, 0x12345600, 'Z'),
    ('X22', -30, 0x00000041, 0x00000000, 0x00000000, 'Z'),
    ('X23', -30, 0x000000E0, 0x00000000, 0x80000000, 'ZV'),
    ('X24', -30, 0x40000060, 0x00000000, 0x7FFFFFFF, 'V'),
    ('X25', -30, 0x7FFFFFE0, 0x00000000, 0x80000100, 'N'),
    ('L1', -36, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('L2', -36, 0x00000001, 0x00000000, 0x80000041, ''),
    ('L3', -36, 0xFFFFFFFF, 0x00000000, 0x800000C1, 'N'),
    ('L4', -36, 0x00000003, 0x00000000, 0xC0000042, ''),
    ('L5', -36, 0x00000007, 0x00000000, 0xE0000043, ''),
    ('L6', -36, 0x00000064, 0x00000000, 0xC8000047, ''),
    ('L7', -36, 0xFFFFFF01, 0x00000000, 0xFF0000C8, 'N'),
    ('L8', -36, 0x00FFFFFF, 0x00000000, 0xFFFFFF58, ''),
    ('L9', -36, 0x01000000, 0x00000000, 0x80000059, ''),
    ('L10', -36, 0x01000001, 0x00000000, 0x80000159, ''),
    ('L11', -36, 0x01000002, 0x00000000, 0x80000159, ''),
    ('L12', -36, 0x01000003, 0x00000000, 0x80000259, ''),
    ('L13', -36, 0xFEFFFFFF, 0x00000000, 0x800001D9, 'N'),
    ('L14', -36, 0x02000002, 0x00000000, 0x8000015A, ''),
    ('L15', -36, 0x02000006, 0x00000000, 0x8000025A, ''),
    ('L16', -36, 0x7FFFFFFF, 0x00000000, 0x80000060, ''),
    ('L17', -36, 0x80000000, 0x00000000, 0x800000E0, 'N'),
    ('L18', -36, 0x80000001, 0x00000000, 0x800000E0, 'N'),
    ('L19', -36, 0x7FFFFFBF, 0x00000000, 0xFFFFFF5F, ''),
    ('L20', -36, 0x7FFFFFC0, 0x00000000, 0x80000060, ''),
    ('L21', -36, 0x12345678, 0x00000000, 0x91A2B45D, ''),
    ('C1', -42, 0x00000000, 0x80000041, 0x00000001, 'N'),
    ('C2', -42, 0x80000041, 0x00000000, 0xFFFFFFFF, ''),
    ('C3', -42, 0x80000041, 0x80000041, 0x00000000, 'Z'),
    ('C4', -42, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('C5', -42, 0x80000041, 0x800000C1, 0xFFFFFFFF, 'NV'),
    ('C6', -42, 0x800000C1, 0x80000041, 0x00000001, 'N'),
    ('C7', -42, 0x800000C2, 0x800000C1, 0x00000001, 'N'),
    ('C8', -42, 0x800000C1, 0x800000C2, 0xFFFFFFFF, ''),
    ('C9', -42, 0x80000141, 0x80000041, 0xFFFFFFFF, ''),
    ('C10', -42, 0xFFFFFFFF, 0xFFFFFF7F, 0x00000001, 'N'),
    ('C11', -42, 0x00000080, 0x00000000, 0x00000001, 'N'),
    ('C12', -42, 0x00000000, 0x00000080, 0xFFFFFFFF, 'NV'),
    ('C13', -42, 0x00000000, 0x80000000, 0xFFFFFFFF, 'NV'),
    ('C14', -42, 0x80000000, 0x00000000, 0x00000001, 'N'),
    ('C15', -42, 0x80000080, 0x00000080, 0xFFFFFFFF, 'NV'),
    ('C16', -42, 0x80000042, 0x40000042, 0x00000001, 'V'),
    ('C17', -42, 0x80000041, 0x00000041, 0x00000001, 'N'),
    ('T1', -48, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('T2', -48, 0x00000000, 0x00000080, 0xFFFFFFFF, 'N'),
    ('T3', -48, 0x00000000, 0x80000041, 0x00000001, ''),
    ('T4', -48, 0x00000000, 0x800000C1, 0xFFFFFFFF, 'N'),
    ('T5', -48, 0x00000000, 0x80000000, 0x00000000, 'Z'),
    ('T6', -48, 0x00000000, 0x12345600, 0x00000000, 'Z'),
    ('T7', -48, 0x00000000, 0x00000041, 0x00000001, ''),
    ('T8', -48, 0x00000000, 0x000000C1, 0xFFFFFFFF, 'N'),
    ('T9', -48, 0x00000000, 0xFFFFFF7F, 0x00000001, ''),
    ('T10', -48, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 'N'),
    ('A1', -54, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('A2', -54, 0x00000080, 0x00000000, 0x00000000, 'Z'),
    ('A3', -54, 0x800000C1, 0x00000000, 0x80000041, ''),
    ('A4', -54, 0x80000041, 0x00000000, 0x80000041, ''),
    ('A5', -54, 0xFFFFFFFF, 0x00000000, 0xFFFFFF7F, ''),
    ('A6', -54, 0x80000080, 0x00000000, 0x80000000, 'Z'),
    ('A7', -54, 0x000000C1, 0x00000000, 0x00000041, ''),
    ('A8', -54, 0x12345680, 0x00000000, 0x12345600, 'Z'),
    ('N1', -60, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('N2', -60, 0x00000080, 0x00000000, 0x00000000, 'Z'),
    ('N3', -60, 0x80000041, 0x00000000, 0x800000C1, 'N'),
    ('N4', -60, 0x800000C1, 0x00000000, 0x80000041, ''),
    ('N5', -60, 0xFFFFFF7F, 0x00000000, 0xFFFFFFFF, 'N'),
    ('N6', -60, 0x80000000, 0x00000000, 0x80000000, 'Z'),
    ('N7', -60, 0x80000080, 0x00000000, 0x80000000, 'Z'),
    ('N8', -60, 0x00000041, 0x00000000, 0x000000C1, 'N'),
    ('N9', -60, 0x12345600, 0x00000000, 0x12345600, 'Z'),
    ('D1', -66, 0x80000041, 0x80000041, 0x80000042, ''),
    ('D2', -66, 0x80000042, 0x80000041, 0xC0000042, ''),
    ('D3', -66, 0xC0000041, 0xC0000041, 0xC0000042, ''),
    ('D4', -66, 0x800000C1, 0x80000041, 0x00000000, 'Z'),
    ('D5', -66, 0x80000041, 0x80000141, 0x80000042, ''),
    ('D6', -66, 0x80000042, 0x80000141, 0xC0000142, ''),
    ('D7', -66, 0xC0000041, 0x80000141, 0xA0000042, ''),
    ('D8', -66, 0x80000041, 0x80000028, 0x80000041, ''),
    ('D9', -66, 0x80000041, 0xC0000029, 0x80000041, ''),
    ('D10', -66, 0x80000041, 0x800000A8, 0x80000041, ''),
    ('D11', -66, 0x80000041, 0x80000027, 0x80000041, ''),
    ('D12', -66, 0x80000141, 0x80000028, 0x80000141, ''),
    ('D13', -66, 0x80000141, 0x800000A8, 0x80000141, ''),
    ('D14', -66, 0x80000041, 0xFFFFFFC0, 0x8000002A, ''),
    ('D15', -66, 0xFFFFFF7F, 0x80000068, 0xFFFFFF7F, 'V'),
    ('D16', -66, 0x80000041, 0x80000029, 0x80000041, ''),
    ('D17', -66, 0x80000141, 0x80000029, 0x80000141, ''),
    ('D18', -66, 0xFFFFFF7F, 0xFFFFFF7F, 0xFFFFFF7F, 'V'),
    ('D19', -66, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 'NV'),
    ('D20', -66, 0x80000101, 0x80000081, 0x00000000, 'Z'),
    ('D21', -66, 0x80000041, 0x00000000, 0x80000041, ''),
    ('D22', -66, 0x00000000, 0x80000041, 0x80000041, ''),
    ('D23', -66, 0x00000000, 0x00000080, 0x00000080, 'N'),
    ('D24', -66, 0x80000041, 0x80000000, 0x80000041, ''),
    ('D25', -66, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('S1', -72, 0x80000042, 0x80000041, 0x80000041, ''),
    ('S2', -72, 0x80000041, 0x80000042, 0x800000C1, 'N'),
    ('S3', -72, 0x80000041, 0x80000041, 0x00000000, 'Z'),
    ('S4', -72, 0x80000042, 0x80000141, 0x80000041, ''),
    ('S5', -72, 0xC0000042, 0x80000141, 0x80000042, ''),
    ('S6', -72, 0x80000141, 0x80000042, 0x800000C1, 'N'),
    ('S7', -72, 0xFFFFFFFF, 0xFFFFFF7F, 0xFFFFFFFF, 'NV'),
    ('S8', -72, 0x00000000, 0x80000041, 0x800000C1, 'N'),
    ('S9', -72, 0x80000041, 0x00000000, 0x80000041, ''),
    ('S10', -72, 0x00000000, 0x00000080, 0x00000000, 'Z'),
    ('S11', -72, 0x80000041, 0x800000A9, 0x80000041, ''),
    ('M1', -78, 0xC0000041, 0xC0000041, 0x90000042, ''),
    ('M2', -78, 0xC0000042, 0xC0000042, 0x90000044, ''),
    ('M3', -78, 0x800000C1, 0x80000042, 0x800000C2, 'N'),
    ('M4', -78, 0xC0000041, 0x00000000, 0x00000000, 'Z'),
    ('M5', -78, 0x00000000, 0xC0000041, 0x00000000, 'Z'),
    ('M6', -78, 0x80000041, 0x80000000, 0x00000000, 'Z'),
    ('M7', -78, 0x80000000, 0x80000041, 0x80000000, 'Z'),
    ('M8', -78, 0x00000080, 0x80000042, 0x00000081, 'N'),
    ('M9', -78, 0x800400C9, 0x881000BD, 0x88144145, ''),
    ('M10', -78, 0xC84000CE, 0x900100B2, 0xE149913F, ''),
    ('M11', -78, 0xFFFFFF7F, 0x80000041, 0xFFFFFF7F, 'V'),
    ('M12', -78, 0xFFFFFF7F, 0x80000040, 0xFFFFFF7E, ''),
    ('M13', -78, 0x80000060, 0x80000060, 0xFFFFFF7F, 'V'),
    ('M14', -78, 0xB504F3D0, 0x800000F0, 0xFFFFFF7F, 'V'),
    ('M15', -78, 0x80000020, 0x80000021, 0x00000000, 'Z'),
    ('M16', -78, 0xB504F389, 0x80000138, 0xB504F480, 'N'),
    ('M17', -78, 0xB504F483, 0xC00000BD, 0x00000000, 'Z'),
    ('M18', -78, 0xC0000020, 0xC00000A0, 0x90000080, 'N'),
    ('V1', -84, 0x80000041, 0xC0000042, 0xAAAAAB3F, ''),
    ('V2', -84, 0x80000041, 0x80000042, 0x80000040, ''),
    ('V3', -84, 0x80000041, 0xC0000041, 0xAAAAAB40, ''),
    ('V4', -84, 0x00000000, 0x80000041, 0x00000000, 'Z'),
    ('V5', -84, 0x80000041, 0x00000000, TRAP, ''),
    ('V6', -84, 0x80000041, 0x00000080, 0xFFFFFFFF, 'NV'),
    ('V7', -84, 0x00000000, 0x00000080, 0x00000000, 'Z'),
    ('V8', -84, 0x80000041, 0x00000041, TRAP, ''),
    ('V9', -84, 0x80000041, 0x80000000, TRAP, ''),
    ('V10', -84, 0x80000041, 0xFFFFFF7F, 0x80000102, ''),
    ('V11', -84, 0xFFFFFF7F, 0x80000040, 0xFFFFFF7F, 'V'),
    ('V12', -84, 0xFFFFFFFF, 0x80000040, 0xFFFFFF7F, 'V'),
    ('V13', -84, 0xFFFFFFFF, 0x800000C0, 0xFFFFFFFF, 'NV'),
    ('V14', -84, 0x80000041, 0x80000080, 0xFFFFFFFF, 'NV'),
    ('V15', -84, 0x80000001, 0x80000042, 0x00000000, 'Z'),
    ('V16', -84, 0x80000001, 0xFFFFFFC1, 0x80000180, 'N'),
    ('V17', -84, 0x80000001, 0xFFFFFF41, 0x00000000, 'Z'),
    ('V18', -84, 0x80000000, 0x80000040, 0x80000001, ''),
    ('V19', -84, 0xEC30A533, 0xF7698CBF, 0xF46361B4, 'N'),
    ('V20', -84, 0x80000041, 0x40000041, 0x00000040, ''),
    ('F1', -90, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('F2', -90, 0x00000080, 0x00000000, 0x00000000, 'Z'),
    ('F3', -90, 0x80000041, 0x00000000, 0x80000041, ''),
    ('F4', -90, 0x800000C1, 0x00000000, 0x800000C1, 'N'),
    ('F5', -90, 0xC0000041, 0x00000000, 0x80000041, ''),
    ('F6', -90, 0xC00000C1, 0x00000000, 0x800000C2, 'N'),
    ('F7', -90, 0xA0000042, 0x00000000, 0x80000042, ''),
    ('F8', -90, 0xA00000C2, 0x00000000, 0xC00000C2, 'N'),
    ('F9', -90, 0x80000040, 0x00000000, 0x00000000, 'Z'),
    ('F10', -90, 0x800000C0, 0x00000000, 0x800000C1, 'N'),
    ('F11', -90, 0xFFFFFF41, 0x00000000, 0x80000041, ''),
    ('F12', -90, 0x80000001, 0x00000000, 0x00000000, 'Z'),
    ('F13', -90, 0x80000081, 0x00000000, 0x800000C1, 'N'),
    ('F14', -90, 0xFFFFFF58, 0x00000000, 0xFFFFFF58, ''),
    ('F15', -90, 0xFFFFFFD8, 0x00000000, 0xFFFFFFD8, 'N'),
    ('F16', -90, 0xFFFFFF7F, 0x00000000, 0xFFFFFF7F, ''),
    ('F17', -90, 0x80000080, 0x00000000, 0x80000000, 'Z'),
    ('F18', -90, 0x40000041, 0x00000000, 0x00000041, ''),
    ('F19', -90, 0x00000001, 0x00000000, 0x00000000, 'Z'),
    ('E1', -96, 0x00000000, 0x00000000, 0x00000000, 'Z'),
    ('E2', -96, 0x00000080, 0x00000000, 0x00000000, 'Z'),
    ('E3', -96, 0x80000041, 0x00000000, 0x80000041, ''),
    ('E4', -96, 0x800000C1, 0x00000000, 0x800000C1, 'N'),
    ('E5', -96, 0xC0000041, 0x00000000, 0x80000042, ''),
    ('E6', -96, 0xC00000C1, 0x00000000, 0x800000C1, 'N'),
    ('E7', -96, 0xA0000042, 0x00000000, 0xC0000042, ''),
    ('E8', -96, 0xA00000C2, 0x00000000, 0x800000C2, 'N'),
    ('E9', -96, 0x80000040, 0x00000000, 0x80000041, ''),
    ('E10', -96, 0x800000C0, 0x00000000, 0x00000000, 'Z'),
    ('E11', -96, 0xFFFFFF41, 0x00000000, 0x80000042, ''),
    ('E12', -96, 0x80000001, 0x00000000, 0x80000041, ''),
    ('E13', -96, 0x80000081, 0x00000000, 0x00000000, 'Z'),
    ('E14', -96, 0xFFFFFF58, 0x00000000, 0xFFFFFF58, ''),
    ('E15', -96, 0xFFFFFFD8, 0x00000000, 0xFFFFFFD8, 'N'),
    ('E16', -96, 0xFFFFFF7F, 0x00000000, 0xFFFFFF7F, ''),
    ('E17', -96, 0x80000080, 0x00000000, 0x80000000, 'Z'),
    ('E18', -96, 0x40000041, 0x00000000, 0x80000041, ''),
    ('E19', -96, 0x00000001, 0x00000000, 0x80000041, ''),
]
VEC = {v[0]: v for v in VECTORS}

# R1 (spec §7 V13): one call per function with A6 = 0 -> (id, LVO, D0, D1, result)
A6ZERO = [
    ('R1fix', FIX, 0xC0000042, 0, 3), ('R1flt', FLT, 7, 0, 0xE0000043),
    ('R1cmp', CMP, 0x80000041, 0x80000042, 1), ('R1tst', TST, 0, 0x800000C1, 0xFFFFFFFF),
    ('R1abs', ABS, 0x800000C1, 0, 0x80000041), ('R1neg', NEG, 0x80000041, 0, 0x800000C1),
    ('R1add', ADD, 0x80000041, 0x80000042, 0xC0000042), ('R1sub', SUB, 0x80000041, 0x80000042, 0x800000C1),
    ('R1mul', MUL, 0xC0000042, 0x80000042, 0xC0000043), ('R1div', DIV, 0x80000041, 0xC0000042, 0xAAAAAB3F),
    ('R1floor', FLOOR, 0xC00000C1, 0, 0x800000C2), ('R1ceil', CEIL, 0xC00000C1, 0, 0x800000C1),
]
STACKV = ['X13', 'L21', 'C9', 'T4', 'A3', 'N3', 'D14', 'S4', 'M9', 'V19', 'F8', 'E7']   # one per function (§8.5)
CCRV = ['X16', 'L13', 'C5', 'T2', 'N7', 'D6', 'S4', 'M10', 'V1', 'E13']               # entry CCR $1F (§8.7)

K_PLAIN, K_STACK, K_A6Z, K_CCR, K_TRAP = range(5)


def cases():
    out = []
    for v in VECTORS:
        out.append((v[0], K_TRAP if v[4] == TRAP else K_PLAIN, v[1], v[2], v[3]))
    out.append(('V5b 0/0', K_TRAP, DIV, 0, 0))
    for vid in STACKV:
        v = VEC[vid]
        out.append((vid + ' stack', K_STACK, v[1], v[2], v[3]))
    for r in A6ZERO:
        out.append((r[0], K_A6Z, r[1], r[2], r[3]))
    for vid in CCRV:
        v = VEC[vid]
        out.append((vid + ' ccr$1F', K_CCR, v[1], v[2], v[3]))
    return out


def gen(path):
    with open(path, 'w') as f:
        f.write('; generated by tests/mathffp_check.py gen - kind.w, LVO.w, D0.l, D1.l per case\n')
        f.write('cases:\n')
        for cid, kind, lvo, d0, d1 in cases():
            f.write('                dc.w    %d,%d\n                dc.l    $%08X,$%08X    ; %s\n'
                    % (kind, lvo, d0, d1, cid))
        f.write('                dc.w    -1\n')


# --- arithmetic model of spec §4 --------------------------------------------------------------------------------
M32 = 0xFFFFFFFF
MAXP, MAXN = 0xFFFFFF7F, 0xFFFFFFFF


def fl(r, v=False):
    """N and Z from the result's low byte (sign bit, low byte 0), plus V."""
    return r, ('N' if r & 0x80 else '') + ('Z' if r & 0xFF == 0 else '') + ('V' if v else '')


def pack(m, e, s):
    """24-bit mantissa m (only its low 24 bits are kept), exponent e, sign s ($80/0); spec §4.8/4.9 exponent 0."""
    if e > 127:
        return fl(MAXP | s, True)
    if e < 0 or (e == 0 and not s):
        return 0, 'Z'
    return fl(((m & 0xFFFFFF) << 8) | e | s)


def m_fix(x):
    if x & 0xFF == 0:
        return x, 'Z'
    n, neg, m32 = (x & 0x7F) - 64, x & 0x80, x & 0xFFFFFF00
    if n <= 0:
        return 0, 'Z'
    if not neg:
        if n >= 32:
            return 0x7FFFFFFF, 'V'
        r = m32 >> (32 - n)
        return r, 'Z' if r == 0 else ''
    if n > 32 or (n == 32 and (m32 == 0 or m32 > 0x80000000)):
        return 0x80000000, 'ZV'
    r = (-(m32 >> (32 - n))) & M32
    return r, 'Z' if r == 0 else 'N'


def m_flt(i):
    if i == 0:
        return 0, 'Z'
    s = 0x80 if i & 0x80000000 else 0
    mag = (-i) & M32 if s else i
    e = 64 + mag.bit_length()
    mag <<= 32 - mag.bit_length()
    mag += 0x80
    if mag > M32:
        mag, e = 0x80000000, e + 1
    return fl((mag & 0xFFFFFF00) | e | s)


def cmpkey(x):
    k = ((x & 0x7F) << 24) | ((x >> 8) ^ 0x800000)
    return -k - 1 if x & 0x80 else k


def m_cmp(d0, d1):
    a, b = cmpkey(d1), cmpkey(d0)
    return (1, 'N') if a > b else (0xFFFFFFFF, '') if a < b else (0, 'Z')


def m_tst(d1):
    return (0xFFFFFFFF, 'N') if d1 & 0x80 else (0, 'Z') if d1 & 0xFF == 0 else (1, '')


def m_abs(x):
    return fl(x & ~0x80 & M32)


def m_neg(x):
    return fl(x if x & 0xFF == 0 else x ^ 0x80)


def m_add(d0, d1):
    if d1 & 0xFF == 0:
        return fl(d0)
    if d0 & 0xFF == 0:
        return fl(d1)
    a, b = (d0, d1) if (d0 & 0x7F, d0 >> 8) >= (d1 & 0x7F, d1 >> 8) else (d1, d0)
    d = (a & 0x7F) - (b & 0x7F)
    if d >= 24:
        return fl(a)
    ma, mb = a & 0xFFFFFF00, (b & 0xFFFFFF00) >> d
    t = ma + mb if (a ^ b) & 0x80 == 0 else ma - mb
    if t == 0:
        return 0, 'Z'
    r, e = (t + 0x80) >> 8, a & 0x7F
    if r >= 1 << 24:
        r, e = r >> 1, e + 1
    while r < 1 << 23 and e >= 0:
        r, e = r << 1, e - 1
    return pack(r, e, a & 0x80)


def m_sub(d0, d1):
    return fl(d0) if d1 & 0xFF == 0 else m_add(d0, d1 ^ 0x80)


def m_mul(d0, d1):
    if d0 & 0xFF == 0:
        return fl(d0)
    if d1 & 0xFF == 0:
        return 0, 'Z'
    s, S = (d0 ^ d1) & 0x80, (d0 & 0x7F) + (d1 & 0x7F)
    if S >= 192:
        return fl(MAXP | s, True)
    p = (d0 >> 8) * (d1 >> 8)
    if p >= 1 << 47:
        m, e = (p + (1 << 23)) >> 24, S - 64
    else:
        m, e = (p + (1 << 22)) >> 23, S - 65
    if m >= 1 << 24:
        m, e = m >> 1, e + 1
    return pack(m, e, s)


def s32(v):
    return v - (1 << 32) if v & 0x80000000 else v


def m_div(d0, d1):
    if d1 & 0xFF == 0:
        return TRAP, ''
    if d0 == 0:
        return 0, 'Z'
    s, q = (d0 ^ d1) & 0x80, (d0 & 0x7F) - (d1 & 0x7F) + 64
    if q >= 128:
        return fl(MAXP | s, True)
    if q < 0:
        return 0, 'Z'
    md, mv = d0 >> 8, d1 >> 8
    if mv == 0:
        return TRAP, ''
    if s32(d0 & 0xFFFFFF00) >= s32(d1 & 0xFFFFFF00):
        m, e = (((md << 24) // mv) + 1) >> 1, q + 1
        if e == 128:
            s = d1 & 0x80
    else:
        m, e = (((md << 25) // mv) + 1) >> 1, q
    return pack(m, e, s)


def m_floor(x):
    e = x & 0x7F
    if e == 0:
        return fl(x & ~0x80 & M32)
    n = e - 64
    if n <= 0:
        return (0x800000C1, 'N') if x & 0x80 else (0, 'Z')
    if n >= 24:
        return fl(x)
    fm = (M32 >> n) & 0xFFFFFF00
    if x & fm == 0:
        return fl(x)
    t = x & ~fm & M32
    if not x & 0x80:
        return fl(t)
    t += fm + 0x100
    if t > M32:
        t = 0x80000000 | ((x & 0xFF) + 1)
    return fl(t)


def m_ceil(x):
    return m_neg(m_floor(m_neg(x)[0])[0])


def model(lvo, d0, d1):
    return {FIX: lambda: m_fix(d0), FLT: lambda: m_flt(d0), CMP: lambda: m_cmp(d0, d1), TST: lambda: m_tst(d1),
            ABS: lambda: m_abs(d0), NEG: lambda: m_neg(d0), ADD: lambda: m_add(d0, d1), SUB: lambda: m_sub(d0, d1),
            MUL: lambda: m_mul(d0, d1), DIV: lambda: m_div(d0, d1), FLOOR: lambda: m_floor(d0),
            CEIL: lambda: m_ceil(d0)}[lvo]()


def selftest():
    bad = 0
    for vid, lvo, d0, d1, want, wfl in VECTORS:
        got, gfl = model(lvo, d0, d1)
        ok = got == want and (want == TRAP or flags_ok(lvo, got, gfl, wfl))
        if not ok:
            bad += 1
            print('MODEL FAIL %s %s: %s %s want %s %s' % (vid, NAMES[lvo], hx(got), gfl, hx(want), wfl))
    print('model: %d/%d vectors' % (len(VECTORS) - bad, len(VECTORS)))
    return bad


def hx(v):
    return v if isinstance(v, str) else '%08X' % v


def flags_ok(lvo, res, got, want):
    """got/want: sets of N Z V letters. SPCmp: Z exact and the signed relation (spec §3.3)."""
    if lvo != CMP:
        return set(got) == set(want)
    n, z, v = 'N' in got, 'Z' in got, 'V' in got
    if res == 0:
        return z
    if res == 1:
        return not z and n != v
    return not z and n == v


# --- probe output check ------------------------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.n = self.fails = 0

    def res(self, name, ok, why=''):
        self.n += 1
        self.fails += not ok
        print('%s %s%s' % ('PASS' if ok else 'FAIL', name, '' if ok else ': ' + why))


def parse(path):
    lines = {}
    for line in open(path, encoding='latin-1'):
        parts = line.split()
        if not parts:
            continue
        f = {'_': parts[1:]}
        for p in parts[1:]:
            if '=' in p:
                k, v = p.split('=', 1)
                f[k] = v
        lines[parts[0]] = f
    return lines


def check(path):
    out = parse(path)
    rep = Report()
    for i, (cid, kind, lvo, d0, d1) in enumerate(cases()):
        f = out.get('C%03d' % i)
        name = '%s %s' % (cid, NAMES[lvo])
        if f is None:
            rep.res(name, False, 'no output line')
            continue
        if kind == K_TRAP:
            rep.res(name, 'TRAP' in f['_'], 'returned D0=%s f=%s instead of the zero-divide trap'
                    % (f.get('r'), f.get('f')))
            continue
        vid = cid.split()[0]
        if kind == K_A6Z:
            want, wfl = [(r[4], None) for r in A6ZERO if r[0] == cid][0]
        else:
            want, wfl = VEC[vid][4], VEC[vid][5]
        if 'TRAP' in f['_']:
            rep.res(name, False, 'unexpected trap')
            continue
        got, gfl = int(f['r'], 16), f['f'].replace('.', '').replace('C', '')
        errs = []
        if got != want:
            errs.append('D0=%08X want %08X' % (got, want))
        if wfl is not None and not flags_ok(lvo, got, gfl, wfl):
            errs.append('flags %s want %s' % (gfl or '-', wfl or '-'))
        x = f.get('x', '?')
        allowed = set() if lvo in D1_KEPT else {'d1'}
        changed = set(x.split(',')) - {'-'}
        if changed - allowed:
            errs.append('registers changed: %s' % ','.join(sorted(changed - allowed)))
        if kind == K_STACK:
            depth = int(f.get('s', '0'), 16)
            if not 4 <= depth <= STACK_MAX:
                errs.append('stack depth %d (spec: at most %d)' % (depth, STACK_MAX))
            name += ' depth=%d' % depth
        rep.res(name, not errs, '; '.join(errs))
    lib(out, rep)
    print('TOTAL %d checks, %d FAIL' % (rep.n, rep.fails))
    return rep.fails


def lib(out, rep):
    """Library vectors, spec §1 and §7 V13 (B1-B8)."""
    def val(line, key):
        f = out.get(line)
        return None if f is None or key not in f else int(f[key], 16)

    def expect(name, line, key, want):
        got = val(line, key)
        rep.res('%s %s=%s' % (name, key, '%X' % want), got == want,
                'got %s' % ('missing' if got is None else '%X' % got))

    expect('boot: listed', 'PRE', 'listed', 1)
    expect('boot: open count', 'PRE', 'cnt', 0)
    expect('boot: lib_Flags', 'PRE', 'flags', 4)
    expect('B1 Open(0)', 'B1', 'ok', 1)
    expect('B1 open count', 'B1', 'cnt', 1)
    expect('version', 'B1', 'ver', 34)
    expect('revision', 'B1', 'rev', 1)
    expect('lib_NegSize', 'B1', 'neg', 96)
    expect('lib_PosSize', 'B1', 'pos', 34)
    expect('ln_Type', 'B1', 'type', 9)
    expect('ln_Pri', 'B1', 'pri', 0)
    f = out.get('B1', {})
    ids = bytes.fromhex(f.get('id', ''))
    rep.res('lib_IdString "mathffp 34.1 (18 Aug 1987)\\r\\n"', ids == b'mathffp 34.1 (18 Aug 1987)\r\n',
            'got %r' % ids)
    expect('B3 Open(35)', 'B3', 'd0', 0)
    expect('B3 open count unchanged', 'B3', 'cnt', 1)
    expect('B2 Open(34)', 'B2', 'ok', 1)
    expect('B2 open count', 'B2', 'cnt', 2)
    expect('B4 CloseLibrary D0', 'B4', 'd0', 0)
    expect('B4 open count', 'B4', 'cnt', 1)
    expect('B5 Expunge(count 1) D0', 'B5', 'd0', 0)
    expect('B5 lib_Flags (DELEXP set)', 'B5', 'flags', 0x0C)
    expect('B5 still listed', 'B5', 'listed', 1)
    expect('B6 CloseLibrary D0', 'B6', 'd0', 0)
    expect('B6 open count', 'B6', 'cnt', 0)
    expect('B6 still listed (no delayed expunge)', 'B6', 'listed', 1)
    expect('B7 Null D0 unchanged', 'B7', 'd0', 0x5A5A1234)
    expect('B8 Expunge(count 0) D0', 'B8', 'd0', 0)
    expect('B8 removed from the library list', 'B8', 'listed', 0)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'gen':
        gen(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == 'check':
        sys.exit(1 if check(sys.argv[2]) else 0)
    elif len(sys.argv) == 2 and sys.argv[1] == 'model':
        sys.exit(1 if selftest() else 0)
    else:
        sys.exit(__doc__)
