# ClashRetro — serveur

Serveur privé pour jouer entre amis à Clash Royale 1.9 avec le client ClashRetro. Le dépôt contient :

- **game** : le serveur de jeu (.NET), fork de [retroroyale/ClashRoyale](https://github.com/retroroyale/ClashRoyale)
  (GPL-3.0, détail des modifications dans `server/UPSTREAM.md`) ;
- **portal** : le portail web (comptes, invitations, appairage des téléphones, administration,
  statistiques de combat anonymes, page des QR codes de combat amical) ;
- **db** : MariaDB avec le schéma.

Les images sont construites par GitHub Actions et publiées sur `ghcr.io/ouinon0/clashretro-{game,portal,db}`.

## TrueNAS SCALE (24.10 et suivants)

1. Dans **System → Shell**, créer le dossier de données pour l'utilisateur 950 :

   ```bash
   mkdir -p /mnt/Pool2/data/clash && chown 950:950 /mnt/Pool2/data/clash
   openssl rand -hex 32   # à lancer 5 fois : une valeur par « CHANGE_ME »
   ```

2. **Apps → Discover → ⋮ → Install via YAML**, nom `clashretro`, coller
   [`docker-compose.truenas.yml`](docker-compose.truenas.yml) et remplacer les `CHANGE_ME` (le mot
   de passe de la base apparaît deux fois, avec la même valeur). Les autres réglages (or, gemmes,
   durée des coffres, prix du magasin, invitations…) sont commentés dans le fichier.

3. Premier compte administrateur : le serveur écrit un code dans
   `/mnt/Pool2/data/clash/game/admin/premier-admin.txt`. Dans l'appli : « Créer un compte », choisir
   pseudo et mot de passe, saisir ce code. Le compte est admin et le fichier disparaît.

4. Dans l'appli, saisir le serveur `IP_DU_NAS:9339`. Chaque joueur trouve ses codes d'invitation
   dans **Paramètres → Compte** (masqués, révélés puis copiés au toucher, ✓ une fois utilisés) ; un
   ami crée son compte avec l'un d'eux, et peut se reconnecter depuis un autre téléphone avec son
   pseudo et son mot de passe.

### Gérer les comptes : un fichier texte

`/mnt/Pool2/data/clash/game/admin/comptes.txt` liste les comptes, une ligne par joueur, et est
relu et réécrit par le serveur toutes les quelques secondes :

```
# pseudo   | rôle   | invitations | état   | infos
bad        | admin  | auto        | actif  | quota du rôle : illimité · 2 invité(s) · …
alice      | invite | auto        | actif  | quota du rôle : 3 · 0 invité(s) · invité par bad · …
```

- **rôle** : `admin`, `proche` (10 invitations) ou `invite` (3 invitations)
- **invitations** : `auto` (quota du rôle) ou un nombre de codes pour ce joueur
- **état** : `actif`, `bloqué`, ou `nouveau-mdp` : le serveur remplace ce mot par un code
  (`code ABCD-2345`, valable 48 h) à donner au joueur, qui choisit un nouveau mot de passe dans
  l'appli (« Me connecter » → « Mot de passe oublié »).

Compte admin créé avant la version 0.3 (portail, `flask create-admin`) : se connecter une fois au
portail (le mot de passe est converti), puis « Me connecter » dans l'appli avec le même pseudo ;
le joueur du téléphone déjà appairé est repris. Mot de passe oublié : `nouveau-mdp` dans le fichier.

Le fichier ne contient ni mot de passe ni jeton : seul l'accès au NAS donne ces droits. Les mots
de passe sont hachés (PBKDF2-SHA256), les essais limités. Le portail web (port 8080) reste
disponible pour les statistiques de combat, les évènements et l'ancien client 32 bits.

| Port | Rôle |
|---|---|
| 9339/TCP | jeu |
| 8080/HTTP | portail ; aussi utilisé par les QR codes de combat amical (même hôte, port 8080) |

Pour des amis hors du réseau local : un VPN (Tailscale, app officielle TrueNAS) plutôt que
d'ouvrir les ports sur Internet.

Mise à jour : **Apps → clashretro → Update** (ou `docker compose pull && docker compose up -d`).
Sauvegarde : snapshot périodique du dataset qui contient `/mnt/Pool2/data/clash`.

Contenu de `/mnt/Pool2/data/clash` : `mariadb/` (base), `game/` (configuration générée, journaux,
`logs/battles/` journal de combat anonyme).

## Ailleurs (Docker / Podman)

```bash
cp .env.example .env      # remplir les secrets
docker compose up -d --build
cat data/game/admin/premier-admin.txt   # code du premier admin (comptes créés dans l'appli)
```

## Données personnelles

Aucune adresse IP n'est enregistrée. Le journal de combat ne contient ni pseudo ni IP (identifiants
hachés avec un sel, conservation limitée, désactivable). Chaque joueur peut exporter ou supprimer
ses données depuis le portail.

## Licence

GPL-3.0 (voir `LICENSE`). Les fichiers de données du jeu (`server/src/ClashRoyale/GameAssets`)
viennent du jeu d'origine, comme dans le dépôt retroroyale ; Clash Royale est une marque de
Supercell, ce projet n'y est pas affilié.
