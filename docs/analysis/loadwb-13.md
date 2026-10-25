# loadwb-13.md — `c/loadwb` (Monkey Island, 2 784 o) vs `C:LoadWB` 1.3.3 (2 780 o), et `EndCLI`

> Piste ANALYSE (« dirty »). Sources :
> - disque Monkey Island, disque 1/4 [cr Defjam] : `c/loadwb` (en-tête bloc 891), `c/endcli` (bloc
>   903), `s/startup-sequence` (bloc 997) ;
> - `assets/wb133.adf` : `C:LoadWB` (bloc 1039), `C:EndCLI` (bloc 979) ;
> - ROM `kick34005.A500` : boucle du CLI dans la section BCPL de dos, workbench.task.
>
> Fichiers extraits par le lecteur OFS tolérant, relogés à plat à $100000 et comparés octet par
> octet. **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Appels publics et
> comportement ; aucune suite d'instructions recopiée.

---

## 1. `c/loadwb` de Monkey Island : séquence complète [O]

Exécutable C de **12 hunks**, d'une structure identique à celle du 1.3.3 (§2). Les globales sont
SysBase (exec) et DOSBase. La séquence de `main(argc, argv)` :

1. exec **OpenLibrary("icon.library", 0)** (−552). Échec ⇒ **exit(20)** silencieux, sans
   message.
2. exec **OpenLibrary("intuition.library", 0)**. En cas de succès :
   - **AllocMem(160, MEMF_PUBLIC|MEMF_CLEAR)** (−198), qui recevra le code de remplacement ;
   - décodage en place de deux chaînes obfusquées (XOR $9E) : un texte d'« œuf de Pâques »
     d'écran et son remplaçant ;
   - **CopyMem(code, bloc, 160)** (−624) ;
   - **Forbid** (−132), **SetFunction(IntuitionBase, −276 = SetWindowTitles, bloc+4)** (−420),
     l'ancien vecteur étant rangé en tête du bloc, **Permit** (−138) ;
   - **CloseLibrary(intuition)** (−414).

   Le remplaçant est examiné en §2. Échec d'OpenLibrary ou d'AllocMem ⇒ le patch n'est pas
   posé, et le programme continue.
3. exec **FindTask(NULL)** (−294) : son Process, dont on garde `&pr_MsgPort` (+$5C) et
   `BADDR(pr_CLI)` (+$AC).
4. Si **argc = 2 et argv[1] = "-debug"** (comparaison exacte, sensible à la casse) ⇒ drapeau
   debug := 1.
5. exec **FindResident("workbench.task")** (−96). Échec ⇒ écrit **« Cannot find resident tag for
   workbench.task »** sur **Output()** (dos −60, Write −48, via RawDoFmt −522), puis exit(20).
6. Copie du chemin de commandes : pour chaque nœud de `cli_CommandDir` (CLI +$08),
   AllocMem(8, MEMF_CLEAR), puis **DupLock** (dos −96) du lock. Le tout forme une liste BPTR.
7. dos **CreateProc("workbench.task", pri 1, seglist = (RomTag + $2A) >> 2, pile 5000)** (−138).
   Le décalage est arithmétique et l'adresse n'est pas alignée : c'est le « sélecteur 2 » de la
   ROM, cf. `workbench-task-v34.md` §1.3. Échec ⇒ **« Cannot start tool (error %ld) »** avec
   **IoErr()** (−132) sur Output(), puis exit(20).
8. Message de démarrage de 28 octets **sur sa pile** :
   - `mn_ReplyPort` = son `pr_MsgPort` ;
   - +$14 = la liste de chemins ;
   - +$18 = le drapeau debug ;
   - `mn_Length` n'est pas initialisé.

   Il est envoyé par **PutMsg(port renvoyé par CreateProc, msg)** (−366).
9. **WaitPort(&pr_MsgPort)** (−384) puis **GetMsg** (−372) : attente **bloquante** de la
   réponse. Il n'y a pas de délai d'expiration.
10. **FindTask("Workbench")**. Si la tâche est trouvée : **`pr_ConsoleTask` (+$A4) := 0** dans
    ce process. Sinon, rien.
11. Si **argc = 2 et argv[1] = "delay"** ⇒ dos **Delay(150)** (−198), soit 3 s.
12. Retour, code 0.

**Ce qu'il ne fait pas** :
- il n'ouvre pas de workbench.library ;
- il ne cherche pas de port « Workbench » ;
- il ne fait ni Execute, ni LoadSeg, ni OpenWorkBench ;
- il ne teste pas un Workbench déjà lancé : un deuxième `loadwb` relance un second process.

**Sorties silencieuses** : seulement l'échec d'OpenLibrary(icon), avec le code 20. Les deux
autres échecs écrivent un message.

## 2. Différences avec `C:LoadWB` 1.3.3 (2 780 o, md5 f10020d8…) [O]

- **Le même programme** : mêmes 12 hunks, même `main` octet pour octet. Les seuls octets qui
  diffèrent dans `main` sont des adresses relogées, décalées par les tailles des hunks 4 et 6.
- **Aucune différence pour `delay`, `-debug`, FindResident, CreateProc, le message, WaitPort,
  FindTask("Workbench") et pr_ConsoleTask.**
- **Hunk 4, le remplaçant de SetWindowTitles(win A0, titre A1, titre d'écran A2)** :
  - **dans les deux versions** : si le titre d'écran vaut $FFFFFFFF, appel direct de
    l'original. Sinon :
    - si c'est le texte de version en 1.2, quelques caractères sont réécrits dans la chaîne de
      l'appelant (+$11…+$15) ;
    - si c'est le texte d'œuf de Pâques, le titre est remplacé par l'autre chaîne ;
    - puis appel de l'original avec les mêmes registres ;
  - **seule différence** : la version 1.3.3 sort aussi si **A2 = NULL**. La version Monkey ne
    teste pas NULL : avec A2 = NULL, elle **lit** l'octet $14 et compare la chaîne à l'adresse 0.
    Ce sont des lectures en mémoire basse, sans écriture, puisqu'aucune comparaison ne réussit [D].
    Les deux versions affichent un texte « Workbench release 1.2. ».
- **Hunk 6** (helper d'écriture formatée) : 36 octets au lieu de 28, même fonction.
- **Conclusion** : avec ce loadwb, le Workbench doit démarrer comme avec celui du 1.3.3. Ce qui
  change dans la startup-sequence Monkey, c'est **l'absence de `delay`** et **`endcli` sans
  `>NIL:`**.

## 3. `EndCLI` (696 o) : **identique** au C:EndCLI du WB 1.3.3 (même md5 34adda82…) [O]

### 3.1 Ce que fait la commande

Commande BCPL : un hunk stub, plus un module de 82 longs, globale max 145. Avec les numéros de
globales de `bcpl-runtime-v34.md` :

1. rdargs avec un gabarit vide ; numéro de process lu pour le message.
2. **`cli_StandardInput`→fh_End (FileHandle +$14) := 0** : vide le tampon de l'entrée console.
3. Si **cli_CurrentInput ≠ cli_StandardInput** (on est dans un script) : **endstream(CurrentInput)**
   (Close), puis CurrentInput := StandardInput.
4. **`cli_Background` := −1 (TRUE)** (globale 145 = champ CLI +$2C).
5. Si **cli_Interactive ≠ 0** : **writef("CLI process %N ending")** sur la sortie courante.
6. Forbid (−132) ; dans la liste des segments résidents de DosInfo (via rootstruct), recherche du
   nœud nommé **"CLI"** et **décrément de son compteur d'utilisation** s'il est > 0 ; Permit
   (−138).
7. Retour.

**EndCLI ne ferme pas la console**, n'envoie aucun ACTION_END et ne touche ni Output() ni Input().
Le message « CLI process 1 ending » est **normal** : il s'affiche aussi sur la vraie 1.3, juste
avant la fermeture de la fenêtre. Avec `>NIL:`, la sortie courante de la commande est NIL: et le
message n'apparaît pas.

### 3.2 Qui ferme réellement la fenêtre : la boucle du CLI en ROM [O]

Dans la boucle BCPL du CLI (dos, autour de $FF953C), lorsque la lecture d'une ligne de commande
rend **fin de flux** :
- **CurrentInput ≠ StandardInput** : fin d'un script ⇒ endread, puis retour sur StandardInput.
- **CurrentInput = StandardInput et Background = 0** : CLI interactif normal ⇒ fh_End := −1,
  c'est-à-dire « tampon à recharger », et lecture suivante ; on continue.
- **CurrentInput = StandardInput et Background ≠ 0** : **fin du CLI** :
  1. **endread()** (globale 63) : Close du flux d'entrée courant, la console ;
  2. **endwrite()** (globale 64) : Close du flux de sortie courant, la console ;
  3. **currentdir(0, …)** puis **freeobj(lock)** (globales 51 et 109) : **UnLock du répertoire
     courant du CLI** ;
  4. libérations, puis fin du process. Un autre chemin traite un CLI lancé par paquet
     (NewCLI/Run) avec returnpkt.
- **La fenêtre CON: se ferme** quand le handler console reçoit le **dernier ACTION_END**, ses
  deux FileHandles (entrée et sortie) étant fermés [D, comportement du handler].

**Point clé (convention FileHandle BCPL)** :
- `fh_End = 0` veut dire « **flux épuisé** » : le prochain `rdch` rend fin de flux
  **immédiatement, sans lire la console** ;
- `fh_End = −1` veut dire « **tampon vide, à recharger** par ACTION_READ ».

EndCLI met 0. C'est ce qui fait sortir le CLI **sans attendre de frappe**, aussitôt la commande
terminée.

## 4. Pistes pour notre écart [D]

L'enchaînement réel est le suivant :
1. `loadwb` rend la main dès la **réponse immédiate** de workbench.task. Cette réponse arrive
   avant toute ouverture d'écran (`workbench-task-v34.md` §2.4).
2. `endcli` s'exécute **pendant** l'init du Workbench.
3. Le CLI lit la fin de flux, ferme ses deux handles console, fait UnLock de son répertoire
   courant et se termine.
4. La fenêtre se ferme et le Workbench finit de s'ouvrir.

Chez nous (« CLI process 1 ending », fenêtre ouverte, pas de Workbench) :
1. **`fh_End = 0` doit signifier EOF sans lecture.** Si notre rdch ou notre recharge traite
   fh_End = 0 comme « tampon vide », le CLI repart en ACTION_READ sur la console et **attend une
   frappe**. La fenêtre reste alors ouverte, avec le message affiché : c'est exactement ce qu'on
   observe.
   - Avec `endcli >NIL:`, on passe par le chemin de redirection, puis la fermeture des flux
     redirigés (endstream, `$FF9AD0`/`$FF9AE8`). Cette séquence pourrait cacher l'écart.
   - **À tester : `endcli` sans `>NIL:` derrière `LoadWB delay` sur le disque WB 1.3.3.**
2. **Fin du CLI ⇒ endread + endwrite, puis le handler console ferme la fenêtre au dernier
   ACTION_END.** Il faut vérifier que notre fin de CLI fait ces deux Close et que notre handler
   compte bien ses ouvertures.
3. **Répertoire courant partagé.** La fin du CLI fait **UnLock de son répertoire courant**. Si
   notre CreateProc donne au process Workbench le **même lock** que le CLI (au lieu de 0 ou d'un
   DupLock), l'UnLock fait sortir le Workbench de son répertoire en pleine init. Le Workbench
   resterait alors invisible ou bloqué. Avec `delay`, le Workbench a fini son init avant l'UnLock,
   ce qui expliquerait que notre cas de référence marche.
   - **À tester : `loadwb` puis `endcli >NIL:` sans `delay`.**
4. **`FindTask("Workbench")`.** Sur la vraie ROM, le process s'appelle déjà « Workbench » quand
   LoadWB reçoit la réponse. Sinon, `pr_ConsoleTask` n'est pas remis à 0. C'est sans gravité tant
   que notre Workbench n'utilise pas `pr_ConsoleTask` ; la ROM ne le lit jamais.
5. Le process est créé avec **pile 5000 et priorité 1** : vérifier que notre CreateProc respecte
   la priorité, puisque le Workbench doit passer devant le CLI (pri 0) qui se termine.

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : appels publics avec LVO et arguments, champs de
  structures publiques (Process, CommandLineInterface, FileHandle, Message), conditions.
- [x] Aucune donnée du programme reproduite, hormis de courtes chaînes. Les textes obfusqués sont
  décrits par leur rôle seulement.
