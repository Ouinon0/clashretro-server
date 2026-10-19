-- Tâches que le portail confie au serveur de jeu (qui garde les joueurs en mémoire) :
-- suppression d'un joueur (droit à l'effacement), dons d'or / gemmes par un admin.
-- Le serveur les exécute toutes les 30 s (Core/GameJobs.cs) et remplit done_at / result.
CREATE TABLE IF NOT EXISTS game_jobs (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  kind        ENUM('delete_player','grant') NOT NULL,
  player_id   BIGINT          NOT NULL,
  payload     JSON            NULL,                           -- grant : {"gold": n, "gems": n}
  created_by  BIGINT UNSIGNED NULL,
  created_at  DATETIME        NOT NULL DEFAULT UTC_TIMESTAMP(),
  done_at     DATETIME        NULL,
  result      VARCHAR(128)    NULL,
  PRIMARY KEY (id),
  KEY ix_jobs_pending (done_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Évènements temporaires créés par un admin : bonus d'or / de cartes, annonce dans le jeu.
CREATE TABLE IF NOT EXISTS events (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title            VARCHAR(64)     NOT NULL,
  message          VARCHAR(255)    NULL,
  starts_at        DATETIME        NOT NULL,
  ends_at          DATETIME        NOT NULL,
  gold_multiplier  DECIMAL(5,2)    NOT NULL DEFAULT 1.00,
  card_multiplier  DECIMAL(5,2)    NOT NULL DEFAULT 1.00,
  created_by       BIGINT UNSIGNED NULL,
  created_at       DATETIME        NOT NULL DEFAULT UTC_TIMESTAMP(),
  PRIMARY KEY (id),
  KEY ix_events_time (starts_at, ends_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
