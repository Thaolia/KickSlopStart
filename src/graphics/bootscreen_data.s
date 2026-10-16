; src/graphics/bootscreen_data.s — donnees GENEREES par mk_bootscreen.py. NE PAS editer a la main.
; Palette OCS (32x RGB444) + 5 bitplanes planar (plan 0 = LSB) de l'ecran de boot (chaton KickSlopStart).

                xdef    bootscreen_palette
                xdef    bootscreen_planes

bootscreen_palette:
        dc.w    $EEE,$CCB,$AAA,$AA9,$AA9,$AA9,$999,$999
        dc.w    $A98,$998,$899,$888,$678,$678,$765,$578
        dc.w    $765,$666,$567,$555,$643,$445,$642,$522
        dc.w    $345,$333,$222,$111,$211,$000,$000,$000
        EVEN
bootscreen_planes:
        incbin  "bootscreen.raw"
        EVEN
