; src/intuition/intuition.i — layout IntuitionBase V34 + constantes M5.
; Piste IMPLÉMENTATION (« clean ») : NDK intuition.i/intuitionbase.i + intuition_lib.fd (public). AUCUNE lecture ROM.
; LIB_SIZE est défini dans exec.i (inclus AVANT ce fichier).

; --- IntuitionBase : champs publics 1re génération (stables V34 ; intuitionbase.i) ---
; ib_LibNode = base Library ; ib_ViewLord = View embarqué d'intuition (le « ViewLord », renvoyé par ViewAddress).
IB_VIEWLORD      EQU LIB_SIZE          ; 34 : struct View embarquée (v_SIZEOF = 18)
IB_ACTIVEWINDOW  EQU IB_VIEWLORD+18    ; 52
IB_ACTIVESCREEN  EQU IB_ACTIVEWINDOW+4 ; 56
IB_FIRSTSCREEN   EQU IB_ACTIVESCREEN+4 ; 60 : Screen frontal (liste front->back)
IB_FLAGS         EQU IB_FIRSTSCREEN+4  ; 64
IB_MOUSEY        EQU IB_FLAGS+4        ; 68
IB_MOUSEX        EQU IB_MOUSEY+2       ; 70
IB_SECONDS       EQU IB_MOUSEX+2       ; 72
IB_MICROS        EQU IB_SECONDS+4      ; 76
INTUITIONBASE_SIZE EQU IB_MICROS+4     ; 80 : dataSize pour MakeLibrary

; --- LVO intuition.library (lvo/intuition_lib.i, autoritatif) ---
LVO_VIEWADDRESS  EQU -294              ; ViewAddress() -> View courant (vecteur 49)

; --- struct Gadget / struct Requester (NDK intuition/intuition.i) — requester insert-disk cliquable ---
GG_NEXTGADGET EQU 0
GG_LEFTEDGE   EQU 4             ; WORD (relatif au requester)
GG_TOPEDGE    EQU 6             ; WORD
GG_WIDTH      EQU 8             ; WORD
GG_HEIGHT     EQU 10            ; WORD
GG_FLAGS      EQU 12            ; UWORD
GG_ACTIVATION EQU 14           ; UWORD
GG_GADGETTYPE EQU 16           ; UWORD
GG_SIZEOF     EQU 44
BOOLGADGET    EQU 1             ; gg_GadgetType : bouton booléen
RQ_OLDERREQ   EQU 0
RQ_LEFTEDGE   EQU 4             ; WORD
RQ_TOPEDGE    EQU 6             ; WORD
RQ_WIDTH      EQU 8             ; WORD
RQ_HEIGHT     EQU 10            ; WORD
RQ_REQGADGET  EQU 16           ; APTR liste de gadgets
RQ_REQTEXT    EQU 24           ; APTR texte
RQ_SIZEOF     EQU 112
; REQ_NO_HITTEST=1 (RED requester) : req_input_handler ne fait PAS le hit-test -> un clic DANS le gadget ne pose pas
; REQ_HIT -> « REQUESTER CLICK OK » absent. Isole le hit-test du gadget. Défaut 0.
REQ_NO_HITTEST EQU 0

; M5 : intuition.library comme module résident (squelette + ViewAddress). M5I_BAD_VIEWADDR=1 (RED) : ViewAddress
; renvoie 0 au lieu de &ib_ViewLord -> la preuve « ViewAddress()==IntuitionBase+34 » échoue -> « M5I INTUI LIB OK »
; absent. Isole la primitive neuve (le routage NT_LIBRARY->LibList est déjà RED-prouvé par M4C1_WRONG_TYPE).
; Défaut 0 (inerte).
M5I_BAD_VIEWADDR EQU 0
