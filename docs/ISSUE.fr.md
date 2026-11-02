# Signaler un problème

*[English version](ISSUE.md)*

Merci de tester KickSlopStart. Un signalement qu'on peut reproduire est le chemin le plus court vers une
correction. Ouvrez une issue depuis le [sélecteur d'issues](https://github.com/Thaolia/KickSlopStart/issues/new/choose) :
les formulaires demandent tout ce qui suit.

## Avant de signaler

- Essayez la dernière version de la page [Releases](https://github.com/Thaolia/KickSlopStart/releases) (ou le
  lien vAmigaWeb du README, qui lance toujours la dernière).
- Vérifiez les [différences voulues](../README.fr.md#différences-voulues-pas-des-bugs) : le Workbench vert,
  l'écran de boot au chaton, les symboles de chat dans les menus, la fenêtre « AmigaSlopDOS » et le pointeur
  violet sont volontaires.
- Consultez les manques connus dans [`docs/PLAN.md`](PLAN.md), et cherchez dans les issues existantes.

## Ce qu'il faut indiquer

- **La ROM** : le tag de la version (par ex. `v0.2.6`), ou le nom du fichier et son SHA-256.
- **Comment elle est chargée** : émulateur, disquette de soft-kick, ou EPROM sur une vraie machine.
- **L'émulateur** et sa version (FS-UAE, WinUAE, Amiberry, vAmiga/vAmigaWeb...).
- **La configuration de la machine** : processeur, chipset et révision d'Agnus, tailles de RAM chip / slow /
  fast. Un Agnus OCS (A500) n'adresse que 512 Ko de RAM chip au maximum, quelle que soit la taille donnée à
  l'émulateur.
- **Le programme** : son nom, le nom exact de l'image disque, et sa provenance.
- **Les étapes pour reproduire**, depuis la mise sous tension.
- **Attendu et observé** : ce que fait le même programme sur un vrai Kickstart 1.3 avec la même configuration,
  et ce qu'il fait sur KickSlopStart.
- **Une capture d'écran** du problème.
- **La sortie série** si vous pouvez la capturer (KickSlopStart écrit ses messages de boot sur le port série ;
  FS-UAE et WinUAE savent l'enregistrer dans un fichier).

## Valeurs et messages

Citez la valeur ou le message exact, et l'endroit où il s'affiche, par exemple « la barre de titre du Workbench
indique 4009448 free memory » ou « la démo dit : not enough chip memory ». Un nombre sans sa provenance ne peut pas
être vérifié.

## Règles clean-room

KickSlopStart est écrit sans code Commodore (voir [`docs/CLEANROOM.md`](CLEANROOM.md) et
l'[audit clean-room](AUDIT.fr.md)). Pour que cela reste vrai, merci de **ne jamais joindre ni coller** :

- la ROM Kickstart d'origine, ou une partie ;
- un désassemblage ou une décompilation de cette ROM ;
- du code source Commodore, fuité ou non.

Décrire ce que **fait** la ROM d'origine est bienvenu : une capture, un message, une valeur, l'ordre des
événements.

## Demandes de fonctionnalité

Nommez le programme qui a besoin de la fonctionnalité et, si vous la connaissez, la bibliothèque ou le device et
la fonction appelée (par ex. `graphics.library ScrollVPort`). Dites ce qui se passe aujourd'hui sur KickSlopStart.

## Langue

L'anglais est préféré ; le français est bienvenu aussi.
