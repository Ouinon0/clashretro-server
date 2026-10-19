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

3. Créer le compte administrateur du portail (une fois) :

   ```bash
   sudo docker exec -it clashretro-portal-1 flask create-admin
   ```

4. Ouvrir le portail sur `http://IP_DU_NAS:8080`, créer des invitations pour les amis. Dans
   l'appli, saisir le serveur `IP_DU_NAS:9339`.

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
docker compose exec portal flask create-admin
```

## Données personnelles

Aucune adresse IP n'est enregistrée. Le journal de combat ne contient ni pseudo ni IP (identifiants
hachés avec un sel, conservation limitée, désactivable). Chaque joueur peut exporter ou supprimer
ses données depuis le portail.

## Licence

GPL-3.0 (voir `LICENSE`). Les fichiers de données du jeu (`server/src/ClashRoyale/GameAssets`)
viennent du jeu d'origine, comme dans le dépôt retroroyale ; Clash Royale est une marque de
Supercell, ce projet n'y est pas affilié.
