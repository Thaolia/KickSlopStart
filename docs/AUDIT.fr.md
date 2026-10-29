# Audit clean-room — 2026-10-29

*English version: [AUDIT.md](AUDIT.md).*

Cet audit répond à une issue GitHub. Elle demande des preuves de ce qu'affirme le README : le dépôt ne contiendrait
aucun code Commodore. La question est légitime. Le code de `src/` a été écrit avec un LLM, et un LLM a pu mémoriser
pendant son entraînement des sources de Kickstart qui ont fuité. Le mur clean-room (voir [CLEANROOM.md](CLEANROOM.md))
contrôle ce qui est lu *pendant* le projet, pas ce que le modèle a retenu avant. Une telle reprise ne peut donc être
que mesurée a posteriori : c'est l'objet de cet audit.

Trois contrôles indépendants ont été menés, chacun par un agent séparé dans un périmètre étanche. Les rapports
détaillés sont dans [`docs/audit/`](audit/). Les outils sont dans `tests/`, pour que chacun puisse refaire la mesure.

| Contrôle | Question | Outil | Rapport détaillé |
|---|---|---|---|
| 1. Similarité binaire | Notre ROM contient-elle des suites de code de la ROM Kickstart 1.3 d'origine ? | `tests/audit_rom_similarity.py` | [rom-similarity.md](audit/rom-similarity.md) |
| 2. Similarité des sources | `src/` contient-il du code copié d'AROS ? | `tests/audit_aros_similarity.py` | [aros-similarity.md](audit/aros-similarity.md) |
| 3. Relecture des specs | Les notes d'analyse (`docs/analysis/`) laissent-elles fuir du code de la ROM, et quelles *données* de la ROM se retrouvent dans `src/` ? | relecture | [specs-review.md](audit/specs-review.md) |

## 1. Comparaison binaire avec la ROM d'origine

**Méthode.**
- La comparaison porte sur trois flux : les mots de 16 bits, les instructions décodées, et une variante souple sans
  registres ni constantes.
- Les adresses absolues de la ROM et les déplacements de branchement ou relatifs au PC sont masqués : une copie
  relogée reste ainsi détectable.
- L'outil cherche les plus longues correspondances avec un automate des suffixes et compte les n-grammes communs
  (4, 8 et 16).
- La référence est du code 68000 sans rapport : exécutables de jeux et SysInfo, extraits des disquettes de test.
- Deux autres groupes sont mesurés à part : le code Commodore hors ROM (commandes du Workbench 1.3.3) et AROS.

**Contrôle positif.** Douze fragments relogés de la vraie ROM ont été insérés dans la nôtre, et l'outil les retrouve
tous. La méthode est donc capable de détecter une copie.

**Résultats** (ROM de production) :

| Comparaison | Plus longue correspondance de code | Couverture des correspondances ≥ 8 mots |
|---|---|---|
| **notre ROM / ROM d'origine** | **20 mots / 13 instructions** | 0,69 % (≥ 16 mots : 0,09 % ; ≥ 32 mots : 0) |
| jeux sans rapport / ROM d'origine (référence) | 39 mots / 18 instructions | — |
| code Commodore du Workbench / ROM d'origine (code apparenté) | 121 mots / 96 instructions | 3,8 % |
| notre ROM / ROM AROS | 12 mots / 8 instructions | — |

**Ce qui dépasse le seuil.**
- Les tables de vecteurs de fonctions, dont la longueur est fixée par les fichiers `.fd` publics.
- La table de positions des caractères d'une police à chasse fixe de 8 pixels. C'est une simple progression
  arithmétique, et la ROM AROS contient la même table.
- Les dessins des glyphes, eux, **ne** correspondent **pas**.

**Verdict :** aucune reprise de code du Kickstart 1.3 n'est mesurée. Notre plus longue correspondance de code est plus
courte que celle de jeux sans aucun rapport avec la ROM d'origine.

**Limites.**
- Une seule version de référence était disponible (1.3, 34.5). Les fuites connues portent surtout sur les sources 2.x
  et 3.x : il faudra refaire la mesure contre des ROM 2.04 et 3.1.
- La mesure est binaire, pas sémantique : elle ne voit ni une paraphrase ni une traduction du C vers l'assembleur.

## 2. Comparaison avec AROS

**Corpus.**
- La copie locale `third_party/aros` étant trop partielle, l'audit utilise un clone partiel du dépôt officiel d'AROS
  (commit `4dbf6509`) : `arch/m68k-*`, `rom/*`, `workbench/{libs,devs,c,fs,system}` et `compiler/include`.
- Notre côté, c'est `src/` : 75 fichiers, 221 721 tokens. AROS étant presque entièrement en C, l'assembleur 68000
  comparable n'y pèse que 22 757 tokens.

**Méthode.**
- **Assembleur contre assembleur** : empreintes de tokens avec winnowing (à la façon de MOSS), à trois niveaux de
  normalisation.
- **Assembleur contre C** : commentaires, identifiants hors ABI et constantes « magiques ».
- **Contrôle positif** : deux fichiers AROS translittérés en vasm, labels renommés et commentaires remplacés, sont
  retrouvés à 62–100 %.

**Résultats.**

| Taille des k-grammes | `src` → AROS comparable | `src` → code Amiga sans rapport, de taille égale |
|---|---|---|
| 20 tokens, exact | 0,06 % | 0,004 % |
| 30 tokens, exact | 0,031 % (2 passages) | 0 % |

Un seul passage est notable : `bcpl_call`/`bcpl_ret` dans `src/dos/bcpl.s` (8 instructions) est identique à
`BCPL_jsr`/`BCPL_rts` d'AROS.
- L'ABI BCPL fige cette entrée de 16 octets : la multiplication doit être à +$10, la division à +$12, et le frame suit
  la disposition -12/-8/-4. AROS le commente lui-même : « This MUST be at BCPL_jsr+0x10 ».
- Les routines de multiplication et de division, elles, diffèrent. Le source documente désormais cette identité.

Côté C, rien de distinctif n'est partagé. Une phrase anglaise citée comme « AutoDoc » dans `src/dos/dos_lib.s` figure
aussi dans l'autodoc d'AROS ; elle a été remplacée par un commentaire en français.

**Limite :** une transcription du C vers l'assembleur ne laisse aucune trace lexicale ; seule la discipline
clean-room y répond.

## 3. Relecture des notes d'analyse et données issues de la ROM

**Notes d'analyse (`docs/analysis/`, 50 fichiers).**
- 19 notes anciennes n'avaient pas de section de relecture. Elles ont été relues ligne par ligne et 9 ont été
  corrigées.
- Une seconde passe a retiré environ 194 adresses de routines et de données de la ROM restées dans 13 autres notes,
  surtout dans des blocs « Repères ».
- Il ne reste que des adresses génériques : base et plage de la ROM, offsets d'en-tête, et la base `$F80000` que
  testent les logiciels.
- Les 50 notes se terminent maintenant par une section de relecture datée.

**Données issues de la ROM présentes dans `src/`.**

| Élément | Statut |
|---|---|
| Palette et Preferences par défaut, ~50 chaînes affichées (Guru, CLI, requesters, Workbench) | Gardées volontairement : valeurs observables nécessaires à la compatibilité. |
| Keymap | **Pas une copie.** Seuls les caractères ASCII de la disposition US coïncident ; les colonnes Alt et Ctrl, les touches mortes et les octets Capsable/Repeatable sont absents. |
| Glyphes de la police | Dessinés à la main ; ils ne correspondent pas à la ROM (contrôle 1). |
| **Coche des menus** | **Corrigée.** Le premier dessin, fait juste après la lecture d'une note qui montrait l'image de la ROM, en partageait 4 lignes sur 8. Il est remplacé par un motif sans rapport : une empreinte de patte de chat. |
| **Pictogrammes des gadgets système** (fermeture, profondeur, taille) | **Ouvert.** Ils suivent la géométrie au pixel de `intuition-frame-v34.md` §5.3 et ressemblent donc à ceux de la 1.3. La compatibilité ne l'exige pas ; une refonte est proposée. |
| Messages d'avertissement « Discard » du Workbench | **Ouvert.** Aucune trace dans les notes : ils viennent très probablement de la mémoire du modèle. Ce sont des textes d'interface publics, mais leur provenance n'est pas documentée. |
| Points mineurs (liste copper réduite, gestionnaire d'exception compatible SetPatch, mot RESET) | Imposés par le matériel ou par des logiciels externes ; voir le §3 du rapport. |

Les notes contiennent encore quelques *données* de la ROM qu'il vaudrait mieux décrire que reproduire :
- les images de la coche et du symbole Amiga (`intuition-input-menus-v34.md`) ;
- la géométrie des pictogrammes (`intuition-frame-v34.md` §5.3) ;
- deux octets de code visibles à travers SetPatch (`setpatch-disk-resource.md`).

Elles sont listées au §2 du rapport.

## Conclusion

- Aucune reprise de code du Kickstart n'est mesurée dans le binaire.
- Aucune reprise de code d'AROS n'est mesurée, hormis une séquence de 8 instructions imposée par l'ABI.
- L'audit a en revanche trouvé des endroits où des **données** ou des images de la ROM sont passées dans
  l'implémentation, par les notes d'analyse ou par la mémoire du modèle :
  - la coche est corrigée ;
  - deux points restent ouverts : les pictogrammes et les chaînes « Discard ».
- L'affirmation « aucun code Commodore » du README tient pour le code. Les données gardées pour la compatibilité
  (valeurs par défaut, chaînes affichées) sont listées ci-dessus.

## Refaire la mesure

```sh
# 1. Similarité binaire (avec votre propre ROM Kickstart 1.3 ; capstone facultatif)
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom <kick13.rom> --selftest
# 2. Similarité avec AROS (clone partiel d'AROS : voir aros-similarity.md, « Commandes »)
python3 -I tests/audit_aros_similarity.py src <clone-aros>
```

Les deux outils n'affichent que des statistiques et des emplacements dans le premier argument (notre code), jamais le
contenu de la référence.

Mesures faites sur les builds du commit `ec9f9ab` (2026-10-29). Les corrections listées ci-dessus sont postérieures à
la mesure ; elles ne font qu'éloigner davantage nos données de l'original.
