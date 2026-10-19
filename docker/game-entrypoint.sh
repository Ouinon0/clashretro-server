#!/bin/sh
# Génère config.json depuis l'environnement puis lance le serveur.
# Sans config.json, le serveur retroroyale attend une touche au clavier : on l'écrit toujours ici.
set -eu

# Secrets dans des fichiers (VAR_FILE, ex. /data/secrets/…) quand ils ne sont pas donnés directement.
for var in MYSQL_PASSWORD CLUSTER_KEY PAIRING_SECRET BATTLE_LOG_SALT; do
  file=$(eval "printf '%s' \"\${${var}_FILE:-}\"")
  current=$(eval "printf '%s' \"\${${var}:-}\"")
  if [ -z "$current" ] && [ -n "$file" ] && [ -r "$file" ]; then
    export "$var=$(cat "$file")"
  fi
done

: "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}" "${MYSQL_PASSWORD:?}" "${CLUSTER_KEY:?}" "${PAIRING_SECRET:?}"

# Dossier de travail (config.json, journaux) : /app par défaut ; avec un utilisateur imposé
# (TrueNAS, user: "950:950"), un dossier du volume de données, ex. GAME_WORK_DIR=/data/game.
WORK="${GAME_WORK_DIR:-/app}"
mkdir -p "$WORK"
cd "$WORK"
[ "$WORK" = /app ] || ln -sfn /app/GameAssets GameAssets
BATTLE_LOG_DIR="${BATTLE_LOG_DIR:-$WORK/logs/battles}"
mkdir -p "$BATTLE_LOG_DIR"

cat > config.json <<JSON
{
  "encryption_key": "${GAME_ENCRYPTION_KEY:-fhsd6f86f67rt8fw78fw789we78r9789wer6re}",
  "cluster_encryption_key": "${CLUSTER_KEY}",
  "cluster_encryption_nonce": "nonce",
  "cluster_server_port": 9876,
  "mysql_server": "${MYSQL_HOST:-db}",
  "mysql_database": "${MYSQL_DATABASE}",
  "mysql_user": "${MYSQL_USER}",
  "mysql_password": "${MYSQL_PASSWORD}",
  "server_port": 9339,
  "patch_url": "${PATCH_URL:-}",
  "use_content_patch": ${USE_CONTENT_PATCH:-false},
  "update_url": "",
  "sentry_api": "",
  "use_udp": false,
  "progression": {
    "starting_gold": ${START_GOLD:-5000},
    "starting_gems": ${START_GEMS:-1000000},
    "card_multiplier": ${CARD_MULTIPLIER:-3},
    "gold_multiplier": ${GOLD_MULTIPLIER:-5},
    "min_chest_gold": ${MIN_CHEST_GOLD:-100},
    "unlock_time_percent": ${UNLOCK_TIME_PERCENT:-25},
    "chat_cheats": ${CHAT_CHEATS:-false},
    "shop_price_percent": ${SHOP_PRICE_PERCENT:-50}
  },
  "access": {
    "require_invite": ${REQUIRE_INVITE:-true},
    "pairing_secret": "${PAIRING_SECRET}",
    "admin_directory": "${ADMIN_DIR:-$WORK/admin}"
  },
  "battle_logs": {
    "enabled": ${BATTLE_LOGS:-true},
    "directory": "${BATTLE_LOG_DIR}",
    "retention_days": ${BATTLE_LOG_RETENTION_DAYS:-90},
    "salt": "${BATTLE_LOG_SALT:-$PAIRING_SECRET}"
  }
}
JSON

exec dotnet /app/ClashRoyale.dll
