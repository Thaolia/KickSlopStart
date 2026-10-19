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

                xdef    dos_loadseg
                xdef    dos_unloadseg
                xdef    ls_load_hunks
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

; ls_load_hunks(a6=SysBase, a0=filebuf, d0=taille) -> d0 = BPTR 1er segment | 0. Parse le format hunk depuis le
; buffer. NE libère PAS filebuf (l'appelant en est propriétaire). Partagé par dos_loadseg (lecture ofs, D2) et
; par le client D3d (buffer lu via dos Open/Read = chargement par packets). a2=curseur, a3=fin, a4=contentAddr[],
; d2=hidx, d4=hunkcount, d5=BPTR 1er segment, d6=bloc précédent, d7=scratch.
ls_load_hunks:
                movem.l d2-d7/a2-a5,-(sp)
                move.l  a0,a2                ; curseur = filebuf
                move.l  a0,a3
                add.l   d0,a3                ; fin = filebuf + taille
                ; --- HUNK_HEADER ---
                bsr     ls_rdl
                cmp.l   #HUNK_HEADER,d0
                bne     .fail_fb
                bsr     ls_rdl               ; resident libs
                tst.l   d0
                bne     .fail_fb             ; != 0 non supporté
                bsr     ls_rdl               ; table_size -> d4
                move.l  d0,d4
                beq     .fail_fb
                cmp.l   #LS_MAXHUNKS,d4
                bhi     .fail_fb
                bsr     ls_rdl               ; first (doit être 0)
                tst.l   d0
                bne     .fail_fb
                bsr     ls_rdl               ; last
                addq.l  #1,d0                ; hunkcount = last+1
                cmp.l   d4,d0
                bhi     .fail_fb             ; hunkcount > table_size -> corrompu
                move.l  d0,d4                ; d4 = hunkcount (= nb de tailles à lire)
                ; contentAddr[] (d4 longs)
                move.l  d4,d0
                lsl.l   #2,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fail_fb
                move.l  d0,a4                ; a4 = contentAddr table
                ; --- allouer chaque segment + chaîner ---
                moveq   #0,d2                ; i
                moveq   #0,d5                ; BPTR 1er segment
                moveq   #0,d6                ; bloc précédent (0 = aucun)
.alloc_loop:
                cmp.l   d4,d2
                bhs.s   .alloc_done
                bsr     ls_rdl               ; champ taille (longs + flags mémoire)
                move.l  d0,d3
                rol.l   #2,d3
                and.l   #3,d3                ; d3 = bits 31-30 -> 1-0 : bit0 = CHIP, bit1 = FAST
                cmp.w   #3,d3
                beq     .fail_segs           ; 11 = attributs étendus (V37+) -> non supporté en 1.3
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
                beq     .fail_segs           ; alloc KO -> libérer les segments déjà faits
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
                ; --- corps : copier le contenu + appliquer les relocations ---
                moveq   #0,d2                ; hidx = 0 (first==0 validé)
.body_loop:
                cmp.l   a3,a2
                bhs     .body_done           ; fichier consommé
                bsr     ls_rdl               ; id de hunk
                and.l   #$3FFFFFFF,d0        ; l'id recopie les flags mémoire (ex. $400003EB = BSS chip)
                cmp.l   #HUNK_CODE,d0
                beq.s   .b_content
                cmp.l   #HUNK_DATA,d0
                beq.s   .b_content
                cmp.l   #HUNK_BSS,d0
                beq.s   .b_bss
                cmp.l   #HUNK_RELOC32,d0
                beq.s   .b_reloc
                cmp.l   #HUNK_END,d0
                beq.s   .b_end
                cmp.l   #HUNK_NAME,d0
                beq.s   .b_skip
                cmp.l   #HUNK_DEBUG,d0
                beq.s   .b_skip
                cmp.l   #HUNK_SYMBOL,d0
                beq.s   .b_symbol
                bra     .fail_segs           ; hunk non supporté ($3FC, overlay...) -> échec propre
.b_skip:                                     ; NAME / DEBUG : [nlongs][données] ignorés
                bsr     ls_rdl
                lsl.l   #2,d0
                add.l   d0,a2
                bra     .body_loop
.b_symbol:                                   ; SYMBOL : ([nlongs du nom][nom][valeur])* puis 0, ignoré
                bsr     ls_rdl
                tst.l   d0
                beq     .body_loop
                addq.l  #1,d0                ; nom + valeur
                lsl.l   #2,d0
                add.l   d0,a2
                bra.s   .b_symbol
.b_bss:
                bsr     ls_rdl               ; nlongs (pas de data ; mémoire déjà CLEAR)
                bra.s   .body_loop
.b_end:
                addq.l  #1,d2                ; hunk suivant
                bra.s   .body_loop
.b_content:
                cmp.l   d4,d2
                bhs     .fail_segs           ; plus de hunks de contenu que déclarés -> corrompu
                bsr     ls_rdl               ; nlongs
                move.l  d2,d1
                lsl.l   #2,d1
                move.l  0(a4,d1.l),a1        ; dest = contentAddr[hidx]
                move.l  a2,a0                ; src = curseur
                move.l  d0,d1                ; d1 = nlongs
                lsl.l   #2,d0
                add.l   d0,a2                ; avance le curseur après le contenu
                tst.l   d1
                beq     .body_loop
.b_copy:
                move.l  (a0)+,(a1)+
                subq.l  #1,d1
                bne.s   .b_copy              ; copie longword (long-safe, pas de limite 64K)
                bra     .body_loop
.b_reloc:
                bsr     ls_rdl               ; count
                tst.l   d0
                beq     .body_loop           ; 0 -> fin du bloc RELOC32
                move.l  d0,d7                ; d7 = count
                cmp.l   d4,d2
                bhs     .fail_segs           ; RELOC32 hors d'un hunk déclaré -> corrompu
                bsr     ls_rdl               ; hunk référencé
                cmp.l   d4,d0
                bhs     .fail_segs           ; référence vers un hunk inexistant -> corrompu
                lsl.l   #2,d0
                move.l  0(a4,d0.l),d1        ; d1 = contentAddr[ref] (addend)
                move.l  d2,d0
                lsl.l   #2,d0
                move.l  0(a4,d0.l),a1        ; a1 = contentAddr[hidx] (base à patcher)
.rl_off:
                bsr     ls_rdl               ; offset dans le hunk courant
                ifeq    D2_NO_RELOC
                move.l  a1,a0
                add.l   d0,a0
                add.l   d1,(a0)              ; *(contentAddr[hidx]+offset) += contentAddr[ref]
                endc                         ; RED D2_NO_RELOC : saute l'application (offset quand même lu)
                subq.l  #1,d7
                bne.s   .rl_off
                bra.s   .b_reloc             ; bloc (count,ref,offsets) suivant
.body_done:
                move.l  a4,a1                ; succès : libère contentAddr (temp) ; filebuf appartient à l'appelant
                move.l  d4,d0
                lsl.l   #2,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d5,d0                ; renvoie BPTR 1er segment
                bra.s   .ret
.fail_segs:
                move.l  d5,d0                ; libère les segments déjà alloués (chaîne BPTR)
                bsr     dos_unloadseg
                move.l  a4,a1                ; libère contentAddr
                move.l  d4,d0
                lsl.l   #2,d0
                jsr     LVO_FREEMEM(a6)
.fail_fb:                                    ; échec d'en-tête (rien alloué hormis filebuf, à l'appelant)
.fail0:
                moveq   #0,d0
.ret:
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ls_rdl() -> d0 = long au curseur a2, a2 avancé de 4. Ne touche que d0 (curseur a2). Pas de borne ici : le
; corps vérifie a2 < a3 à chaque tête de boucle ; les sous-lectures (nlongs/count/offsets) font confiance au
; fichier (contrôlé ; les hunks SYMBOL/DEBUG strippés -> format minimal).
ls_rdl:
                move.l  (a2)+,d0
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
