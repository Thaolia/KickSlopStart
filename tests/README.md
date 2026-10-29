# Tests & banc d'essai

## boot_test.sh — boot headless d'une ROM sous FS-UAE

Lance FS-UAE dans un display virtuel Xvfb, laisse la ROM booter, capture l'écran émulé et rapporte les
couleurs dominantes. Pour la hello-ROM M0, un **fond vert** confirme que le coldstart a écrit COLOR00
(donc que notre code s'exécute sur l'A500 émulée).

```sh
tests/boot_test.sh [chemin/vers/rom] [secondes_de_boot]
# défaut : build/kick13-hello.rom, 10 s
```

Prérequis : `fs-uae`, `Xvfb`, `xwd`, `convert` (ImageMagick). Sorties dans `build/boot/` :
`hello.fs-uae` (config générée), `fs-uae.log`, `screen.png` (capture).

Résultat attendu M0 : couleur dominante `#00FF00` (vert) sur la zone active, log FS-UAE
« KS ROM … (262144 bytes) » sans erreur.

## À venir (dès M2)

Capture du **log série** (registre SERDAT) comme canal d'assertion primaire, marqueurs série par
milestone, et comparaison oracle boîte noire contre la vraie KS 1.3 (sondes comportementales ciblées).

## Audit clean-room — audit_rom_similarity.py, audit_aros_similarity.py

Mesures de similarité publiées dans [docs/AUDIT.md](../docs/AUDIT.md) (synthèse) et `docs/audit/` (détail). Les deux
outils n'affichent que des statistiques et des emplacements dans le premier argument (notre code).

```sh
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom <rom_kick13_de_référence> [--temoin NOM fichiers…] [--selftest]
python3 -I tests/audit_aros_similarity.py src <clone_aros>
```
