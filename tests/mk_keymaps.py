#!/usr/bin/env python3
# tests/mk_keymaps.py - generates src/exec/keymapdata.s: HAND-AUTHORED keymaps (US QWERTY + FR AZERTY) in the public
# `struct KeyMap` format (devices/keymap.h): types, values, Capsable and Repeatable bit arrays, for the Lo ($00-$3F)
# and Hi ($40-$77) code ranges.
#
# CLEAN-ROOM: the layouts are authored HERE, NOT extracted from the ROM. Printable keys are KC_VANILLA (bytes: none,
# Shift, Alt = none, Shift+Alt = Shift; Ctrl is derived by the converter); cursor keys, F1-F10, Help and Shift-Tab are
# KCF_STRING with the CSI sequences documented for console.device; Return/Enter give CR, Ctrl-Return LF. French
# accents in Latin-1. Letters a-z are Capsable; every mapped key repeats.
# Usage: python3 -I tests/mk_keymaps.py > src/exec/keymapdata.s
import sys

# (keycode) -> (unshifted char, shifted char). ASCII characters except French accents (Latin-1).
US = {
 0x00:('`','~'),
 0x01:('1','!'),0x02:('2','@'),0x03:('3','#'),0x04:('4','$'),0x05:('5','%'),
 0x06:('6','^'),0x07:('7','&'),0x08:('8','*'),0x09:('9','('),0x0A:('0',')'),
 0x0B:('-','_'),0x0C:('=','+'),0x0D:('\\','|'),
 0x10:('q','Q'),0x11:('w','W'),0x12:('e','E'),0x13:('r','R'),0x14:('t','T'),
 0x15:('y','Y'),0x16:('u','U'),0x17:('i','I'),0x18:('o','O'),0x19:('p','P'),
 0x1A:('[','{'),0x1B:(']','}'),
 0x20:('a','A'),0x21:('s','S'),0x22:('d','D'),0x23:('f','F'),0x24:('g','G'),
 0x25:('h','H'),0x26:('j','J'),0x27:('k','K'),0x28:('l','L'),0x29:(';',':'),
 0x2A:("'",'"'),
 0x31:('z','Z'),0x32:('x','X'),0x33:('c','C'),0x34:('v','V'),0x35:('b','B'),
 0x36:('n','N'),0x37:('m','M'),0x38:(',','<'),0x39:('.','>'),0x3A:('/','?'),
}
# AZERTY (France): digit row = unshifted symbols / shifted digits; A<->Q, Z<->W, M moved.
FR = {
 0x00:('\xb2','\xb2'),          # superscript two
 0x01:('&','1'),0x02:('\xe9','2'),0x03:('"','3'),0x04:("'",'4'),0x05:('(','5'),
 0x06:('-','6'),0x07:('\xe8','7'),0x08:('_','8'),0x09:('\xe7','9'),0x0A:('\xe0','0'),
 0x0B:(')','\xb0'),0x0C:('=','+'),
 0x10:('a','A'),0x11:('z','Z'),0x12:('e','E'),0x13:('r','R'),0x14:('t','T'),
 0x15:('y','Y'),0x16:('u','U'),0x17:('i','I'),0x18:('o','O'),0x19:('p','P'),
 0x1A:('^','\xa8'),0x1B:('$','\xa3'),
 0x20:('q','Q'),0x21:('s','S'),0x22:('d','D'),0x23:('f','F'),0x24:('g','G'),
 0x25:('h','H'),0x26:('j','J'),0x27:('k','K'),0x28:('l','L'),0x29:('m','M'),
 0x2A:('\xf9','%'),0x2B:('*','\xb5'),
 0x30:('<','>'),
 0x31:('w','W'),0x32:('x','X'),0x33:('c','C'),0x34:('v','V'),0x35:('b','B'),
 0x36:('n','N'),0x37:(',','?'),0x38:(';','.'),0x39:(':','/'),0x3A:('!','\xa7'),
}
# Numeric keypad (same characters with or without Shift).
KEYPAD = {
 0x0F:'0',0x1D:'1',0x1E:'2',0x1F:'3',0x2D:'4',0x2E:'5',0x2F:'6',0x3D:'7',0x3E:'8',0x3F:'9',0x3C:'.',
 0x4A:'-',0x5A:'(',0x5B:')',0x5C:'/',0x5D:'*',0x5E:'+',
}
CSI = '\x9b'
STRINGS = {                     # code -> (sequence without Shift, sequence with Shift)
 0x42:('\t', CSI+'Z'),          # Tab / Shift-Tab
 0x4C:(CSI+'A', CSI+'T'),       # cursor up
 0x4D:(CSI+'B', CSI+'S'),       # cursor down
 0x4E:(CSI+'C', CSI+' @'),      # cursor right
 0x4F:(CSI+'D', CSI+' A'),      # cursor left
 0x5F:(CSI+'?~', CSI+'?~'),     # Help
}
for n in range(10):              # F1-F10
    STRINGS[0x50+n] = (CSI+'%d~' % n, CSI+'1%d~' % n)
SINGLE = {0x40:' ', 0x41:'\x08', 0x45:'\x1b', 0x46:'\x7f'}   # Space, Backspace, Esc, Del
CTRLKEYS = {0x43:('\r','\n'), 0x44:('\r','\n')}            # Enter, Return: CR, Ctrl -> LF

KC_VANILLA, KCF_SHIFT, KCF_CONTROL, KCF_STRING, KCF_NOP = 7, 1, 4, 0x40, 0x80

def b(c):
    return ord(c) & 0xFF

def build(layout, prefix):
    """-> (types[0x78], values[0x78] as int or label, capsable bits, repeatable bits, extra data lines)."""
    types=[KCF_NOP]*0x78; vals=[0]*0x78; caps=set(); rep=set(); extra=[]
    for k,(lo,hi) in layout.items():
        types[k]=KC_VANILLA
        vals[k]=(b(hi)<<24)|(b(lo)<<16)|(b(hi)<<8)|b(lo)     # bytes from LSB: none, Shift, Alt, Shift+Alt
        if 'a'<=lo<='z': caps.add(k)
    for k,c in KEYPAD.items():
        types[k]=0; vals[k]=b(c)
    for k,c in SINGLE.items():
        types[k]=0; vals[k]=b(c)
    for k,(n,c) in CTRLKEYS.items():
        types[k]=KCF_CONTROL; vals[k]=(b(c)<<8)|b(n)
    for k,(s0,s1) in sorted(STRINGS.items()):
        lab="%s_s%02X" % (prefix,k)
        types[k]=KCF_STRING|KCF_SHIFT; vals[k]=lab
        data=[len(s0),4,len(s1),4+len(s0)]+[b(c) for c in s0+s1]
        extra.append("%s:\n                dc.b    %s" % (lab, ",".join("$%02X" % x for x in data)))
    for k in range(0x78):
        if types[k]!=KCF_NOP: rep.add(k)
    return types,vals,caps,rep,extra

def bits(s, base, n):
    out=[0]*n
    for k in s:
        if base<=k<base+8*n: out[(k-base)>>3] |= 1<<((k-base)&7)
    return out

def emit(prefix, layout):
    types,vals,caps,rep,extra=build(layout,prefix)
    L=["; --- %s ---" % prefix, "%s:                              ; struct KeyMap" % prefix]
    for f in ("lotypes","lomap","locaps","lorep","hitypes","himap","hicaps","hirep"):
        L.append("                dc.l    %s_%s" % (prefix,f))
    def dcb(lab, arr):
        L.append(lab+":")
        for i in range(0,len(arr),16):
            L.append("                dc.b    "+",".join("$%02X" % x for x in arr[i:i+16]))
    def dcl(lab, arr):
        L.append(lab+":")
        for i in range(0,len(arr),4):
            L.append("                dc.l    "+",".join(v if isinstance(v,str) else "$%08X" % v for v in arr[i:i+4]))
    dcb(prefix+"_lotypes", types[0:0x40]); dcb(prefix+"_hitypes", types[0x40:0x78])
    dcb(prefix+"_locaps", bits(caps,0,8)); dcb(prefix+"_hicaps", bits(caps,0x40,7))
    dcb(prefix+"_lorep", bits(rep,0,8)); dcb(prefix+"_hirep", bits(rep,0x40,7))
    L.append("                EVEN")
    dcl(prefix+"_lomap", vals[0:0x40]); dcl(prefix+"_himap", vals[0x40:0x78])
    L.extend(extra)
    L.append("                EVEN")
    return L

def main():
    L=[]
    L.append("; src/exec/keymapdata.s — HAND-AUTHORED keymaps (US + AZERTY) in struct KeyMap format, GENERATED by")
    L.append("; tests/mk_keymaps.py. CLEAN-ROOM: layouts authored by hand (generator), NOT extracted from the ROM. French")
    L.append("; accents in Latin-1. DO NOT EDIT.")
    L.append("")
    L.append("                xdef    km_us")
    L.append("                xdef    km_fr")
    L.append("                EVEN")
    L.extend(emit("km_us", US))
    L.extend(emit("km_fr", FR))
    sys.stdout.write("\n".join(L)+"\n")

main()
