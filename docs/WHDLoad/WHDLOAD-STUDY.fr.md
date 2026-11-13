# WHDLoad sur KSS — étude de faisabilité (2026-11-13)

Version anglaise de référence : `WHDLOAD-STUDY.md`.

Question de l'utilisateur : peut-on utiliser WHDLoad avec notre ROM ? C'est une étude seulement, sans changement
dans `src/`.

## Méthode

- WHDLoad, JST (JOTD Startup, son prédécesseur) et leurs slaves ont été traités comme la ROM Commodore : un agent
  d'analyse séparé les a téléchargés, lancés et désassemblés. Il a écrit deux pages de comportement seul :
  `docs/WHDLoad/whdload-host-requirements.md` et `docs/WHDLoad/jst-host-requirements.md`.
- Côté implémentation, on n'a lu que ces deux pages et la documentation officielle de whdload.de. Les pages ont été
  vérifiées : aucun listing d'instructions, aucune adresse dans les binaires ni dans la ROM. `$3F5` et `$3F7` sont
  des constantes publiques du format hunk.
- Les essais ont tourné sous Amiberry : A500, 68000 cycle-exact, 512 Ko chip + 512 Ko slow (une série avec 2 Mo de
  fast). DH0: est un répertoire hôte monté par le système de fichiers UAE. Chaque essai a été fait sur la vraie
  Kickstart 1.3 et sur nos ROM dev et prod.

## Résultats

| Programme | Vraie 1.3 | KSS (prod) |
|---|---|---|
| WHDLoad 20.1 | « file is not an object module » (hunk V37 `$3F7`) | identique |
| WHDLoad 0.41 / 0.88 | sortie muette (OpenLibrary dos 37 échoue) | identique |
| JST 4.7 | « file is not an object module » | identique |
| JST 3.1 | plantage sur un appel dos V36 non protégé (AllocDosObject) | même plantage, Guru sans le requester « task held » |
| JST 0.8c + loader JST (démo Cadaver) | le jeu tourne | le jeu tourne (25 s contre 20 s) |
| JST 0.8c + slave WHDLoad | « not a JOTD loader » (version antérieure au support des slaves) | identique |
| Gamebench 2.00 (lanceur WB 1.3) | la fenêtre s'ouvre | identique |

## Conclusions

1. **WHDLoad ne peut tourner sur aucune Kickstart 1.3, la nôtre comprise. Ce n'est pas un bug de KSS.** Toutes les
   versions depuis la première publique (0.41, 1996) exigent Kickstart 2.0 (V37). Notre ROM le refuse aux deux mêmes
   barrières que la vraie 1.3 : d'abord le type de hunk V37 dans `LoadSeg`, ensuite le test de version.
2. **On ne peut pas utiliser KSS comme image Kickstart du kickemu de WHDLoad.** Le kickemu n'accepte qu'une image
   Commodore intacte avec son fichier de relocation `.RTB`, et il patche l'intérieur de cette image, ce qui sort du
   cadre clean-room.
3. **Ce que KSS fait tourner aujourd'hui, ce sont les anciens loaders JST.** JST 0.8c mène un loader JST jusqu'au
   jeu jouable sur la ROM prod, comme sur la vraie 1.3. La touche de sortie et le retour à l'OS pendant le jeu n'ont
   été observés sur aucune des deux ROM.
4. **Les versions de JST qui lancent des slaves WHDLoad (1.3 à 4.4) ne sont pas sûres sur 1.3.** C'est le cas de la
   seule disponible, la 3.1. À partir de la 4.5, JST exige V37 par conception.

## Options

| Option | Ce qu'il faut | Taille | Verdict |
|---|---|---|---|
| A. Rien (1.3 stricte) | KSS se comporte déjà comme la 1.3 sur tous ces programmes | — | **recommandé** |
| B. Un build `-DV37` à part, avec une API de niveau 2.04 | exec V36/37 (CreateMsgPort, CreateIORequest, AllocVec, pools, CacheClearE, StackSwap), 26 fonctions dos V36/37 (ReadArgs, AllocDosObject, verrous de la DOS list, motifs, CreateNewProc, SystemTagList, GetVar...), intuition V36 (écrans publics, Open* à tags, EasyRequestArgs), graphics GetVPModeID, trois nouvelles bibliothèques (gadtools, keymap, utility), hunks V37 dans LoadSeg, `lib_Version` >= 37 partout | L+ (en pratique une ROM 2.0) | hors de la mission 1.3 ; les programmes 1.3 qui testent la version prendraient leur chemin 2.0 |
| C. Seulement les neuf fonctions dos V36 de JST 3.1/4.7 (AllocDosObject, FreeDosObject, Flush, LockDosList, UnLockDosList, FindDosEntry, ReadArgs, FreeArgs, GetVar) | une table de sauts dos plus longue, donc une ROM 1.3 qui n'en est plus une | M | n'en vaut pas la peine : JST 4.7 exige encore les hunks V37 et la version 37, et le support des slaves de la 3.1 date de l'ère shareware, en bêta |
| D. Le kickemu avec KSS comme image | — | — | impossible (voir conclusion 2) |

## Trouvailles annexes sur KSS (côté implémentation, hors WHDLoad)

- **Il manque le requester « Software error - task held ».** Sur une exception d'une tâche utilisateur, la 1.3
  l'affiche avant le Guru, alors que KSS passe directement au Guru. Ce requester est décrit dans
  `docs/analysis/alert-v34.md`. Repris dans `docs/REMAINING-WORK.md` A12.
- **La ROM dev cale sous JST 0.8c et Gamebench** : des minutes au lieu de secondes, alors que la ROM prod se
  comporte comme la 1.3. Tous les échantillons de PC tombaient dans du code d'interruption : dispatch niveau 6,
  handler de preuve niveau 6 propre au dev, serveur VBlank du gameport, avec EXTER et PORTS en attente. Ça désigne le
  harnais de test dev. Pas encore étudié. Repris dans A13.
- Le CLI de boot affiche le prompt `> ` là où la 1.3 affiche `1> `, avec la même startup-sequence réduite. C'est
  cosmétique et pas encore confirmé de notre côté. Repris dans A14.

## Sources

- whdload.de : `docs/en/need.html` (Kickstart 2.0 V37, 68000, 1 Mio), `docs/en/opt.html`, `docs/en/howto.html`,
  `docs/History.html`.
- Aminet : `game/patch/jst.lha`, `game/patch/jst32b_dev.lha`, `game/patch/jst_hdinstalls.lha`,
  `util/misc/Gamebench.lha`.
- Les pages d'analyse ci-dessus (essais boîte noire sur les deux ROM et lecture statique, comportement seul).
