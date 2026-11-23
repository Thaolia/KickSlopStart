; src/exec/relay.i - chip RAM relay of a soft-kicked image in Zorro II fast RAM (shared by the image and the
; soft-kick bootblock, src/softkick/bootblock.s).
; A reset de-configures the autoconfig boards, so the fast RAM holding the image is gone when the Kickstart in ROM
; calls ColdCapture. ColdCapture therefore points at a relay in low chip RAM: it gives each recorded board its
; address again, checks the image and jumps into it. The record is written by the bootblock from the host's board
; list; the image's expansion.library rebuilds its ConfigDevs from it (src/exec/expansion.s, exp_replay) instead of
; looking for those boards at $E80000, where they no longer answer.
; The area sits in the cushion below LOWHEAP_LO: never in a free list, and kept by coldstart's low-RAM clear.

RELAY_LO    EQU $00000C00
RELAY_HI    EQU $00001000
RL_MAGIC    EQU 0                ; RL_MAGIC_V when the record is valid
RL_IMAGE    EQU 4                ; load address of the image (its relocated kick_base)
RL_COUNT    EQU 8                ; UWORD: entries, in chain order
RL_ENTRIES  EQU $10
RE_ROM      EQU 0                ; struct ExpansionRom as in cd_Rom (16 bytes: er_Type as read, the rest logical)
RE_SLOT     EQU 16               ; UWORD: cd_BoardAddr >> 16
RE_FLAGS    EQU 18               ; UWORD: cd_Flags in the low byte (CDB_SHUTUP)
RE_SIZE     EQU 20
RL_MAXENT   EQU 8
RL_HDRSIZE  EQU RL_ENTRIES+RL_MAXENT*RE_SIZE
RL_CODE     EQU $100             ; relay code, copied there by the image at each boot
RL_CODEMAX  EQU RELAY_HI-RELAY_LO-RL_CODE
RL_MAGIC_V  EQU $4B535352        ; "KSSR"
RL_ZBASE    EQU $00200000        ; Zorro II memory space [RL_ZBASE, RL_ZEND)
RL_ZEND     EQU $00A00000
