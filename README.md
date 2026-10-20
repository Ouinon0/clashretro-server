# Clash Royale : Modern Classic — serveur

Serveur privé pour jouer entre amis à **Clash Royale : Modern Classic** : le gameplay de l'Âge d'Or
(1.9 / 2.2 : 1c1, 2c2, cycle de coffres, clans, demandes et dons) dans l'interface des versions
actuelles. Un seul conteneur, sans base de données :

- **jeu** (UDP 19340) : comptes, appariement 1c1 / 2c2 (IA si personne n'arrive), combats
  arbitrés par le serveur à latence minimale (poses relayées dès réception, retour en arrière côté
  appli), reprise après coupure, progression de la 1.9, boutique, clans ;
- **web** (TCP 19341) : page d'accueil pour les amis (téléchargement de l'appli, code
  d'invitation) et **admin** sur `/admin`.

Le serveur est un projet Godot 4.4 sans écran (`godot/`, aucun asset du jeu) ; l'image est
construite par GitHub Actions et publiée sur `ghcr.io/ouinon0/clashretro-modern:latest`.

## Installation

### TrueNAS SCALE

**Apps → Discover → ⋮ → Install via YAML**, nom `clash`, coller
[`docker-compose.truenas.yml`](docker-compose.truenas.yml), **Save**. Seul le chemin des données
(`/mnt/Pool2/data/clash/modern`) est à adapter ; il est créé au premier lancement.

### Docker / Podman

```sh
docker compose up -d
docker compose logs clash      # mot de passe de l'admin web (premier démarrage)
```

## Premiers pas

1. Ouvrir `http://IP_DU_SERVEUR:19341/admin` avec le mot de passe du journal (ou celui de
   `CLASH_ADMIN_PASSWORD`), puis le changer dans **Réglages**.
2. **Invitations** : créer un code par ami. Le lien `http://IP_DU_SERVEUR:19341/i/CODE` affiche
   le code et le bouton de téléchargement de l'appli.
3. Pour proposer l'appli au téléchargement : déposer l'APK sous le nom `clash-modern.apk` dans le
   dossier des données.
4. Dans l'appli : **Menu ☰ → Paramètres → Serveur** = adresse du serveur, et le code d'invitation.

## Admin web

| Onglet | Contenu |
|---|---|
| Vue d'ensemble | joueurs connectés, combats en cours, files d'attente ; annonce immédiate à tous les joueurs |
| Joueurs | pseudo, niveau, trophées, or, gemmes, victoires, clan, parrain, dernière visite (jour) ; donner or / gemmes / cartes / coffres, renommer, trophées, niveau, toutes les cartes au max, suspendre, réinitialiser, supprimer |
| Événements | titre, message, couleur, début / fin, bonus d'or et de cartes, mode de jeu (double ou triple élixir, niveaux de tournoi, mort subite, combat libre ; 1c1 ou 2c2), trophées et coffres en jeu ou non |
| Boutique | prix (%), packs d'or contre gemmes, offres spéciales (or, gemmes, cartes, coffres ; gratuites ou payantes ; limite par joueur ; période) |
| Invitations | créer (note, nombre d'utilisations), lien à partager, qui l'a utilisée, annuler |
| Actualités | textes affichés dans l'onglet Événements de l'appli |
| Clans | membres, renommer, dissoudre |
| Réglages | nom du serveur, accès (libre, code commun, invitation), invitations par joueur, or et gemmes de départ, contenu des coffres, durée de déverrouillage, IA, durée des combats… |
| Journal | combats et nouveaux comptes |

**Vie privée** : le serveur ne garde ni adresse IP, ni identifiant d'appareil ; un compte, c'est
un pseudo, un jeton (dans l'appli) et la progression. L'admin ne voit que des dates (jour).

## Données

Fichiers JSON dans le dossier des données : `accounts.json`, `clans.json`, `settings.json`,
`events.json`, `offers.json`, `invites.json`, `news.json`, `admin.json` (empreinte du mot de
passe). Sauvegarder ce dossier suffit.

## Construire soi-même

```sh
docker build -t clashretro-modern .
```

L'ancien serveur (.NET, portail, MariaDB, client 1.9 32 bits) reste dans l'historique du dépôt
(étiquette `legacy-0.3`).
