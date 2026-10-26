; src/exec/io.s — exec : entrées/sorties device (OpenDevice, CloseDevice, DoIO, SendIO, CheckIO, WaitIO, AbortIO)
; et copies mémoire (CopyMem, CopyMemQuick : L:Ram-Handler copie toutes ses données par CopyMem).
; Requis par les handlers BCPL du disque (L:Newcon-Handler, L:Aux-Handler, L:Port-Handler : globales opendevice,
; doio, sendio) et par tout programme qui ouvre un device.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs exec (OpenDevice/DoIO/SendIO/CheckIO/WaitIO/AbortIO) + exec/io.i.
; AUCUNE lecture ROM.

                include "exec.i"

                xdef    exec_OpenDevice
                xdef    exec_CloseDevice
                xdef    exec_DoIO
                xdef    exec_SendIO
                xdef    exec_CheckIO
                xdef    exec_WaitIO
                xdef    exec_AbortIO
                xdef    exec_CopyMem
                xdef    exec_CopyMemQuick
                xdef    exec_AddLibrary
                xdef    exec_RemLibrary
                xdef    exec_AddDevice
                xdef    exec_RemDevice
                xref    ram_loadmodule   ; ramlib.s

IOF_QUICK       EQU 1
DEV_OPEN        EQU -6
DEV_CLOSE       EQU -12
DEV_BEGINIO     EQU -30
DEV_ABORTIO     EQU -36

; OpenDevice(nom a0, unité d0, iorequest a1, flags d1) -> d0 = io_Error (0 = succès). Sous Forbid : FindName dans la
; DeviceList, io_Device := device, io_Error := 0, puis le vecteur Open du device (a6 = device, a1/d0/d1 transmis).
; Device absent : chargé depuis DEVS: (ram_loadmodule, appelant process) ; sinon io_Error = IOERR_OPENFAIL.
exec_OpenDevice:
        movem.l d2-d3/a2-a3/a6,-(sp)
        move.l  a1,a2                ; a2 = iorequest
        move.l  d0,d2                ; d2 = unité
        move.l  d1,d3                ; d3 = flags
        move.l  a0,a3                ; a3 = nom
        jsr     LVO_FORBID(a6)
        lea     EB_DEVICELIST(a6),a0
        move.l  a3,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .od_found
        jsr     LVO_PERMIT(a6)       ; absent : chargement depuis DEVS: (ramlib), hors Forbid
        lea     od_devsdir(pc),a0
        move.l  a3,a1
        jsr     ram_loadmodule
        jsr     LVO_FORBID(a6)
        tst.l   d0
        beq.s   .od_nodev
        lea     EB_DEVICELIST(a6),a0
        move.l  a3,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .od_found
.od_nodev:
        move.b  #IOERR_OPENFAIL,IO_ERROR(a2)
        bra.s   .od_done
.od_found:
        move.l  d0,IO_DEVICE(a2)
        clr.b   IO_ERROR(a2)
        move.l  a6,-(sp)
        move.l  d0,a6
        move.l  a2,a1
        move.l  d2,d0
        move.l  d3,d1
        jsr     DEV_OPEN(a6)
        move.l  (sp)+,a6
.od_done:
        jsr     LVO_PERMIT(a6)
        move.b  IO_ERROR(a2),d0
        ext.w   d0
        ext.l   d0
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

od_devsdir:
        dc.b    "DEVS:",0
        even

; CloseDevice(iorequest a1) : vecteur Close du device de la requête.
exec_CloseDevice:
        move.l  a6,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a6,-(sp)
        move.l  IO_DEVICE(a1),a6
        jsr     DEV_CLOSE(a6)
        move.l  (sp)+,a6
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; DoIO(iorequest a1) -> d0 = io_Error : BeginIO en mode rapide (IOF_QUICK), puis WaitIO si le device a mis la
; requête en file.
exec_DoIO:
        move.l  a1,-(sp)
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        bsr.s   io_beginio
        move.l  (sp)+,a1
        bra     exec_WaitIO

; SendIO(iorequest a1) : BeginIO asynchrone (la réponse arrivera sur mn_ReplyPort).
exec_SendIO:
        clr.b   IO_FLAGS(a1)
io_beginio:
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.l  a6,-(sp)
        move.l  IO_DEVICE(a1),a6
        jsr     DEV_BEGINIO(a6)
        move.l  (sp)+,a6
        rts

; CheckIO(iorequest a1) -> d0 = a1 si la requête est terminée (rapide ou répondue), sinon 0.
exec_CheckIO:
        moveq   #0,d0
        btst    #0,IO_FLAGS(a1)      ; IOF_QUICK
        bne.s   .ci_done
        cmp.b   #NT_REPLYMSG,LN_TYPE(a1)
        bne.s   .ci_ret
.ci_done:
        move.l  a1,d0
.ci_ret:
        rts

; WaitIO(iorequest a1) -> d0 = io_Error : attend la réponse (Wait sur le bit du reply port) puis retire la requête
; du port (sous Disable : la réponse peut venir d'une interruption).
exec_WaitIO:
        move.l  a2,-(sp)
        move.l  a1,a2
        btst    #0,IO_FLAGS(a2)
        bne.s   .wi_err
.wi_wait:
        cmp.b   #NT_REPLYMSG,LN_TYPE(a2)
        beq.s   .wi_got
        move.l  MN_REPLYPORT(a2),a0
        moveq   #0,d1
        move.b  MP_SIGBIT(a0),d1
        moveq   #0,d0
        bset    d1,d0
        jsr     LVO_WAIT(a6)
        bra.s   .wi_wait
.wi_got:
        jsr     LVO_DISABLE(a6)
        move.l  a2,a1
        jsr     LVO_REMOVE(a6)
        jsr     LVO_ENABLE(a6)
.wi_err:
        move.b  IO_ERROR(a2),d0
        ext.w   d0
        ext.l   d0
        move.l  (sp)+,a2
        rts

; AbortIO(iorequest a1) : vecteur AbortIO du device.
exec_AbortIO:
        move.l  a6,-(sp)
        move.l  IO_DEVICE(a1),a6
        jsr     DEV_ABORTIO(a6)
        move.l  (sp)+,a6
        rts

; CopyMem(source a0, destination a1, taille d0) : copie d'octets sans alignement requis (AutoDoc : zones disjointes).
; Par longs quand source et destination ont la même parité, sinon octet par octet. Ne touche que d0/d1/a0/a1.
exec_CopyMem:
        move.l  a0,d1
        add.l   a1,d1                ; bit 0 de la somme = parités différentes
        btst    #0,d1
        bne.s   cm_bytes            ; parités différentes : octets
        move.l  a0,d1
        btst    #0,d1
        beq.s   exec_CopyMemQuick
        tst.l   d0
        beq.s   cm_ret
        move.b  (a0)+,(a1)+          ; aligne sur un mot pair
        subq.l  #1,d0
; CopyMemQuick(source a0, destination a1, taille d0) : source/destination alignées ; longs puis reste en octets.
exec_CopyMemQuick:
        move.l  d0,d1
        lsr.l   #2,d1                ; nombre de longs
        bra.s   .cq_lnext
.cq_long:
        move.l  (a0)+,(a1)+
.cq_lnext:
        subq.l  #1,d1
        bcc.s   .cq_long
        and.l   #3,d0
cm_bytes:
        bra.s   cm_bnext
cm_byte:
        move.b  (a0)+,(a1)+
cm_bnext:
        subq.l  #1,d0
        bcc.s   cm_byte
cm_ret:
        rts

; AddLibrary(library a1) / AddDevice(device a1) : Enqueue dans LibList / DeviceList sous Forbid (un module chargé
; depuis le disque qui fait lui-même son MakeLibrary s'inscrit ainsi). RemLibrary / RemDevice(a1) : appel du
; vecteur Expunge du module (a6 = module) -> d0 = seglist rendue par Expunge (0 si le module refuse).
exec_AddLibrary:
        lea     EB_LIBLIST(a6),a0
        bra.s   io_addnode
exec_AddDevice:
        lea     EB_DEVICELIST(a6),a0
io_addnode:
        movem.l a0-a1,-(sp)
        jsr     LVO_FORBID(a6)
        movem.l (sp)+,a0-a1
        jsr     LVO_ENQUEUE(a6)
        jmp     LVO_PERMIT(a6)
exec_RemLibrary:
exec_RemDevice:
        move.l  a6,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a6,-(sp)
        move.l  a1,a6
        jsr     -18(a6)              ; Expunge
        move.l  (sp)+,a6
        move.l  d0,-(sp)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        move.l  (sp)+,a6
        rts
