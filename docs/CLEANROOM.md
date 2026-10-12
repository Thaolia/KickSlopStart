# Discipline salle blanche (clean-room)

## Le principe

« Salle blanche » a un sens juridique précis : un **mur** sépare qui lit l'original copyrighté de qui
écrit le remplacement. L'implémenteur ne doit jamais avoir vu l'expression originale, pour que le
résultat ne soit pas une œuvre dérivée. Désassembler la ROM *et* en écrire le code dans le même flux
est l'exact opposé : c'est ce qu'on s'interdit ici.

## Les deux pistes

### Piste ANALYSE (« dirty »)
- **Entrées** : la ROM `assets/kick34005.A500` (lecture seule), radare2 / Ghidra headless.
- **Sorties** : exclusivement `docs/analysis/*.md`.
- **Autorisé** : adresses, offsets, tailles et layout de structures (= ABI, interopérabilité),
  ordres d'opérations, valeurs de constantes d'ABI, comportements observables, vecteurs de test.
- **Interdit** : écrire dans `src/` ; recopier des suites d'instructions désassemblées ; produire du
  code d'implémentation.

### Piste IMPLÉMENTATION (« clean »)
- **Entrées** : docs publiques (RKRM, AutoDocs, NDK, fichiers `.fd`/SFD = contrat d'ABI), source AROS
  (`third_party/`, **lecture seule**), et les specs **comportementales** de `docs/analysis/`.
- **Sorties** : `src/`.
- **Interdit** : lire la ROM d'origine ou son désassemblage.

## Porte de revue de spec

Avant qu'une spec de `docs/analysis/` ne soit consommée par la piste implémentation, elle est relue
pour confirmer qu'elle **ne contient aucune suite d'instructions transcrite** depuis la ROM. C'est ce
contrôle qui donne au mur sa valeur réelle.

## Pourquoi les docs publiques d'abord

Les fichiers `.fd` et les AutoDocs/RKRM **définissent déjà** l'API (noms, LVO, signatures) de façon
légale : c'est la base de l'implémentation. La ROM ne sert qu'à **lever des ambiguïtés
comportementales** que les docs publiques — qui décrivent surtout la 2.0/3.x — ne couvrent pas pour la
1.3. Ce delta (ce que fait réellement la V34 vs ce que disent les docs 2.0) est capturé *par la piste
analyse dans les specs*, puisque la piste implémentation ne peut pas aller le chercher dans la ROM.

## Licences

- **AROS** est sous **APL v1.1** (copyleft par fichier, non-OSI, incompatible GPL) : on la **lit**, on
  ne **copie pas** ses sources dans `src/` → notre licence reste libre.
- **NDK / RKRM** : licences propriétaires, **consultées**, **jamais redistribuées** dans le dépôt.
- La **ROM Kickstart** est propriétaire : jamais committée, jamais modifiée.

## Honnêteté sur la portée

Deux rôles d'agents dans une même session *approchent* le mur (l'implémenteur ne voit pas l'expression
originale) sans équivaloir à une séparation de personnes « niveau tribunal ». Pour une posture
juridique maximale, l'analyse et l'implémentation devraient être confiées à des personnes différentes.
