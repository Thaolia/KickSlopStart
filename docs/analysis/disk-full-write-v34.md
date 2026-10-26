# Disque plein en écriture : Join, Write, handler OFS (V34) — spec comportementale

> Piste ANALYSE. Tout ce qui suit a été **observé** en faisant tourner la vraie ROM
> (`assets/kick34005.A500`, lecture seule) sous FS-UAE, ou lu dans la commande `C:Join` du disque
> Workbench 1.3.3 (programme BCPL, liste de ses appels de globales seulement). Aucune suite
> d'instructions transcrite, aucune adresse de routine ROM. Légende : **[O]** observé à l'écran ou sur
> l'image disque, **[J]** lu dans `C:Join` (liste des globales appelées), **[?]** non établi.

## 1. Montage

- ADF : copie du WB 1.3.3 + fichiers `a` (8772 o) et `b` (9972 o) à la racine, 287 blocs libres.
  startup-sequence : 5 × `join a b a as jN` + `echo "JN"`, puis `echo "FIN"`.
  Chaque `jN` fait 27516 o = 57 blocs de données OFS (488 o par bloc) + 1 en-tête = 58 blocs.
  Après 4 joins il reste 55 blocs → le 5e manque de 3 blocs.
- Sonde `tests/diskfull.s` (ASSET DE TEST) : Open/Write dos et packets `ACTION_WRITE` (87) bruts
  envoyés directement au port du handler (`fh_Type`, `dp_Arg1 = fh_Args`), avec affichage de
  dp_Res1/dp_Res2, Write()/IoErr(), `Seek(fh,0,OFFSET_CURRENT)` et `id_NumBlocksUsed`.
  Disque : WB 1.3.3 vierge (325 blocs libres), écriture d'une source de 200000 octets.
- Les requesters ont été fermés au clavier par **Amiga gauche + B** (= bouton de droite, « Cancel »).

## 2. Q1 — Ce qu'on voit pendant et après le join qui manque de place [O]

1. Les joins 1 à 4 se déroulent normalement (« J1 »… « J4 »).
2. Pendant le 5e join apparaît un **requester système** : fenêtre titrée « System Request »,
   placée en haut à gauche **sur l'écran de la fenêtre CLI** (fenêtre du process demandeur),
   texte sur trois lignes :
   ```
   Volume
   Workbench1.3
   is full
   ```
   boutons **Retry** (gauche) et **Cancel** (droite). Le process Join est bloqué tant que le requester
   est ouvert (vérifié : il reste affiché au moins 5 min sans réponse).
3. Chaque **Cancel** fait disparaître le requester ; il **réapparaît pour chaque Write suivant** qui
   échoue. Dans ce scénario : **3 requesters** (voir le décompte au §4).
4. Après le dernier Cancel, Join **n'affiche rien** (aucun message d'erreur), se termine **sans code
   d'erreur visible** : la startup-sequence **continue** (« J5 » puis « FIN » s'affichent, puis le
   prompt `1>` ; FailAt 10 n'est pas déclenché). Join rend donc 0 (cf. §5 : il n'examine pas le
   résultat de ses écritures).
5. Image disque après le run :
   - `j1`…`j4` = 27516 o chacun ; **`j5` = 26344 o** dans l'en-tête de fichier.
   - Contenu de `j5` : les 26344 premiers octets = exactement le début de `a+b+a`.
   - L'en-tête a **54 blocs de données**, le dernier bloc porte une taille de données de **488**
     (plein) alors que la taille du fichier (26344) n'en compte que 480. Les 8 octets restants du
     dernier bloc contiennent **les 8 premiers octets de la dernière écriture refusée** (début du
     dernier morceau de 372 o de `a`), pas la suite logique du fichier. → incohérence en-tête/bloc
     produite par la vraie 1.3 (xdftool la signale : « file size mismatch got=26352 want=26344 »).
   - Bloc racine : **drapeau bitmap valide = 0** (bitmap marquée invalide sur le disque), la bitmap
     sur disque est restée à l'état d'avant les joins (xdftool `info` lit 287 libres alors que le
     disque est plein). Run tué ~60 s après « FIN » : on ne sait pas si la 1.3 l'aurait réécrite
     plus tard **[?]**.

## 3. Q2 — Résultats du handler et de Write() quand la place manque

### 3.1 Vecteurs de la sonde (vraie ROM) [O]

Disque WB vierge, `df0:big` en MODE_NEWFILE, source 200000 o (plus que la place libre).
`used` = id_NumBlocksUsed (le disque compte **1758** blocs utilisables, valeur à saturation).

| Étape | Appel | Res1 / valeur rendue | Res2 / IoErr | pos après | used après | Requester |
|---|---|---|---|---|---|---|
| A | Open NEWFILE | fh (≠ 0) | $1574 (résidu, non significatif) | 0 | 1434 | non |
| B | packet ACTION_WRITE brut, 200000 o, pos 0 | **−1** | **221** (ERROR_DISK_FULL) | **0** | **1758** (disque plein) | **non** |
| C | packet ACTION_WRITE brut, 1000 o | **1000** | $FFFF (non significatif) | 1000 | 1758 | non |
| D | dos `Write(fh, 1000)` | **1000** | $FFFF | 2000 | 1758 | non |
| E (run v3) | dos `Write(fh, 200000)` depuis pos 2000 | **ne revient pas** | — | — | — | **oui, un** (« Volume Workbench1.3 is full ») ; après Cancel plus aucun requester, Write toujours bloqué > 4 min |

Lecture de ces vecteurs :

- **Échec = tout ou rien côté résultat** : une écriture qui ne tient pas rend **Res1 = −1** et
  **Res2 = 221**, et la **position du fichier n'avance pas** (pos reste 0 après B) — jamais un
  nombre partiel d'octets.
- Mais les **blocs alloués pendant l'écriture ratée restent attachés au fichier** (used passe à
  1758 ; l'image montre 320 blocs de données chaînés dans l'en-tête de `big`, taille 0 tant que le
  fichier n'est pas fermé). Les écritures suivantes **réutilisent** ces blocs : C et D réussissent
  (1000 o chacune) alors que le disque est plein.
- Le contenu des blocs a bien été recopié jusqu'à épuisement de la place (cf. les 8 octets de `j5`) :
  la copie n'est pas annulée, seuls la position et la taille ne sont pas avancées.
- `Write()` de dos rend le **Res1** du handler (1000 ici) ; `IoErr()` rend le Res2. Les Res2 des
  écritures **réussies** ne sont pas significatifs ($FFFF observé) : ne pas s'y fier.
- Sur Join (écritures de ≤ 400 o via Write), chaque morceau qui ne tient plus est refusé en entier :
  20e morceau de la 3e copie de `a` (400 o) alors qu'il restait 8 octets → refusé, puis les 2
  morceaux suivants (400 o, 372 o) → refusés, d'où 3 requesters et la taille 26344 = 18744 + 19×400.

### 3.2 Non établi [?]

- **E bloqué** : une **grosse** `Write()` dos qui déborde après réutilisation des blocs déjà alloués
  ne revient pas après Cancel (observé une fois, run v3 ; run v2 identique avec Seek/Info en plus).
  Les Writes de Join (≤ 400 o, un bloc à allouer) reviennent, eux. Cause non élucidée : la sonde v4
  (même débordement par packet **brut**, pour savoir si le blocage et le requester viennent du handler
  ou de dos) a été interrompue avant résultat.
- Res1/Res2 rendus par `Write()` **après Cancel** : non mesurés directement (Join ne les teste pas,
  et l'étape E de la sonde ne revient pas). Hypothèse cohérente avec B : −1 / 221.
- Effet de **Retry** : non testé.
- Close d'un fichier dont la dernière écriture a échoué : la taille enregistrée = position atteinte
  par les écritures réussies (j5 = 26344) **[O]** ; le reste (bitmap revalidée ou non) **[?]**.

## 4. Q4 — Le requester « Volume … is full » existe-t-il en 1.3, et qui l'affiche ? [O] / [?]

- **Oui**, il existe et apparaît sur un disque plein en écriture (§2). Texte : `Volume` / nom du
  volume / `is full`, boutons `Retry` / `Cancel`, sur l'écran de la fenêtre du process qui écrit.
- **Un packet ACTION_WRITE brut qui échoue (B) ne provoque AUCUN requester** : il rend −1/221 tout
  de suite. Les `Write()` dos qui échouent (Join, E) en provoquent un.
  → Indice fort que le requester est posé **côté dos (fonction Write / sa boucle de retry)** et non
  par le handler, sur le modèle des autres requesters disque de dos (globale 114, « errorreq »,
  cf. `bcpl-runtime-v34.md` §8.2). **Réserve** : B est la première écriture d'un fichier vide et E
  une écriture au-delà de blocs déjà alloués ; la sonde v4 qui devait lever cette ambiguïté (packet
  brut dans la situation de E) n'a pas abouti → attribution **[?]**, à confirmer.
- Un requester par Write qui échoue ; Cancel → la Write rend l'échec à l'appelant (cas Join : le
  programme continue) ; pas de requester supplémentaire à la fermeture.

## 5. Q3 — Comment Join écrit et détecte l'échec [J]

`C:Join` (1056 o, BCPL, données en globales du runtime ROM) :

1. Mémorise `output()` (globale 66), lit les arguments avec `rdargs` (78) sur le gabarit
   `,,,,,,,,,,,,,,,AS=TO/K` (15 sources + destination). Échec ou pas de 1re source ou pas de AS :
   `writef` (74) « Bad args » puis `stop(20)`.
2. Ouvre la destination par `findoutput` (60) ; échec : « Can't open %S » puis `stop(20)`.
   Sinon `selectoutput` (62).
3. Pour chaque source non vide (au plus 15) : `findinput` (59) ; échec : `endwrite` (64, ferme la
   destination partielle — **elle n'est pas supprimée**), resélectionne l'ancienne sortie,
   « Can't open %S », `stop(20)`. Sinon `selectinput` (61), puis boucle :
   - `readbytes` (40) dans un tampon local de **400 octets** (lecture d'abord),
   - puis `testflags(1)` (37, Ctrl-C) : si posé → ferme la source (`endstream`, 93), `endwrite`,
     resélectionne l'ancienne sortie, `writes` (73) « **BREAK », `stop(10)` ;
   - si le nombre lu est ≤ 0 → fin de cette source (`endstream`) ;
   - sinon **`writebytes(tampon, n)`** (43 = `Write(output(), …)` direct, sans le tampon de 200 o
     de `wrch`), **dont la valeur de retour est ignorée** ; on reboucle.
4. Fin : `endwrite` puis `stop(0)`.

Conséquences :
- Join **ne détecte pas** l'échec d'écriture : ni la valeur rendue par Write ni Result2 ne sont
  testées ; pas de message, code retour **0** ; la startup-sequence continue.
- Le seul retour visible à l'utilisateur est le requester posé pendant chaque Write ratée.
- Le fichier destination est fermé normalement et garde ce qui a été écrit avec succès.

## 6. Ce que notre ROM doit reproduire

1. Handler OFS, `ACTION_WRITE` sans place suffisante : **Res1 = −1, Res2 = 221**, position et
   taille du fichier **inchangées** (pas de résultat partiel).
2. Les blocs alloués pendant l'écriture ratée restent au fichier et resservent aux écritures
   suivantes (C/D réussissent sur disque plein). (Reproduire la copie partielle dans le dernier bloc
   et l'incohérence taille-bloc n'est pas nécessaire : artefact, pas un contrat.)
3. `Write()` dos rend le Res1 du handler et IoErr = Res2.
4. Requester « Volume / <nom du volume> / is full », Retry / Cancel, sur l'écran du process, **une
   fois par Write qui échoue** ; Cancel → la Write rend l'échec (−1, IoErr 221 supposé) ; Retry →
   nouvel essai **[?]**. Un packet brut n'en produit pas (au moins dans le cas B).
5. Join : écritures de 400 o via Write, résultat ignoré, sortie 0, startup-sequence continue,
   aucun texte d'erreur. Vecteur de bout en bout : sur l'ADF jw, `j5` = **26344 o**, écran
   « J1…J5 », « FIN », 3 requesters à annuler.

## 7. Vecteurs de test

| Vecteur | Entrée | Attendu (vraie 1.3) |
|---|---|---|
| V1 | ADF jw (startup 5 × join), Cancel à chaque requester | 3 requesters « Volume Workbench1.3 is full » ; écran J1…J5, FIN ; `j5` = 26344 o = préfixe de a+b+a |
| V2 | sonde, étape B | `B FFFFFFFF 000000DD` ; pos 0 ; used 1758 ; pas de requester |
| V3 | sonde, étapes C, D | `000003E8` chacune ; pos 1000 puis 2000 |
| V4 | sonde, `Write` 200000 depuis pos 2000 | 1 requester ; **ne revient pas** après Cancel (comportement 1.3 observé, à ne pas forcément reproduire) **[?]** |

## Relecture clean-room

- [x] Aucune suite d'instructions de la ROM ni de `C:Join` transcrite : seuls des numéros de
      globales BCPL (ABI déjà documentée), des constantes d'ABI (87, 221, 1006) et des
      comportements observés.
- [x] Aucune adresse de routine ROM.
- [x] Les éléments non établis sont marqués **[?]**.
- [x] Sonde `tests/diskfull.s` : code auteur, en-tête « ASSET DE TEST, PAS du code ROM ».
