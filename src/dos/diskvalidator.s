; src/dos/diskvalidator.s — disk-validator OFS (#4) : valide le bitmap d'allocation de DF0:.
;
; Le vrai disk-validator d'AmigaDOS revalide une disquette dont le bitmap est marqué invalide (bm_flag=0) en
; reconstruisant le bitmap depuis l'arbre de répertoires. Portée #4 (bornée) : VÉRIFICATION D'INTÉGRITÉ du bitmap
; d'un disque valide — (1) checksum OFS du rootblock (somme des 128 longs == 0), (2) sec_type = ST_ROOT, (3) bm_flag
; == $FFFFFFFF (bitmap marqué valide), (4) checksum OFS du bloc bitmap, (5) COHÉRENCE : le rootblock (880) doit être
; marqué ALLOUÉ (bit=0) dans le bitmap. Renvoie valide/invalide. La reconstruction (bm_flag=0 -> rebâtir) est différée.
;
; Format OFS public + ADF de test (asset) : bitmap bits LSB-first, idx = bloc-2, long[1+idx/32] bit (idx%32),
; 1=libre / 0=alloué. Via trackdisk CMD_READ (M6z). Piste IMPLÉMENTATION : ADF-FAQ / AmigaDOS Tech Ref. AUCUNE lecture ROM.

                include "exec.i"
                include "disk.i"
                include "ofs.i"

                xdef    dv_validate

; dv_validate(a6 = SysBase) -> d0 = 1 (disque valide) | 0 (invalide / pas de disque). Clobbe scratch + d2-d7/a2-a4 (sauvés).
dv_validate:
                movem.l d2-d7/a2-a4,-(sp)
                moveq   #0,d7                        ; d7 = résultat (invalide par défaut)
                lea     EB_DEVICELIST(a6),a0
                lea     dv_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .dv_ret                      ; pas de trackdisk
                move.l  d0,a2                        ; a2 = trackdisk base
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .dv_ret
                move.l  d0,a3                        ; a3 = ioreq ; buffer = a3+IOREQ_SZ
                move.l  #OFS_ROOTBLK,d0              ; 1. lire le rootblock (880)
                bsr     dv_read_block
                tst.l   d0
                beq     .dv_free                     ; lecture KO (pas de disque)
                lea     IOREQ_SZ(a3),a4              ; a4 = buffer
                bsr     dv_checksum                  ; checksum OFS rootblock : somme longs == 0 ?
                tst.l   d0
                bne     .dv_free                     ; checksum rootblock KO
                cmp.l   #OFS_ST_ROOT,OFSB_SECTYPE(a4)
                bne     .dv_free                     ; pas un rootblock
                move.l  OFSB_BMFLAG(a4),d0           ; 3. bm_flag == $FFFFFFFF ?
                addq.l  #1,d0                        ; -1 + 1 = 0
                bne     .dv_free                     ; bitmap marqué invalide (revalidation différée)
                move.l  OFSB_BMPAGES(a4),d5          ; d5 = bloc bitmap
                cmp.l   #2,d5
                blo     .dv_free
                cmp.l   #OFS_NBLK,d5
                bhs     .dv_free                     ; n° de bloc bitmap hors bornes
                move.l  d5,d0                        ; 4. lire le bloc bitmap
                bsr     dv_read_block
                tst.l   d0
                beq     .dv_free
                lea     IOREQ_SZ(a3),a4
                ifne    DV_CORRUPT
                eori.b  #$FF,OFSB_BMBITS(a4)         ; RED : corrompt le bitmap -> checksum KO
                endc
                bsr     dv_checksum                  ; checksum OFS du bloc bitmap
                tst.l   d0
                bne     .dv_free                     ; bitmap corrompu
                ; 5. cohérence : rootblock (880) marqué ALLOUÉ dans le bitmap.
                ; idx = 880-2 = 878 ; long index = 1 + 878/32 = 28 (octet 112) ; bit = 878 mod 32 = 14 (LSB-first) ; 0=alloué
                move.l  112(a4),d0                   ; long[28] du bloc bitmap
                btst    #14,d0
                bne     .dv_free                     ; bit=1 (libre) -> incohérent : le root doit être alloué
                moveq   #1,d7                        ; tous les contrôles passent -> disque valide
.dv_free:
                move.l  a3,a1
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
.dv_ret:
                move.l  d7,d0
                movem.l (sp)+,d2-d7/a2-a4
                rts

; dv_checksum(a4 = bloc 512 o) -> d0 = somme des 128 longs (0 = checksum OFS valide). Clobbe d0/d1/a0.
dv_checksum:
                move.l  a4,a0
                moveq   #0,d0
                move.w  #(OFS_BSIZE/4)-1,d1          ; 127 itérations
.cs_lp:
                add.l   (a0)+,d0
                dbra    d1,.cs_lp
                rts

; dv_read_block(d0=bloc, a2=trackdisk, a3=ioreq, a6=SysBase) -> d0 = 1 OK / 0 KO ; remplit a3+IOREQ_SZ.
; Scratch d0/d1/a0/a1 (BeginIO préserve d2-d7/a2-a5) -> l'état de dv_validate survit.
dv_read_block:
                lsl.l   #8,d0
                lsl.l   #1,d0                        ; offset = bloc * 512
                move.l  a2,IO_DEVICE(a3)
                move.w  #CMD_READ,IO_COMMAND(a3)
                move.l  #OFS_BSIZE,IO_LENGTH(a3)
                lea     IOREQ_SZ(a3),a0
                move.l  a0,IO_DATA(a3)
                move.l  d0,IO_OFFSET(a3)
                move.b  #IOF_QUICK,IO_FLAGS(a3)
                clr.l   IO_ACTUAL(a3)
                move.l  a6,-(sp)
                move.l  a2,a6
                move.l  a3,a1
                jsr     -30(a6)                      ; BeginIO (trackdisk, -30)
                move.l  (sp)+,a6
                tst.b   IO_ERROR(a3)
                bne.s   .rb_fail
                cmp.l   #OFS_BSIZE,IO_ACTUAL(a3)
                bne.s   .rb_fail
                moveq   #1,d0
                rts
.rb_fail:
                moveq   #0,d0
                rts

dv_td_name:
                dc.b    "trackdisk.device",0
                even
