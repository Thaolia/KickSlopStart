; src/exec/rawdofmt.s — exec RawDoFmt (LVO -522) : formatage « à la printf » utilisé par les programmes (printf des
; startup C, messages de SetPatch...). Sans lui, ces programmes formatent dans un tampon jamais rempli.
; Piste IMPLÉMENTATION (« clean ») : AutoDoc exec.library/RawDoFmt (public). AUCUNE lecture ROM.
;
; RawDoFmt(FormatString a0, DataStream a1, PutChProc a2, PutChData a3) -> d0 = DataStream après consommation.
; Spécification %[-][0][largeur][.limite][l]type ; types d (signé), u (non signé), x (hexa), s (C-string), b (BSTR
; via BPTR), c (caractère). Les données sont des MOTS (16 bits) sauf avec « l » (32 bits) ; %s et %b prennent
; toujours un pointeur 32 bits. Chaque caractère produit, NUL final compris, est passé à PutChProc (d0 = caractère,
; a3 = PutChData) ; a3 peut être modifié par PutChProc et est transmis tel quel à l'appel suivant, mais il est
; RESTITUÉ à l'appelant au retour (SetPatch mesure ensuite son tampon à partir de a3).

                include "exec.i"

                xdef    exec_RawDoFmt

RDF_BUF         EQU 12               ; tampon de conversion numérique (32 bits décimal = 11 caractères avec signe)

; registres : a4 = format, a5 = flux de données, a2 = PutChProc, a3 = PutChData
; d3 = drapeau long, d4 = cadrage à gauche, d5 = caractère de remplissage, d6 = largeur, d7 = limite (-1 = aucune)
exec_RawDoFmt:
        movem.l d2-d7/a2-a5,-(sp)            ; a2/a3 restitués à l'appelant (a3 n'évolue qu'entre les PutChProc)
        lea     -RDF_BUF(sp),sp
        move.l  a0,a4
        move.l  a1,a5
.rf_next:
        move.b  (a4)+,d0
        beq.s   .rf_end
        cmp.b   #'%',d0
        beq.s   .rf_spec
        bsr     .rf_put
        bra.s   .rf_next
.rf_end:
        moveq   #0,d0                ; NUL final transmis à PutChProc
        bsr     .rf_put
        move.l  a5,d0
        lea     RDF_BUF(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

.rf_spec:
        moveq   #0,d3
        moveq   #0,d4
        moveq   #' ',d5
        moveq   #0,d6
        moveq   #-1,d7
        move.b  (a4)+,d0
        cmp.b   #'-',d0
        bne.s   .rf_zero
        moveq   #1,d4
        move.b  (a4)+,d0
.rf_zero:
        cmp.b   #'0',d0
        bne.s   .rf_width
        moveq   #'0',d5
        move.b  (a4)+,d0
.rf_width:
        bsr     .rf_digit
        bcs.s   .rf_dot
        mulu.w  #10,d6
        add.w   d1,d6
        move.b  (a4)+,d0
        bra.s   .rf_width
.rf_dot:
        cmp.b   #'.',d0
        bne.s   .rf_long
        moveq   #0,d7
        move.b  (a4)+,d0
.rf_limit:
        bsr     .rf_digit
        bcs.s   .rf_long
        mulu.w  #10,d7
        add.w   d1,d7
        move.b  (a4)+,d0
        bra.s   .rf_limit
.rf_long:
        cmp.b   #'l',d0
        bne.s   .rf_type
        moveq   #1,d3
        move.b  (a4)+,d0
.rf_type:
        tst.b   d0
        beq.s   .rf_end              ; format tronqué après '%'
        cmp.b   #'d',d0
        beq.s   .rf_dec
        cmp.b   #'u',d0
        beq.s   .rf_udec
        cmp.b   #'x',d0
        beq     .rf_hex
        cmp.b   #'s',d0
        beq     .rf_str
        cmp.b   #'b',d0
        beq     .rf_bstr
        cmp.b   #'c',d0
        beq     .rf_char
        bsr     .rf_put              ; « %% » ou type inconnu : le caractère tel quel
        bra     .rf_next

.rf_dec:                             ; décimal signé
        bsr     .rf_fetch_signed
        moveq   #0,d2                ; d2 = 1 si négatif
        tst.l   d0
        bpl.s   .rf_decabs
        neg.l   d0
        moveq   #1,d2
        bra.s   .rf_decabs
.rf_udec:                            ; décimal non signé
        bsr     .rf_fetch_unsigned
        moveq   #0,d2
.rf_decabs:
        lea     RDF_BUF(sp),a0       ; a0 = fin du tampon (chiffres écrits de droite à gauche)
        move.l  d0,d1
.rf_dloop:                           ; d1 /= 10 en deux divu 16 bits (68000), chiffre = reste
        moveq   #0,d0
        swap    d1
        move.w  d1,d0                ; d0 = mot haut
        divu.w  #10,d0               ; d0 = [reste:quotient haut]
        move.w  d0,d1
        swap    d1                   ; d1 = [quotient haut:mot bas]
        move.w  d1,d0                ; d0 = [reste:mot bas]
        divu.w  #10,d0               ; d0 = [chiffre:quotient bas]
        move.w  d0,d1                ; d1 = quotient complet
        swap    d0
        add.b   #'0',d0
        move.b  d0,-(a0)
        tst.l   d1
        bne.s   .rf_dloop
        tst.w   d2
        beq.s   .rf_numout
        move.b  #'-',-(a0)
.rf_numout:
        lea     RDF_BUF(sp),a1
        move.l  a1,d2
        sub.l   a0,d2                ; d2 = longueur
        moveq   #-1,d7               ; pas de limite sur un nombre
        bra     .rf_emit

.rf_hex:
        bsr     .rf_fetch_unsigned
        lea     RDF_BUF(sp),a0
        move.l  d0,d1
.rf_xloop:
        move.b  d1,d0
        and.b   #$0F,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .rf_xdig
        addq.b  #7,d0                ; 'A'..'F'
.rf_xdig:
        move.b  d0,-(a0)
        lsr.l   #4,d1
        bne.s   .rf_xloop
        bra.s   .rf_numout

.rf_str:
        move.l  (a5)+,a0
        move.l  a0,d0
        beq.s   .rf_empty
        move.l  a0,a1
        moveq   #-1,d2
.rf_slen:
        addq.l  #1,d2
        tst.b   (a1)+
        bne.s   .rf_slen
        bra.s   .rf_emit
.rf_empty:
        moveq   #0,d2
        bra.s   .rf_emit

.rf_bstr:                            ; BPTR vers BSTR (octet de longueur + caractères)
        move.l  (a5)+,d0
        lsl.l   #2,d0
        beq.s   .rf_empty
        move.l  d0,a0
        moveq   #0,d2
        move.b  (a0)+,d2
        bra.s   .rf_emit

.rf_char:
        bsr     .rf_fetch_unsigned
        lea     RDF_BUF(sp),a0
        move.b  d0,-(a0)
        moveq   #1,d2

; .rf_emit : a0 = texte, d2 = longueur ; applique la limite (d7), la largeur (d6), le cadrage (d4) et le
; remplissage (d5 ; avec '0', un signe '-' en tête passe devant les zéros).
.rf_emit:
        tst.l   d7
        bmi.s   .rf_nolimit
        cmp.l   d7,d2
        bls.s   .rf_nolimit
        move.l  d7,d2
.rf_nolimit:
        sub.l   d2,d6                ; d6 = remplissage nécessaire
        tst.w   d4
        bne.s   .rf_text             ; cadré à gauche : remplissage après le texte
        cmp.b   #'0',d5
        bne.s   .rf_lpad
        tst.l   d2
        beq.s   .rf_lpad
        cmp.b   #'-',(a0)
        bne.s   .rf_lpad
        move.b  (a0)+,d0
        subq.l  #1,d2
        bsr.s   .rf_put
.rf_lpad:
        bsr.s   .rf_pad
.rf_text:
        tst.l   d2
        beq.s   .rf_tdone
.rf_tloop:
        move.b  (a0)+,d0
        bsr.s   .rf_put
        subq.l  #1,d2
        bne.s   .rf_tloop
.rf_tdone:
        tst.w   d4
        beq     .rf_next
        moveq   #' ',d5
        bsr.s   .rf_pad
        bra     .rf_next

; .rf_pad : émet d6 fois d5 si d6 > 0 ; d6 = 0 en sortie.
.rf_pad:
        tst.l   d6
        ble.s   .rf_padz
        move.b  d5,d0
        bsr.s   .rf_put
        subq.l  #1,d6
        bra.s   .rf_pad
.rf_padz:
        moveq   #0,d6
        rts

; .rf_put : d0.b -> PutChProc(d0, a3). PutChProc peut écraser d0/d1/a0/a1 : a0 (texte en cours) est préservé.
.rf_put:
        movem.l d1/a0-a1,-(sp)
        and.l   #$FF,d0
        jsr     (a2)
        movem.l (sp)+,d1/a0-a1
        rts

; .rf_digit : d0.b chiffre décimal ? -> C = 0 et d1.w = valeur ; sinon C = 1.
.rf_digit:
        cmp.b   #'0',d0
        blo.s   .rf_nodig
        cmp.b   #'9',d0
        bhi.s   .rf_nodig
        moveq   #0,d1
        move.b  d0,d1
        sub.b   #'0',d1
        and.b   #$FE,ccr             ; C = 0
        rts
.rf_nodig:
        or.b    #$01,ccr             ; C = 1
        rts

; .rf_fetch_signed / .rf_fetch_unsigned : d0 = mot (étendu signé / non signé) ou long (si d3) du flux a5.
.rf_fetch_signed:
        tst.w   d3
        bne.s   .rf_flong
        move.w  (a5)+,d0
        ext.l   d0
        rts
.rf_fetch_unsigned:
        tst.w   d3
        bne.s   .rf_flong
        moveq   #0,d0
        move.w  (a5)+,d0
        rts
.rf_flong:
        move.l  (a5)+,d0
        rts
