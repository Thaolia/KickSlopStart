# D3 — Design : dos.library packets / handler / process → « exécuter une commande »

> Piste IMPLÉMENTATION (« clean »). Design validé (user, 2026-10-17) **approche 1** : ABI packet
> observable fidèle, processes en C (pas de runtime BCPL interne) — comme AROS `rom/dos` et la 2.0.
> Entrées : `docs/analysis/dos-v34-spec.md` + `dos-boot-sequence.md` (piste analyse, relues, sans code),
> docs publiques (RKRM/NDK/`dos_lib.fd`), AROS `rom/dos` (lecture seule). **Aucune lecture ROM.**
> Cible : dos ouvre/lit un fichier À TRAVERS un process file-handler via DOS packets, et charge+exécute
> UN exécutable depuis DF0: via dos. **PAS** de shell interactif, **PAS** le bootstrap bootblock→dos réel.

## Contraintes V34 à respecter (de la spec analyse)
- **Pas de `DoPkt`/`SendPkt`/`WaitPkt` public en V34** → échange packet en interne via `PutMsg`/`WaitPort`/
  `GetMsg` exec (helper `dos_sendpkt`). Jump table dos = 37 LVO (-6..-222).
- `Open()` mode = code ACTION (`MODE_OLDFILE 1005 = ACTION_FINDINPUT` ; `READ='R'=82` ; `END=1007`).
- `FileHandle` 44 o : `fh_Type`@0x08 = MsgPort du handler (APTR, pas de `fh_Port`) ; `fh_Arg1`@0x24 = clé
  privée fichier côté handler. `DosPacket` 48 o, `StandardPacket` 68 o (`sp_Msg` 20 + `sp_Pkt` 48).
- Frontières V34 (ne pas déborder) : `Process` → `pr_WindowPtr` (~188 o ; `pr_MsgPort`@0x5C, `pr_SegList`@0x80,
  `pr_CurrentDir`@0x98, `pr_CLI`@0xAC) ; `RootNode` → `rn_FileHandlerSegment` (~32) ; `DosInfo` → `di_NetHand`
  (~20 ; `di_DevInfo`@0x04 ; liste device sous Forbid/Permit, pas de sémaphores). `DeviceNode` 44 o
  (`dn_Next`@0, `dn_Task`@0x08 = port handler, `dn_SegList`@0x20, `dn_Name`@0x28 BSTR).
- **Asymétrie BPTR/APTR** : `Open`→BPTR FileHandle (BADDR=×4 pour déréférencer) ; `CreateProc`/`DeviceProc`→
  APTR MsgPort (PAS de BADDR ; `Process = port − 92`). BSTR = BPTR→chaîne longueur-préfixée.
- Packet cycle : remplir `dp_Type`/`dp_Arg*` + **`dp_Port = &caller.pr_MsgPort`** (re-rempli à chaque envoi) ;
  `PutMsg` au port du handler ; `WaitPort`/`GetMsg` sur le port de réponse ; lire `dp_Res1`/`dp_Res2`.

## Composants (src/dos/, prouvés depuis le scaffold de boot, marqueurs série, gatés disque d4)
1. **Process + CreateProc** (`process.s`) : `Process` = `Task` exec + `pr_MsgPort` embarqué @0x5C + champs V34
   jusqu'à `pr_WindowPtr`. `CreateProc(name,pri,segList,stack)` : AllocMem(Process + pile), init Task
   (tc_SPLower/Upper/SPReg), init `pr_MsgPort` (AllocSignal pour le SigBit, type NT_MSGPORT), `AddTask`
   avec l'entrée = corps du process, renvoie l'**APTR** `&pr_MsgPort`.
2. **`dos_sendpkt`** (helper interne) : monte un `StandardPacket`, `dp_Port=&réponse`, `PutMsg(handlerPort)`,
   `WaitPort(réponse)`/`GetMsg`, renvoie `dp_Res1` (+ `dp_Res2` dans pr_Result2/IoErr).
3. **File-handler DF0:** (`handler.s`) : corps de process qui boucle `WaitPort`/`GetMsg` sur son `pr_MsgPort`,
   sert `FINDINPUT`/`READ`/`END` via `ofs.s` (D1). Simplification assumée : `FINDINPUT` lit le fichier ENTIER
   via `ofs_read_file` dans un buffer handler, `fh_Arg1` → {buffer, taille, pos} ; `READ` copie buffer+pos ;
   `END` libère. (Lectures incrémentales OFS différées.)
4. **dos user-facing** (`dos_lib.s`, étendu M6d) : `Open`(-30)/`Read`(-42)/`Close`(-36) fabriquent les packets
   (via `dos_sendpkt`), résolvent DF0: par `di_DevInfo`→`dn_Task`, posent `fh_Type`/`fh_Arg1`.
5. **Câblage** : étendre l'init M6d (`DosBase`/`RootNode`/`DosInfo`) pour monter un `DeviceNode` DF0: dont
   `dn_Task` = le port du handler D3b.

## Flux Open→Read→Close
`Open("kickslop",OLDFILE)` → résout DF0: → alloue FileHandle (aligné 4), `fh_Type=dn_Task` → packet
`FINDINPUT(ARG1=BPTR(FileHandle), ARG2=0 lock, ARG3=BSTR nom)` → handler ouvre (clé → `fh_Arg1`), `dp_Res1=
DOSTRUE` → renvoie BPTR(FileHandle). `Read(fh,buf,len)` → `READ(fh_Arg1,buf,len)` → octets dans `dp_Res1`
(0=EOF, -1=err). `Close(fh)` → `END(fh_Arg1)` → libère FileHandle.

## Décomposition (chacun GREEN/RED/NODISK/COOP, committé)
- **D3a** — Process + CreateProc + round-trip packet. Handler « echo » trivial + client (boot task + reply port
  temporaire) envoie un packet, reçoit la réponse. Marqueur `D3A`. RED : réponse non renvoyée → absent.
- **D3b** — process file-handler DF0: servant FINDINPUT/READ/END via ofs.s. Envoi direct des packets → relit
  « KickSlop » (1024 o, marqueurs @0/488/976). Marqueur `D3B`. RED : READ non servi → octets faux → absent.
- **D3c** — dos `Open`/`Read`/`Close` (LVO) via packets + DeviceNode DF0: monté ; **appelé depuis un process
  client** (CreateProc'd, car dos exige ThisTask=Process pour `pr_MsgPort`). Marqueur `D3C`. RED : `Open` ne
  pose pas `fh_Type` → routage KO → absent.
- **D3d** — `LoadSeg` re-câblé à travers dos `Open`/`Read` (handler/packets) + exécuter « D2Test ». Marqueur =
  « D2LOADSEG OK » émis par la commande chargée par le chemin packet complet. RED : chemin cassé → absent.

## Robustesse / erreurs
`FINDINPUT` échec nom → `DOSFALSE` → `Open`→0. Valider champs/bornes (cf. D1/D2). Le handler répond toujours
(un handler muet bloquerait `WaitPort` — toléré, comme le vrai dos qui bloque sur packets). Gardes anti-hang
héritées. Processes en user-mode sur SSP partagée (M7c) ; `WaitPort` = switch synchrone (M3d) — déjà prouvé.

## Hors périmètre (différé, assumé)
Bootstrap bootblock→dos réel (init manuel `rt_Flags=0`, montage DeviceNode depuis gabarits ROM, Initial CLI,
`CON:`, startup-sequence, disk-validator, requesters intuition) ; shell/prompt interactif ; lectures
incrémentales OFS ; `Write`/`Lock`/`Examine`/`Seek` au-delà du nécessaire ; `ACTION_STARTUP` fidèle (on démarre
notre handler à notre façon). → milestones CLI + intégration boot réel.

## Déviation de fidélité (notée)
`dos.library` reste un résident initialisé dans notre bringup (M6d, AUTOINIT) et non l'init-manuel-piloté-par-
bootblock du vrai V34 (`rt_Flags=0`). D3 prouve la MACHINERIE packet/handler/Open/Read/LoadSeg-run ; le bootstrap
fidèle + CLI viennent après.
