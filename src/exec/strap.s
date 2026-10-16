; src/exec/strap.s — strap (romboot) : décision de boot (M6r, 1er maillon de la chaîne de boot disquette).
; strap_boot(a6=SysBase) -> d0 = 0 si AUCUN volume bootable (l'appelant affiche l'écran insert-disk),
;                           d0 != 0 si un volume a été bouté (un vrai boot ne revient pas à l'appelant).
;
; M6r = ÉCHAFAUDAGE : la décision d'afficher l'écran de boot est désormais ROUTÉE par le strap (plus inconditionnelle),
; mais aucun volume n'est encore bootable (pas de trackdisk) -> renvoie toujours 0. Le VRAI déclencheur 1.3 (l'écran
; apparaît PARCE QUE la lecture du bootblock de DF0: échoue) arrive avec trackdisk : l'incrément B/C insérera ici
; FindName("trackdisk.device") + OpenDevice + CMD_READ du bootblock (2 secteurs) + validation (checksum + magic
; « DOS ») + saut à BB_ENTRY. Tant que ça n'existe pas, la bonne décision est « non bootable -> insert-disk ».
;
; Déviation clean-room assumée : mécanisme de boot interne propre (le vrai 1.3 n'expose pas `AddBootNode`, qui est
; V36/2.0+) ; on reproduit le COMPORTEMENT observable (pas de disque bootable -> insert-disk), pas l'interne du ROM.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs exec/expansion + devices/bootblock.i (public). AUCUNE lecture ROM.

                include "exec.i"

                xdef    strap_boot

; STRAP_FAKE_BOOTDEV=1 (RED) : simule un boot réussi -> strap retourne « bouté » (d0!=0) -> l'appelant NE montre PAS
; l'insert-disk (comportement FAUX) -> marqueurs M6R/M6S absents + écran vide. Isole le ROUTAGE de l'écran par la
; décision du strap (le bon comportement = montrer l'insert-disk quand rien n'est bootable). Défaut 0.
STRAP_FAKE_BOOTDEV EQU 0

strap_boot:
                ifne    STRAP_FAKE_BOOTDEV
        moveq   #1,d0               ; RED : prétend avoir bouté DF0: -> aucun insert-disk
        rts
                endc
        ; Incrément B/C insérera ici : FindName("trackdisk.device") + OpenDevice + CMD_READ(bootblock) + validation
        ; (checksum + magic « DOS ») + saut à BB_ENTRY. D'ici là, aucun volume n'est bootable.
        moveq   #0,d0               ; aucun volume bootable -> l'appelant affiche l'écran insert-disk
        rts
