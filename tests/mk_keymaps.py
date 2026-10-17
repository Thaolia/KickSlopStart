#!/usr/bin/env python3
# tests/mk_keymaps.py — génère src/exec/keymapdata.s : tables keymap HAND-AUTHORED (US QWERTY + FR AZERTY).
#
# CLEAN-ROOM : ces tables sont auteurées ICI (à la main), PAS extraites de la ROM. Pour chaque keymap, 2 tables
# de 96 octets indexées par keycode brut (0x00..0x5F) : _lo (non-shifté) et _hi (shifté). 0 = touche non mappée.
# Le cook (kbd_cook) applique : SHIFT -> _hi ; CAPS -> majuscule si lettre ; CTRL -> char & 0x1F. Accents FR en
# Latin-1 (é=0xE9 ...) ; la police 8x8 ne couvre que l'ASCII -> ces octets sont produits mais rendus comme bloc.
# Usage : python3 -I tests/mk_keymaps.py > src/exec/keymapdata.s
import sys

# (keycode) -> (char non-shifté, char shifté). Caractères ASCII sauf accents FR (Latin-1).
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
 0x40:(' ',' '),
}
# AZERTY (France) : rangée chiffres = symboles non-shiftés / chiffres shiftés ; A<->Q, Z<->W, M deplace.
FR = {
 0x00:('\xb2','\xb2'),          # ² (superscript two)
 0x01:('&','1'),0x02:('\xe9','2'),0x03:('"','3'),0x04:("'",'4'),0x05:('(','5'),
 0x06:('-','6'),0x07:('\xe8','7'),0x08:('_','8'),0x09:('\xe7','9'),0x0A:('\xe0','0'),
 0x0B:(')','\xb0'),0x0C:('=','+'),
 0x10:('a','A'),0x11:('z','Z'),0x12:('e','E'),0x13:('r','R'),0x14:('t','T'),
 0x15:('y','Y'),0x16:('u','U'),0x17:('i','I'),0x18:('o','O'),0x19:('p','P'),
 0x1A:('^','\xa8'),0x1B:('$','\xa3'),
 0x20:('q','Q'),0x21:('s','S'),0x22:('d','D'),0x23:('f','F'),0x24:('g','G'),
 0x25:('h','H'),0x26:('j','J'),0x27:('k','K'),0x28:('l','L'),0x29:('m','M'),
 0x2A:('\xf9','%'),
 0x31:('w','W'),0x32:('x','X'),0x33:('c','C'),0x34:('v','V'),0x35:('b','B'),
 0x36:('n','N'),0x37:(',','?'),0x38:(';','.'),0x39:(':','/'),0x3A:('!','\xa7'),
}
# Touches communes aux deux layouts (contrôle + espace) : essentielles pour le CLI (Return=CR, etc.).
COMMON = {
 0x40:(' ',' '),                 # Space
 0x41:('\x08','\x08'),           # Backspace
 0x42:('\x09','\x09'),           # Tab
 0x43:('\r','\r'),               # Enter (pavé num)
 0x44:('\r','\r'),               # Return
 0x45:('\x1b','\x1b'),           # Esc
 0x46:('\x7f','\x7f'),           # Delete
}
US.update(COMMON)
FR.update(COMMON)

def byte(c):
    return 0 if c is None else (ord(c) & 0xFF)

def table(d, idx):
    return [byte(d[k][idx]) if k in d else 0 for k in range(0x00,0x60)]

def emit_table(name, vals):
    out=[f"{name}:"]
    for i in range(0,96,12):
        row=vals[i:i+12]
        out.append("                dc.b    " + ",".join("$%02X"%b for b in row) + "   ; $%02X.." % i)
    return "\n".join(out)

def main():
    L=[]
    L.append("; src/exec/keymapdata.s — tables keymap HAND-AUTHORED (US + AZERTY), GÉNÉRÉES par tests/mk_keymaps.py.")
    L.append("; CLEAN-ROOM : tables auteurées à la main (générateur), PAS extraites de la ROM. 96 octets/table (keycode")
    L.append("; brut 0x00..0x5F) ; _lo = non-shifté, _hi = shifté ; 0 = non mappé. Accents FR en Latin-1. NE PAS ÉDITER.")
    L.append("")
    L.append("                xdef    km_us_lo")
    L.append("                xdef    km_us_hi")
    L.append("                xdef    km_fr_lo")
    L.append("                xdef    km_fr_hi")
    L.append("                EVEN")
    L.append(emit_table("km_us_lo", table(US,0)))
    L.append(emit_table("km_us_hi", table(US,1)))
    L.append(emit_table("km_fr_lo", table(FR,0)))
    L.append(emit_table("km_fr_hi", table(FR,1)))
    L.append("")
    sys.stdout.write("\n".join(L)+"\n")

main()
