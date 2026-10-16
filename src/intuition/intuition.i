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

; M5 : intuition.library comme module résident (squelette + ViewAddress). M5I_BAD_VIEWADDR=1 (RED) : ViewAddress
; renvoie 0 au lieu de &ib_ViewLord -> la preuve « ViewAddress()==IntuitionBase+34 » échoue -> « M5I INTUI LIB OK »
; absent. Isole la primitive neuve (le routage NT_LIBRARY->LibList est déjà RED-prouvé par M4C1_WRONG_TYPE).
; Défaut 0 (inerte).
M5I_BAD_VIEWADDR EQU 0
