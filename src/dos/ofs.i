; src/dos/ofs.i — constantes OFS (Old File System, D1 lecture seule). Format PUBLIC (ADF-FAQ / AmigaDOS Technical
; Reference) VERROUILLÉ empiriquement sur un ADF de test (asset, PAS la ROM). AUCUNE lecture ROM.
; Bloc de 512 o = 128 longs ; offsets « fin de bloc » = (128 - k) longs.

OFS_BSIZE       EQU 512
OFS_ROOTBLK     EQU 880           ; root block d'un DD (1760 blocs logiques, 0..1759)
OFS_NBLK        EQU 1760          ; nb total de blocs -> bloc valide dans [2,1760) (0/1 = bootblock)
IOREQ_SZ        EQU 48            ; IOStdReq (le block buffer suit à +IOREQ_SZ)

; offsets LONG (en octets depuis le début du bloc)
OFSB_TYPE       EQU 0             ; long[0] : type primaire (T_SHORT=2 / T_DATA=8)
OFSB_HTSIZE     EQU 12            ; long[3] : hash_table_size (root)
OFSB_DSIZE      EQU 12            ; long[3] : data_size (data block OFS) — même offset
OFSB_FIRSTDATA  EQU 16            ; long[4] : first_data (file header)
OFSB_NEXT       EQU 16            ; long[4] : next_data (data block OFS) — même offset
OFSB_HASHTAB    EQU 24            ; long[6] : début de la table de hash (header)
OFSB_DATA       EQU 24            ; data block OFS : octets de données @ +24
OFSB_FILESIZE   EQU 324           ; long[81] (= BSIZE-188) : byte_size d'un file header (taille en octets).
                                  ; Vérifié sur l'ADF de test : kickslop (bloc 866) -> 1024. L'assertion de boot
                                  ; fib_Size==1024 reconfirme (read@324 -> write@124 -> readback). AUCUNE lecture ROM.
OFSB_PROTECT    EQU 320           ; long[80] (= BSIZE-192) : bits de protection (header fichier / répertoire)
OFSB_COMMENT    EQU 328           ; long[82] (= BSIZE-184) : commentaire BCPL (octet longueur + 79 chars max)
OFSB_DAYS       EQU 420           ; long[105] (= BSIZE-92) : DateStamp de modification (jours, minutes, ticks)
OFSB_MINS       EQU 424
OFSB_TICKS      EQU 428
OFSB_NAME       EQU 432           ; long[108] (= (128-20)) : nom BCPL (octet longueur + chars)
OFSB_HASHCHAIN  EQU 496           ; long[124] (= (128-4)) : hash_chain (prochain header même bucket)
OFSB_PARENT     EQU 500           ; long[125] (= (128-3)) : bloc du répertoire parent (0 pour le root)
OFSB_SECTYPE    EQU 508           ; long[127] (= (128-1)) : type secondaire (ST_FILE=-3)
; bitmap d'allocation (root block) — disk-validator (#4), offsets vérifiés sur l'ADF de test
OFSB_BMFLAG     EQU 312           ; long[78] (= BSIZE-200) : bm_flag ($FFFFFFFF = bitmap valide ; 0 = à revalider)
OFSB_BMPAGES    EQU 316           ; long[79] (= BSIZE-196) : bm_pages[0] = n° du 1er bloc bitmap
OFSB_BMBITS     EQU 4             ; bloc bitmap : long[0] = checksum ; les bits démarrent au long[1] (@4)

OFS_T_SHORT     EQU 2             ; type primaire root/header
OFS_T_DATA      EQU 8             ; type primaire data block OFS
OFS_ST_FILE     EQU -3            ; type secondaire d'un fichier
OFS_ST_ROOT     EQU 1             ; type secondaire du root block
OFS_ST_USERDIR  EQU 2             ; type secondaire d'un répertoire utilisateur (sous-rép)
OFS_DMAX        EQU 488           ; octets de données max par data block OFS (BSIZE-24)
OFS_HTMAX       EQU 128           ; borne de hash_table_size (doit être 72 ; rejette un root corrompu)
OFS_HTDEF       EQU 72            ; hash_table_size par défaut (BSIZE/4-56) : les USERDIR laissent long[3]=0 (mesuré)

; traversée de chemin (sous-répertoires, '/'-séparés) — frame local d'ofs_read_file
OFS_COMPMAX     EQU 32            ; longueur max d'un composant de chemin (+NUL) ; noms AmigaDOS <= 30
LF_COMP         EQU 0             ; buffer composant NUL-terminé (OFS_COMPMAX octets)
LF_PATHCUR      EQU 32            ; LONG : curseur courant dans le chemin
LF_LAST         EQU 36            ; BYTE : 1 si le composant courant est le dernier (-> fichier, sinon -> userdir)
OFS_FRAME       EQU 40            ; taille du frame local (pair)
; OFS_NO_SUBDIR=1 (RED) : ofs_split ne traite PAS '/' comme séparateur -> le chemin entier = 1 composant cherché
; dans la racine -> « s/startup-sequence » introuvable -> startup-sequence non lue -> F1BOOTOK/E3 absents. Défaut 0.
OFS_NO_SUBDIR   EQU 0

; OFS_NO_DATACHAIN=1 (RED D1) : la lecture ne suit PAS la chaîne next_data -> seul le 1er data block (488 o) copié
; -> taille retournée == 488 != 1024 -> « D1 OFS READ OK » absent. Isole le chaînage des data blocks OFS. Défaut 0.
OFS_NO_DATACHAIN EQU 0

; OFS_NO_DIRNEXT=1 (RED Lock/Examine) : ofs_dir_next renvoie immédiatement found=0 (fin) -> ExNext ne trouve JAMAIS
; d'entrée -> la partie énumération de « DOS LOCK EXAMINE OK » échoue -> marqueur absent. ofs_read_file (D1) et
; ofs_name_to_block/ofs_fill_fib restent intacts -> « D1 OFS READ OK » VERT = isole l'énumération de répertoire du
; chemin de lecture prouvé. Défaut 0.
OFS_NO_DIRNEXT  EQU 0

; --- état de STREAMING OFS (un par FileHandle ouvert sur DF0:) : lecture incrémentale data-block par data-block,
; SANS buffer whole-file. Un seul AllocMem (SS_ALLOC) détient les champs + l'IOStdReq + un block buffer de 512 o.
; Le handler ne plafonne plus la taille d'un fichier (l'ancien cap DOS_FILEMAX était le buffer whole-file).
SS_TRACKDISK    EQU 0             ; APTR : base trackdisk.device (FindName à l'ouverture)
SS_SIZE         EQU 4             ; LONG : byte_size total (du file header @324)
SS_POS          EQU 8             ; LONG : position absolue courante de lecture
SS_FIRSTDATA    EQU 12            ; LONG : premier data block (rewind sur seek arrière)
SS_CURBLK       EQU 16            ; LONG : data block courant (celui qui commence à SS_BLKBASE)
SS_BLKBASE      EQU 20            ; LONG : offset absolu du début des données de SS_CURBLK
SS_IOREQ        EQU 24            ; IOStdReq (IOREQ_SZ o) ; le block buffer suit à +IOREQ_SZ (OFS_BSIZE o)
SS_ALLOC        EQU SS_IOREQ+IOREQ_SZ+OFS_BSIZE   ; taille AllocMem totale de l'état

; STREAM_CAP32K=1 (RED streaming) : ofs_stream_read re-plafonne la lecture à 32768 o (= l'ancien cap whole-file)
; -> un fichier > 32 Ko (BigData, 48000 o) est tronqué -> « OFS STREAM OK » absent. Tous les fichiers < 32 Ko
; (kickslop/d3dtest/e3cmd/bigseg/startup-sequence) restent lus en ENTIER -> D3B/D3C/D3D/E3/F1/D3E/LOADSEG BIG
; restent VERTS = isole PRÉCISÉMENT le relèvement du cap (le payoff du streaming) du reste du chemin de lecture. Défaut 0.
STREAM_CAP32K   EQU 0
