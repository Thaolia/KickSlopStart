; tests/busywait_probe.s - CLI command that never calls exec: it counts in a loop forever (REMAINING-WORK A13).
; Started with Run by tests/busywait_probe.sh, it must not keep the shell's "Wait 5" from ending.
        section code,code
start:  addq.l  #1,counter
        bra.s   start
        section data,data
counter: dc.l   0
