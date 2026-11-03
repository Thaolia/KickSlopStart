# KickSlopStart ROM images

Production ROM of each release, built by the release workflow. KickSlopStart.rom is the latest one
(v0.2.17). This branch exists so that browser emulators can load the ROM (CORS).

KickSlopStart.adf is the soft-kick disk of the same release: booted on an A500 with its Kickstart 1.3
and 512 KB of slow RAM ($C00000), it loads KickSlopStart into that RAM and starts it. A reset comes
back to KickSlopStart; switching the machine off returns to the Kickstart in ROM.
