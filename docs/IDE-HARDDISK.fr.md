# Disque dur IDE de l'A600/A1200

*[English version](IDE-HARDDISK.md)*

KickSlopStart a un pilote pour le port IDE interne de l'A600 et de l'A1200 (`scsi.device`, unités 0 et 1). Il ne
démarre que si la puce Gayle de la machine répond, donc rien ne change sur un A500 ou un A2000. Il fonctionne de la
même façon dans la ROM et dans l'image de soft-kick : un A600 ou un A1200 lancé en soft-kick depuis son propre
Kickstart lit son disque dur ou sa carte CF.

- Les partitions du Rigid Disk Block du disque sont montées en DH0:, DH1:, etc., sous les noms donnés par l'outil de
  partitionnement, en OFS ou en FFS (DOS\0 à DOS\3, modes internationaux compris), en lecture et en écriture.
- Un disque ou une carte CF préparé sur PC (sans RDB) est lu aussi : les partitions primaires FAT12, FAT16 et FAT32
  de son MBR, ou la carte entière quand elle a été formatée sans table de partitions, sont montées en FAT0:, FAT1:,
  etc., **en lecture seule** (une écriture fait apparaître la requête « is write protected »). Les noms longs sont
  affichés quand ils font au plus 30 caractères (la limite d'AmigaDOS), sinon le nom 8.3 ; les deux noms ouvrent le
  fichier, quelle que soit la casse. Une partition qui finit au-delà de 4 Go n'est pas montée, pas plus que les
  partitions étendues ou l'exFAT.
- Elles sont seulement montées : la machine démarre toujours sur une disquette, même si une partition est marquée
  bootable, parce que la partition de boot d'un A600 contient en général un Workbench 2.x/3.x qui ne peut pas tourner
  sur un système 1.3.
- Non pris en charge : WHDLoad (il exige le Kickstart 2.0, comme avec la vraie 1.3), PFS3, SFS et les autres systèmes
  de fichiers tiers, DOS\4 à DOS\7 (caches de répertoires, noms longs), les disques de plus de 4 Go, les cartes
  PCMCIA, le port IDE de l'A4000.
- Les transferts se font en PIO par scrutation, un bloc de 512 octets à la fois dans le système de fichiers : environ
  115 Ko/s sur un 68000 en émulation, cinq fois une disquette.
- La mémoire ne grandit pas avec la partition : environ 4 octets par bloc de bitmap plus un cache de 8 blocs (une
  partition de 1,1 Go coûte environ 6 Ko). Reconstruire le bitmap d'une grosse partition après un plantage prend
  quelques minutes.
- Testé en émulation (Amiberry, profils A600 et A1200) avec notre ROM comme hôte et avec un Kickstart 3.1 comme hôte
  du soft-kick, sur des partitions de 8 Mo à 3,9 Go ; pas encore essayé sur une vraie machine, les retours sont
  bienvenus. Les tests de non-régression sont `tests/ide_rdb_probe.sh` (partitions RDB, lecture et écriture) et
  `tests/fatfs_probe.sh` (FAT).

Le même système de fichiers lit et écrit aussi les disquettes FFS (formatées sous 2.x/3.x), sur n'importe quelle
machine, et lit un hardfile UAE qui contient un système de fichiers FAT. Les disquettes PC (720 Ko) ne sont pas lues :
leurs pistes ont un autre format.
