-- Utilisateurs, rôles, invitations, appareils et vue de progression.
-- Lu par le serveur de jeu (server/src/ClashRoyale/Core/AccessGate.cs) et par le portail.

SET time_zone = "+00:00";

-- invite_quota : nombre d'invitations actives autorisées ; NULL = illimité.
CREATE TABLE IF NOT EXISTS roles (
  id            TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name          VARCHAR(32)      NOT NULL,
  invite_quota  SMALLINT UNSIGNED NULL,
  can_admin     BOOLEAN          NOT NULL DEFAULT FALSE,
  PRIMARY KEY (id),
  UNIQUE KEY uq_roles_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO roles (name, invite_quota, can_admin) VALUES
  ('admin',  NULL, TRUE),
  ('proche', 10,   FALSE),
  ('invite', 3,    FALSE);

CREATE TABLE IF NOT EXISTS accounts (
  id                     BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  username               VARCHAR(32)      NOT NULL,
  password_hash          VARCHAR(255)     NOT NULL,          -- argon2id
  role_id                TINYINT UNSIGNED NOT NULL,
  invite_quota_override  SMALLINT UNSIGNED NULL,             -- prioritaire sur roles.invite_quota
  invited_by             BIGINT UNSIGNED  NULL,
  created_at             DATETIME         NOT NULL DEFAULT UTC_TIMESTAMP(),
  disabled_at            DATETIME         NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_accounts_username (username),
  CONSTRAINT fk_accounts_role    FOREIGN KEY (role_id)    REFERENCES roles (id),
  CONSTRAINT fk_accounts_inviter FOREIGN KEY (invited_by) REFERENCES accounts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS invitations (
  id          BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  code        CHAR(12)         NOT NULL,                      -- aléatoire, usage unique
  created_by  BIGINT UNSIGNED  NOT NULL,
  role_id     TINYINT UNSIGNED NOT NULL,                      -- rôle donné à l'invité
  note        VARCHAR(128)     NULL,
  created_at  DATETIME         NOT NULL DEFAULT UTC_TIMESTAMP(),
  expires_at  DATETIME         NOT NULL,
  used_by     BIGINT UNSIGNED  NULL,
  used_at     DATETIME         NULL,
  revoked_at  DATETIME         NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_invitations_code (code),
  UNIQUE KEY uq_invitations_used_by (used_by),
  KEY ix_invitations_creator (created_by),
  CONSTRAINT fk_invitations_creator FOREIGN KEY (created_by) REFERENCES accounts (id) ON DELETE CASCADE,
  CONSTRAINT fk_invitations_role    FOREIGN KEY (role_id)    REFERENCES roles (id),
  CONSTRAINT fk_invitations_user    FOREIGN KEY (used_by)    REFERENCES accounts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Un appareil = un compte de jeu (table player). Créé en 'pending' par le serveur de jeu à la
-- première connexion ; le portail le passe en 'approved' quand le joueur saisit son code.
CREATE TABLE IF NOT EXISTS devices (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_key    CHAR(64)        NOT NULL,                     -- sha256(identifiant appareil | modèle)
  pairing_code  CHAR(9)         NOT NULL,                     -- XXXX-XXXX
  platform      ENUM('android','ios') NOT NULL,
  device_model  VARCHAR(64)     NOT NULL DEFAULT '',
  status        ENUM('pending','approved','revoked') NOT NULL DEFAULT 'pending',
  account_id    BIGINT UNSIGNED NULL,
  player_id     BIGINT          NULL,                         -- player.Id une fois le compte créé
  created_at    DATETIME        NOT NULL DEFAULT UTC_TIMESTAMP(),
  approved_at   DATETIME        NULL,
  last_seen_at  DATETIME        NOT NULL DEFAULT UTC_TIMESTAMP(),
  PRIMARY KEY (id),
  UNIQUE KEY uq_devices_key (device_key),
  UNIQUE KEY uq_devices_pairing (pairing_code),
  UNIQUE KEY uq_devices_player (player_id),
  KEY ix_devices_account (account_id),
  CONSTRAINT fk_devices_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE SET NULL,
  CONSTRAINT fk_devices_player  FOREIGN KEY (player_id)  REFERENCES player (Id)   ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS audit_log (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  actor_id    BIGINT UNSIGNED NULL,
  action      VARCHAR(48)     NOT NULL,                       -- ex. invitation.create, device.approve
  target      VARCHAR(64)     NULL,
  details     JSON            NULL,
  created_at  DATETIME        NOT NULL DEFAULT UTC_TIMESTAMP(),
  PRIMARY KEY (id),
  KEY ix_audit_actor (actor_id),
  CONSTRAINT fk_audit_actor FOREIGN KEY (actor_id) REFERENCES accounts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Quota restant par utilisateur : invitations non révoquées (utilisées ou encore valides).
CREATE OR REPLACE VIEW v_invite_quota AS
SELECT a.id AS account_id,
       a.username,
       r.name AS role,
       COALESCE(a.invite_quota_override, r.invite_quota) AS quota,
       COUNT(i.id) AS used,
       CASE WHEN COALESCE(a.invite_quota_override, r.invite_quota) IS NULL THEN NULL
            ELSE GREATEST(COALESCE(a.invite_quota_override, r.invite_quota) - COUNT(i.id), 0)
       END AS remaining
FROM accounts a
JOIN roles r ON r.id = a.role_id
LEFT JOIN invitations i
       ON i.created_by = a.id AND i.revoked_at IS NULL
      AND (i.used_by IS NOT NULL OR i.expires_at > UTC_TIMESTAMP())
GROUP BY a.id, a.username, r.name, a.invite_quota_override, r.invite_quota;

-- Progression lisible depuis le JSON stocké par le serveur de jeu (player.Home).
CREATE OR REPLACE VIEW v_player_progress AS
SELECT p.Id AS player_id,
       d.account_id,
       acc.username,
       d.platform,
       JSON_UNQUOTE(JSON_EXTRACT(p.Home, '$.Home.name'))     AS name,
       JSON_EXTRACT(p.Home, '$.Home.exp_level')               AS exp_level,
       p.Trophies                                             AS trophies,
       JSON_EXTRACT(p.Home, '$.Home.gold')                    AS gold,
       JSON_EXTRACT(p.Home, '$.Home.diamonds')                AS gems,
       d.last_seen_at
FROM player p
LEFT JOIN devices  d   ON d.player_id = p.Id
LEFT JOIN accounts acc ON acc.id = d.account_id;
