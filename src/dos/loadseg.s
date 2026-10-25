; src/dos/loadseg.s — LoadSeg (D2) : charge un exécutable AmigaDOS « hunk » depuis l'OFS, APPLIQUE les
; relocations, bâtit une seglist BPTR, et renvoie le BPTR du premier segment. Machinerie INTERNE (pas encore
; de dos.library packets = D3). S'appuie sur ofs_read_file (D1) pour lire le fichier, puis parse le format hunk.
;
; Format hunk VERROUILLÉ empiriquement (binaire vlink -s -bamigahunk, PAS la ROM) : HUNK_HEADER (resident libs=0,
; table_size, first, last, N tailles [bits 30-31 = flags mémoire à masquer]) ; corps = par hunk : CODE/DATA (nlongs
; + data) ou BSS (nlongs, pas de data), relocations HUNK_RELOC32 ($3EC : répété [count][hunk_ref][offsets...], 0 =
; fin), HUNK_END ; NAME/SYMBOL/DEBUG ignorés (sans effet sur le chargement). $3FC (RELOC32 compact) -> échec propre
; (pas de skip silencieux de relocation). Clean-room : AmigaDOS Technical Reference /
; RKRM (format hunk public) + AROS rom/dos InternalLoadSeg (lecture seule). AUCUNE lecture ROM.
;
; Seglist (convention AmigaDOS) : chaque segment = bloc AllocMem [LONG taille][BPTR next][contenu...] ; le BPTR
; pointe sur le champ next (bloc+4) -> contenu à (BPTR<<2)+4 = bloc+8 ; taille à bloc+0 (pour UnLoadSeg).
; Flags mémoire du HUNK_HEADER respectés (bit 30 -> MEMF_CHIP, bit 31 -> MEMF_FAST ; 11 = attributs étendus V37 ->
; échec propre). Déviations/portée D2 ASSUMÉES : first != 0, resident libs,
; RELOC32SHORT, overlays -> non supportés (échec propre). Suffit pour charger nos exécutables.
; Gardes anti-corruption : index du hunk courant et hunk référencé par RELOC32 < hunkcount. DETTE : l'offset de
; relocation (`offset < taille du hunk`) et la taille du contenu ne sont pas bornés -> un binaire corrompu peut
; encore écrire hors de son hunk. Prouvé sur un vrai binaire de disque (HolidayLemmings : 4 hunks, BSS chip de
; 363 Ko, hunks CODE chip/any, RELOC32 multi-références, ids de hunk portant les flags mémoire).

                include "exec.i"
                include "ofs.i"
                include "dospkt.i"

                xdef    dos_loadseg
                xdef    dos_unloadseg
                xdef    ls_load_hunks
                xdef    ls_load_stream
                xref    ofs_read_file

HUNK_HEADER     EQU $3F3
HUNK_CODE       EQU $3E9
HUNK_DATA       EQU $3EA
HUNK_BSS        EQU $3EB
HUNK_RELOC32    EQU $3EC
HUNK_END        EQU $3F2
HUNK_NAME       EQU $3E8
HUNK_SYMBOL     EQU $3F0
HUNK_DEBUG      EQU $3F1
LS_FILEMAX      EQU DOS_FILEMAX    ; taille max d'un exécutable hunk chargé (cap-bump 32K, exec.i)
LS_MAXHUNKS     EQU 64            ; borne du nombre de hunks (anti-corruption)

; D2_NO_RELOC=1 (RED D2) : lit les relocations mais ne les APPLIQUE PAS -> le pointeur absolu reste l'offset
; link-time (0 dans le hunk DATA) -> le code chargé lit la RAM basse -> octets faux -> « D2LOADSEG OK » absent,
; SANS bus error. Isole l'application des relocations. Défaut 0.
D2_NO_RELOC     EQU 0

; dos_loadseg(a6=SysBase, a0=filename NUL-terminé) -> d0 = BPTR 1er segment | 0. Wrapper : lit le fichier ENTIER
; via ofs_read_file (D1) dans un filebuf, puis ls_load_hunks le parse. (D3d appelle ls_load_hunks directement sur
; un buffer lu via dos Open/Read -> chargement À TRAVERS les packets/handler.)
dos_loadseg:
                movem.l d2/a2,-(sp)
                move.l  a0,d2                ; d2 = filename
                move.l  #LS_FILEMAX,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .dl_fail0
                move.l  d0,a2                ; a2 = filebuf
                move.l  d2,a0                ; filename
                move.l  a2,a1                ; dest
                move.l  #LS_FILEMAX,d0
                jsr     ofs_read_file        ; d0 = taille | 0
                tst.l   d0
                beq.s   .dl_freefb           ; introuvable / vide
                move.l  a2,a0                ; a0 = filebuf, d0 = taille
                bsr     ls_load_hunks        ; d0 = BPTR seglist | 0
                move.l  d0,d2                ; sauve seglist
                move.l  a2,a1                ; libère filebuf
                move.l  #LS_FILEMAX,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d2,d0                ; renvoie seglist
                bra.s   .dl_ret
.dl_freefb:
                move.l  a2,a1
                move.l  #LS_FILEMAX,d0
                jsr     LVO_FREEMEM(a6)
.dl_fail0:
                moveq   #0,d0
.dl_ret:
                movem.l (sp)+,d2/a2
                rts

; ls_load_hunks(a6=SysBase, a0=filebuf, d0=taille) -> d0 = BPTR 1er segment | 0, d1 = code d'erreur dos si 0.
; Parse le format hunk depuis un buffer déjà en mémoire (dos_loadseg, client D3d). NE libère PAS filebuf.
ls_load_hunks:
                lea     -LR_SIZE(sp),sp
                move.l  a0,LR_BUF(sp)
                clr.l   LR_POS(sp)
                move.l  d0,LR_LEN(sp)
                clr.l   LR_FH(sp)            ; pas de fichier : la fin du tampon est la fin des données
                move.l  sp,a0
                bsr.s   ls_load_stream
                lea     LR_SIZE(sp),sp
                rts

; ls_load_stream(a6=SysBase, a0=lecteur LR_*) -> d0 = BPTR 1er segment | 0, d1 = 103 (mémoire) ou 121 (format) si 0.
; Lecteur : tampon LR_BUF de LR_CAP octets rechargé par Read(LR_FH) via LR_DOS (LoadSeg), ou tampon fixe de LR_LEN
; octets si LR_FH = 0. Les gros blocs de contenu sont lus directement à leur place.
; a5=lecteur, a4=contentAddr[], d2=hidx, d4=hunkcount, d5=BPTR 1er segment, d6=bloc précédent, d7=scratch.
ls_load_stream:
                movem.l d2-d7/a2-a5,-(sp)
                move.l  a0,a5
                clr.w   LR_EOF(a5)
                moveq   #0,d5
                sub.l   a4,a4
                ; --- HUNK_HEADER ---
                bsr     ls_rdl
                cmp.l   #HUNK_HEADER,d0
                bne     .fail_fmt
                bsr     ls_rdl               ; resident libs
                tst.l   d0
                bne     .fail_fmt            ; != 0 non supporté
                bsr     ls_rdl               ; table_size -> d4
                move.l  d0,d4
                beq     .fail_fmt
                cmp.l   #LS_MAXHUNKS,d4
                bhi     .fail_fmt
                bsr     ls_rdl               ; first (doit être 0)
                tst.l   d0
                bne     .fail_fmt
                bsr     ls_rdl               ; last
                addq.l  #1,d0                ; hunkcount = last+1
                cmp.l   d4,d0
                bhi     .fail_fmt            ; hunkcount > table_size -> corrompu
                move.l  d0,d4                ; d4 = hunkcount (= nb de tailles à lire)
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                move.l  d4,d0                ; contentAddr[] (d4 longs)
                lsl.l   #2,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fail_mem
                move.l  d0,a4                ; a4 = contentAddr table
                ; --- allouer chaque segment + chaîner ---
                moveq   #0,d2                ; i
                moveq   #0,d6                ; bloc précédent (0 = aucun)
.alloc_loop:
                cmp.l   d4,d2
                bhs.s   .alloc_done
                bsr     ls_rdl               ; champ taille (longs + flags mémoire)
                move.l  d0,d3
                rol.l   #2,d3
                and.l   #3,d3                ; d3 = bits 31-30 -> 1-0 : bit0 = CHIP, bit1 = FAST
                cmp.w   #3,d3
                beq     .fail_fmt            ; 11 = attributs étendus (V37+) -> non supporté en 1.3
                and.l   #$3FFFFFFF,d0
                lsl.l   #2,d0                ; octets de contenu
                addq.l  #8,d0                ; + en-tête [taille][next]
                move.l  d0,d7                ; d7 = taille d'alloc (sauvée)
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                btst    #0,d3
                beq.s   .no_chip
                or.l    #MEMF_CHIP,d1        ; hunk CHIP (BSS/données DMA du programme)
.no_chip:
                btst    #1,d3
                beq.s   .no_fast
                or.l    #MEMF_FAST,d1
.no_fast:
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fail_mem            ; alloc KO -> libérer les segments déjà faits
                move.l  d0,a0                ; a0 = bloc
                move.l  d7,(a0)              ; bloc[0] = taille d'alloc
                move.l  a0,d1
                addq.l  #8,d1                ; contenu = bloc+8
                move.l  d2,d0
                lsl.l   #2,d0
                move.l  d1,0(a4,d0.l)        ; contentAddr[i] = bloc+8
                move.l  a0,d1
                addq.l  #4,d1
                lsr.l   #2,d1                ; d1 = BPTR_i = (bloc+4)>>2
                tst.l   d6
                bne.s   .chain
                move.l  d1,d5                ; 1er -> BPTR de retour
                bra.s   .chain_prev
.chain:
                move.l  d6,a0
                move.l  d1,4(a0)             ; bloc_préc[4] = BPTR_i
.chain_prev:
                move.l  d1,d6
                lsl.l   #2,d6
                subq.l  #4,d6                ; d6 = ce bloc (= BPTR<<2 - 4)
                addq.l  #1,d2
                bra.s   .alloc_loop
.alloc_done:
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                ; --- corps : contenu + relocations, jusqu'à la fin des données ---
                moveq   #0,d2                ; hidx = 0 (first==0 validé)
.body_loop:
                bsr     ls_rdl               ; id de hunk
                tst.w   LR_EOF(a5)
                bne     .body_done           ; fichier consommé
                and.l   #$3FFFFFFF,d0        ; l'id recopie les flags mémoire (ex. $400003EB = BSS chip)
                cmp.l   #HUNK_CODE,d0
                beq.s   .b_content
                cmp.l   #HUNK_DATA,d0
                beq.s   .b_content
                cmp.l   #HUNK_BSS,d0
                beq.s   .b_bss
                cmp.l   #HUNK_RELOC32,d0
                beq     .b_reloc
                cmp.l   #HUNK_END,d0
                beq.s   .b_end
                cmp.l   #HUNK_NAME,d0
                beq.s   .b_skip
                cmp.l   #HUNK_DEBUG,d0
                beq.s   .b_skip
                cmp.l   #HUNK_SYMBOL,d0
                beq.s   .b_symbol
                bra     .fail_fmt            ; hunk non supporté ($3FC, overlay...) -> échec propre
.b_skip:                                     ; NAME / DEBUG : [nlongs][données] ignorés
                bsr     ls_rdl
                lsl.l   #2,d0
                bsr     ls_skip
                bra.s   .b_chk
.b_symbol:                                   ; SYMBOL : ([nlongs du nom][nom][valeur])* puis 0, ignoré
                bsr     ls_rdl
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                tst.l   d0
                beq.s   .body_loop
                addq.l  #1,d0                ; nom + valeur
                lsl.l   #2,d0
                bsr     ls_skip
                bra.s   .b_symbol
.b_bss:
                bsr     ls_rdl               ; nlongs (pas de data ; mémoire déjà CLEAR)
                bra.s   .b_chk
.b_end:
                addq.l  #1,d2                ; hunk suivant
                bra     .body_loop
.b_content:
                cmp.l   d4,d2
                bhs     .fail_fmt            ; plus de hunks de contenu que déclarés -> corrompu
                bsr     ls_rdl               ; nlongs
                move.l  d2,d1
                lsl.l   #2,d1
                move.l  0(a4,d1.l),a0        ; dest = contentAddr[hidx]
                lsl.l   #2,d0
                bsr     ls_rdbytes
.b_chk:
                tst.w   LR_EOF(a5)
                bne     .fail_fmt            ; fin des données au milieu d'un hunk
                bra     .body_loop
.b_reloc:
                bsr     ls_rdl               ; count
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                tst.l   d0
                beq     .body_loop           ; 0 -> fin du bloc RELOC32
                move.l  d0,d7                ; d7 = count
                cmp.l   d4,d2
                bhs     .fail_fmt            ; RELOC32 hors d'un hunk déclaré -> corrompu
                bsr     ls_rdl               ; hunk référencé
                cmp.l   d4,d0
                bhs     .fail_fmt            ; référence vers un hunk inexistant -> corrompu
                lsl.l   #2,d0
                move.l  0(a4,d0.l),d3        ; d3 = contentAddr[ref] (addend)
                move.l  d2,d0
                lsl.l   #2,d0
                move.l  0(a4,d0.l),a2        ; a2 = contentAddr[hidx] (base à patcher)
.rl_off:
                bsr     ls_rdl               ; offset dans le hunk courant
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                ifeq    D2_NO_RELOC
                add.l   d3,0(a2,d0.l)        ; *(contentAddr[hidx]+offset) += contentAddr[ref]
                endc                         ; RED D2_NO_RELOC : saute l'application (offset quand même lu)
                subq.l  #1,d7
                bne.s   .rl_off
                bra.s   .b_reloc             ; bloc (count,ref,offsets) suivant
.body_done:
                move.l  a4,a1                ; succès : libère contentAddr (temp)
                move.l  d4,d0
                lsl.l   #2,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d5,d0                ; renvoie BPTR 1er segment
                bra.s   .ret
.fail_mem:
                moveq   #ERROR_NO_FREE_STORE,d7
                bra.s   .fail
.fail_fmt:
                moveq   #ERROR_FILE_NOT_OBJECT,d7
.fail:
                move.l  d5,d0                ; libère les segments déjà alloués (chaîne BPTR)
                bsr     dos_unloadseg
                move.l  a4,d0
                beq.s   .fail_ret
                move.l  a4,a1                ; libère contentAddr
                move.l  d4,d0
                lsl.l   #2,d0
                jsr     LVO_FREEMEM(a6)
.fail_ret:
                move.l  d7,d1
                moveq   #0,d0
.ret:
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ls_rdl(a5 = lecteur) -> d0 = long suivant (0 et LR_EOF posé s'il manque des octets). Clobbe d1/a0/a1.
ls_rdl:
                clr.l   -(sp)
                move.l  sp,a0
                moveq   #4,d0
                bsr.s   ls_rdbytes
                move.l  (sp)+,d0
                rts

; ls_skip(d0 = octets, a5 = lecteur) : saute d0 octets (relus dans le tampon). Clobbe d0/d1/a0/a1.
ls_skip:
                sub.l   a0,a0                ; destination nulle : rien n'est recopié
; ls_rdbytes(a0 = destination | 0, d0 = octets, a5 = lecteur) : copie d0 octets du flux ; LR_EOF posé si le flux se
; termine avant. Clobbe d0/d1/a0/a1.
ls_rdbytes:
                movem.l d2-d3/a2,-(sp)
                move.l  a0,a2                ; a2 = destination
                move.l  d0,d2                ; d2 = reste à lire
.rb_lp:
                tst.l   d2
                beq.s   .rb_ret
                move.l  LR_LEN(a5),d1
                sub.l   LR_POS(a5),d1        ; d1 = disponible dans le tampon
                bne.s   .rb_copy
                tst.l   LR_FH(a5)
                beq.s   .rb_eof
                move.l  a2,d0                ; tampon vide, gros bloc vers une vraie destination : Read direct
                beq.s   .rb_fill
                cmp.l   LR_CAP(a5),d2
                blo.s   .rb_fill
                move.l  d2,d3
                bsr.s   ls_read              ; d0 = octets lus en (a2)
                tst.l   d0
                ble.s   .rb_eof
                add.l   d0,a2
                sub.l   d0,d2
                bra.s   .rb_lp
.rb_fill:
                move.l  a2,-(sp)
                move.l  LR_BUF(a5),a2
                move.l  LR_CAP(a5),d3
                bsr.s   ls_read
                move.l  (sp)+,a2
                clr.l   LR_POS(a5)
                move.l  d0,LR_LEN(a5)
                bgt.s   .rb_lp
                clr.l   LR_LEN(a5)
.rb_eof:
                st      LR_EOF(a5)
.rb_ret:
                movem.l (sp)+,d2-d3/a2
                rts
.rb_copy:
                cmp.l   d2,d1
                bls.s   .rb_n
                move.l  d2,d1                ; d1 = octets pris dans le tampon
.rb_n:
                sub.l   d1,d2
                move.l  LR_BUF(a5),a0
                add.l   LR_POS(a5),a0
                add.l   d1,LR_POS(a5)
                move.l  a2,d0
                beq.s   .rb_lp               ; saut : rien à recopier
.rb_cp:
                move.b  (a0)+,(a2)+
                subq.l  #1,d1
                bne.s   .rb_cp
                bra.s   .rb_lp

; ls_read(a2 = destination, d3 = octets, a5 = lecteur) -> d0 = Read(LR_FH, a2, d3) via LR_DOS. Clobbe d0/d1/a0/a1.
ls_read:
                movem.l d2/a6,-(sp)
                move.l  LR_DOS(a5),a6
                move.l  LR_FH(a5),d1
                move.l  a2,d2
                jsr     DOS_LVO_READ(a6)
                movem.l (sp)+,d2/a6
                rts

; dos_unloadseg(a6=SysBase, d0=BPTR 1er segment) : libère la chaîne de segments (FreeMem bloc+taille). d0=0 -> no-op.
dos_unloadseg:
                movem.l d2,-(sp)
                move.l  d0,d2                ; d2 = BPTR courant
.ul_loop:
                tst.l   d2
                beq.s   .ul_done
                move.l  d2,d0
                lsl.l   #2,d0                ; d0 = BPTR<<2 = &next (= bloc+4)
                move.l  d0,a1
                move.l  (a1),d2              ; d2 = next BPTR (lu avant de libérer)
                subq.l  #4,d0
                move.l  d0,a1                ; a1 = bloc
                move.l  (a1),d0              ; d0 = taille (bloc[0])
                jsr     LVO_FREEMEM(a6)
                bra.s   .ul_loop
.ul_done:
                movem.l (sp)+,d2
                rts
