using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using ClashRoyale.Database;
using MySql.Data.MySqlClient;
using SharpRaven.Data;

namespace ClashRoyale.Core
{
    /// <summary>
    ///     Comptes ClashRetro dans le jeu : pseudo + mot de passe, liés à un joueur (accounts.player_id).
    ///     Création avec un code d'invitation donné par un autre joueur, connexion depuis un autre
    ///     téléphone, mot de passe oublié (code de réinitialisation donné par l'admin), codes
    ///     d'invitation de chaque joueur. Le fichier d'administration est géré par AdminFile.
    ///
    ///     Sécurité : mots de passe en PBKDF2-SHA256 (210 000 itérations, sel aléatoire), comparaison
    ///     en temps constant, essais limités par pseudo, aucun mot de passe ni jeton dans les fichiers,
    ///     aucune IP enregistrée.
    /// </summary>
    public static class Accounts
    {
        public const string CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        private const int Iterations = 210000;
        private const int MaxFailures = 5;
        private static readonly TimeSpan LockTime = TimeSpan.FromMinutes(10);
        private static readonly ConcurrentDictionary<string, (int count, DateTime until)> Failures =
            new ConcurrentDictionary<string, (int, DateTime)>();

        /// <summary>Codes donnés à un joueur dont le rôle n'a pas de limite d'invitations.</summary>
        public const int UnlimitedVisibleCodes = 5;

        public class Result
        {
            public bool Ok;
            public string Message = "";
            public long PlayerId;
            public string Token = "";
            public string Username = "";
            public List<(string code, string usedBy)> Invites = new List<(string, string)>();
        }

        // --- Schéma ----------------------------------------------------------------------------

        public static async Task EnsureSchemaAsync()
        {
            try
            {
                using (var connection = new MySqlConnection(AccessGate.ConnectionString))
                {
                    await connection.OpenAsync();
                    foreach (var sql in new[]
                    {
                        "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS player_id BIGINT NULL",
                        "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS reset_code CHAR(8) NULL",
                        "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS reset_expires DATETIME NULL",
                        "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS last_login_at DATETIME NULL",
                        "CREATE UNIQUE INDEX IF NOT EXISTS uq_accounts_player ON accounts (player_id)"
                    })
                        using (var cmd = new MySqlCommand(sql, connection))
                        {
                            await cmd.ExecuteNonQueryAsync();
                        }
                }
            }
            catch (Exception exception)
            {
                Logger.Log($"Comptes : schéma non mis à jour ({exception.Message})", typeof(Accounts),
                    ErrorLevel.Error);
            }
        }

        // --- Mots de passe ---------------------------------------------------------------------

        public static string Hash(string password)
        {
            var salt = new byte[16];
            using (var rng = RandomNumberGenerator.Create())
            {
                rng.GetBytes(salt);
            }

            using (var kdf = new Rfc2898DeriveBytes(password, salt, Iterations, HashAlgorithmName.SHA256))
            {
                return $"pbkdf2_sha256${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(kdf.GetBytes(32))}";
            }
        }

        public static bool Verify(string password, string stored)
        {
            var parts = (stored ?? "").Split('$');
            if (parts.Length != 4 || parts[0] != "pbkdf2_sha256" || !int.TryParse(parts[1], out var iterations))
                return false;
            try
            {
                var salt = Convert.FromBase64String(parts[2]);
                var expected = Convert.FromBase64String(parts[3]);
                using (var kdf = new Rfc2898DeriveBytes(password, salt, iterations, HashAlgorithmName.SHA256))
                {
                    return CryptographicOperations.FixedTimeEquals(kdf.GetBytes(expected.Length), expected);
                }
            }
            catch (FormatException)
            {
                return false;
            }
        }

        public static string NewCode(int length = 8)
        {
            var code = new StringBuilder();
            for (var i = 0; i < length; i++)
                code.Append(CodeAlphabet[RandomNumberGenerator.GetInt32(CodeAlphabet.Length)]);
            return code.ToString();
        }

        /// <summary>« abcd-2345 » → « ABCD2345 ».</summary>
        public static string NormalizeCode(string code)
        {
            return new string((code ?? "").ToUpperInvariant().Where(char.IsLetterOrDigit).ToArray());
        }

        public static string FormatCode(string code)
        {
            return code != null && code.Length == 8 ? $"{code.Substring(0, 4)}-{code.Substring(4)}" : code ?? "";
        }

        private static bool ValidUsername(string name)
        {
            return name != null && name.Length >= 3 && name.Length <= 16 &&
                   name.All(c => char.IsLetterOrDigit(c) || c == '_' || c == '-' || c == '.');
        }

        private static string CheckPassword(string password)
        {
            return password == null || password.Length < 8
                ? "Mot de passe : 8 caractères minimum."
                : password.Length > 64 ? "Mot de passe trop long." : null;
        }

        // --- Limitation des essais --------------------------------------------------------------

        private static bool Locked(string key)
        {
            return Failures.TryGetValue(key, out var f) && f.count >= MaxFailures && f.until > DateTime.UtcNow;
        }

        private static void Fail(string key)
        {
            Failures.AddOrUpdate(key, _ => (1, DateTime.UtcNow + LockTime),
                (_, f) => (f.until < DateTime.UtcNow ? 1 : f.count + 1, DateTime.UtcNow + LockTime));
        }

        // --- Actions ---------------------------------------------------------------------------

        /// <summary>
        ///     Nouveau compte : pseudo, mot de passe et code d'invitation (code du premier admin tant
        ///     qu'il n'y a pas d'admin ; aucun code si le serveur n'exige pas d'invitation).
        /// </summary>
        public static async Task<Result> CreateAsync(string username, string password, string inviteCode,
            long existingPlayerId = 0)
        {
            username = (username ?? "").Trim();
            if (!ValidUsername(username))
                return Error("Pseudo : 3 à 16 lettres, chiffres, « _ », « - » ou « . ».");
            var bad = CheckPassword(password);
            if (bad != null) return Error(bad);
            var code = NormalizeCode(inviteCode);
            if (Locked("code")) return Error("Trop d'essais, réessaie dans quelques minutes.");

            using (var connection = new MySqlConnection(AccessGate.ConnectionString))
            {
                await connection.OpenAsync();
                using (var tx = connection.BeginTransaction())
                {
                    if (await ScalarAsync(connection, tx, "SELECT COUNT(*) FROM accounts WHERE username = @u",
                        ("@u", username)) > 0)
                        return Error("Ce pseudo est déjà pris.");

                    long roleId;
                    long? invitationId = null;
                    long? invitedBy = null;
                    if (await AdminFile.IsBootstrapCodeAsync(connection, tx, code))
                    {
                        roleId = await ScalarAsync(connection, tx, "SELECT id FROM roles WHERE name = 'admin'");
                    }
                    else if (code != "")
                    {
                        using (var cmd = new MySqlCommand(
                            "SELECT i.id, i.role_id, i.created_by FROM invitations i JOIN accounts a ON a.id = i.created_by " +
                            "WHERE i.code = @c AND i.used_by IS NULL AND i.revoked_at IS NULL " +
                            "AND i.expires_at > UTC_TIMESTAMP() AND a.disabled_at IS NULL FOR UPDATE", connection, tx))
                        {
                            cmd.Parameters.AddWithValue("@c", code);
                            using (var reader = await cmd.ExecuteReaderAsync())
                            {
                                if (!await reader.ReadAsync())
                                {
                                    Fail("code");
                                    return Error("Code d'invitation inconnu ou déjà utilisé.");
                                }

                                invitationId = reader.GetInt64(0);
                                roleId = reader.GetInt64(1);
                                invitedBy = reader.GetInt64(2);
                            }
                        }
                    }
                    else if (!Resources.Configuration.Access.RequireInvite || existingPlayerId > 0)
                    {
                        // Serveur de test sans invitation, ou joueur déjà admis qui sécurise son compte.
                        roleId = await ScalarAsync(connection, tx, "SELECT id FROM roles WHERE name = 'invite'");
                    }
                    else
                    {
                        return Error("Il faut un code d'invitation : demande-le à un ami déjà inscrit.");
                    }

                    var player = existingPlayerId > 0 ? null : await PlayerDb.CreateAsync();
                    if (existingPlayerId <= 0 && player == null) return Error("Création du joueur impossible.");
                    if (player != null)
                    {
                        // Le pseudo du compte devient le nom du joueur (modifiable ensuite dans le jeu).
                        player.Home.Name = username;
                        player.Home.NameSet = 1;
                        await PlayerDb.SaveAsync(player);
                    }
                    var playerId = existingPlayerId > 0 ? existingPlayerId : player.Home.Id;

                    long accountId;
                    using (var cmd = new MySqlCommand(
                        "INSERT INTO accounts (username, password_hash, role_id, invited_by, player_id, last_login_at) " +
                        "VALUES (@u, @h, @r, @by, @p, UTC_TIMESTAMP())", connection, tx))
                    {
                        cmd.Parameters.AddWithValue("@u", username);
                        cmd.Parameters.AddWithValue("@h", Hash(password));
                        cmd.Parameters.AddWithValue("@r", roleId);
                        cmd.Parameters.AddWithValue("@by", (object) invitedBy ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@p", playerId);
                        await cmd.ExecuteNonQueryAsync();
                        accountId = cmd.LastInsertedId;
                    }

                    if (invitationId != null)
                        await ExecAsync(connection, tx,
                            "UPDATE invitations SET used_by = @a, used_at = UTC_TIMESTAMP() WHERE id = @i",
                            ("@a", accountId), ("@i", invitationId.Value));

                    tx.Commit();
                    AdminFile.RequestRefresh();
                    return new Result
                    {
                        Ok = true, PlayerId = playerId, Username = username,
                        Token = player?.Home.UserToken ?? ""
                    };
                }
            }
        }

        /// <summary>Connexion avec pseudo et mot de passe : renvoie le joueur (identifiant et jeton).</summary>
        public static async Task<Result> LoginAsync(string username, string password)
        {
            username = (username ?? "").Trim();
            var key = "login:" + username.ToLowerInvariant();
            if (Locked(key)) return Error("Trop d'essais pour ce pseudo, réessaie dans 10 minutes.");

            using (var connection = new MySqlConnection(AccessGate.ConnectionString))
            {
                await connection.OpenAsync();
                long accountId = 0, playerId = 0;
                string hash = null;
                var disabled = false;
                using (var cmd = new MySqlCommand(
                    "SELECT id, password_hash, player_id, disabled_at IS NOT NULL FROM accounts WHERE username = @u",
                    connection))
                {
                    cmd.Parameters.AddWithValue("@u", username);
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            accountId = reader.GetInt64(0);
                            hash = reader.GetString(1);
                            playerId = reader.IsDBNull(2) ? 0 : reader.GetInt64(2);
                            disabled = reader.GetBoolean(3);
                        }
                    }
                }

                // Même travail que le pseudo existe ou non (pas d'indice sur les pseudos inscrits).
                var ok = Verify(password ?? "", hash ?? Hash("x"));
                if (!ok || accountId == 0)
                {
                    Fail(key);
                    return Error("Pseudo ou mot de passe incorrect.");
                }

                if (disabled) return Error("Compte bloqué par l'admin.");
                if (playerId == 0)
                {
                    // Compte du portail : le joueur de son téléphone appairé, sinon un nouveau joueur.
                    playerId = await ScalarAsync(connection, null,
                        "SELECT player_id FROM devices WHERE account_id = @a AND status = 'approved' " +
                        "AND player_id IS NOT NULL ORDER BY last_seen_at DESC LIMIT 1", ("@a", accountId));
                    if (playerId == 0)
                    {
                        var created = await PlayerDb.CreateAsync();
                        if (created == null) return Error("Création du joueur impossible.");
                        created.Home.Name = username;
                        created.Home.NameSet = 1;
                        await PlayerDb.SaveAsync(created);
                        playerId = created.Home.Id;
                    }

                    await ExecAsync(connection, null, "UPDATE accounts SET player_id = @p WHERE id = @a",
                        ("@p", playerId), ("@a", accountId));
                }

                var token = await TokenOfAsync(connection, playerId);
                if (token == null) return Error("Joueur introuvable.");
                Failures.TryRemove(key, out _);
                await ExecAsync(connection, null, "UPDATE accounts SET last_login_at = UTC_TIMESTAMP() WHERE id = @a",
                    ("@a", accountId));
                return new Result {Ok = true, PlayerId = playerId, Token = token, Username = username};
            }
        }

        /// <summary>Mot de passe oublié : code de réinitialisation donné par l'admin (fichier comptes).</summary>
        public static async Task<Result> ResetAsync(string username, string resetCode, string newPassword)
        {
            username = (username ?? "").Trim();
            var bad = CheckPassword(newPassword);
            if (bad != null) return Error(bad);
            var key = "reset:" + username.ToLowerInvariant();
            if (Locked(key)) return Error("Trop d'essais, réessaie dans 10 minutes.");

            using (var connection = new MySqlConnection(AccessGate.ConnectionString))
            {
                await connection.OpenAsync();
                var updated = await ExecAsync(connection, null,
                    "UPDATE accounts SET password_hash = @h, reset_code = NULL, reset_expires = NULL " +
                    "WHERE username = @u AND reset_code = @c AND reset_expires > UTC_TIMESTAMP() AND disabled_at IS NULL",
                    ("@h", Hash(newPassword)), ("@u", username), ("@c", NormalizeCode(resetCode)));
                if (updated == 0)
                {
                    Fail(key);
                    return Error("Code de réinitialisation invalide ou expiré.");
                }

                AdminFile.RequestRefresh();
                return await LoginAsync(username, newPassword);
            }
        }

        /// <summary>
        ///     Compte du joueur connecté et ses codes d'invitation (créés au besoin jusqu'au quota).
        /// </summary>
        public static async Task<Result> InvitesAsync(long playerId)
        {
            using (var connection = new MySqlConnection(AccessGate.ConnectionString))
            {
                await connection.OpenAsync();
                long accountId = 0;
                string username = null;
                long? quota = null;
                string role = "";
                using (var cmd = new MySqlCommand(
                    "SELECT a.id, a.username, COALESCE(a.invite_quota_override, r.invite_quota), r.name FROM accounts a " +
                    "JOIN roles r ON r.id = a.role_id WHERE a.disabled_at IS NULL AND (a.player_id = @p OR a.id = " +
                    "(SELECT account_id FROM devices WHERE player_id = @p AND status = 'approved' LIMIT 1)) LIMIT 1",
                    connection))
                {
                    cmd.Parameters.AddWithValue("@p", playerId);
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            accountId = reader.GetInt64(0);
                            username = reader.GetString(1);
                            quota = reader.IsDBNull(2) ? (long?) null : reader.GetInt64(2);
                            role = reader.GetString(3);
                        }
                    }
                }

                if (accountId == 0) return new Result {Ok = true};

                var invites = new List<(string code, string usedBy)>();
                using (var cmd = new MySqlCommand(
                    "SELECT i.code, u.username, i.used_by IS NOT NULL FROM invitations i LEFT JOIN accounts u ON u.id = i.used_by " +
                    "WHERE i.created_by = @a AND i.revoked_at IS NULL AND (i.used_by IS NOT NULL OR i.expires_at > UTC_TIMESTAMP()) " +
                    "ORDER BY i.id", connection))
                {
                    cmd.Parameters.AddWithValue("@a", accountId);
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        while (await reader.ReadAsync())
                            invites.Add((FormatCode(reader.GetString(0)),
                                reader.GetBoolean(2) ? reader.IsDBNull(1) ? "?" : reader.GetString(1) : null));
                    }
                }

                var unused = invites.Count(i => i.usedBy == null);
                var missing = quota == null ? UnlimitedVisibleCodes - unused : (int) quota.Value - invites.Count;
                var inviteeRole = role == "admin" ? "proche" : "invite";
                for (var i = 0; i < missing; i++)
                {
                    var code = NewCode();
                    await ExecAsync(connection, null,
                        "INSERT INTO invitations (code, created_by, role_id, note, expires_at) " +
                        "SELECT @c, @a, id, 'jeu', DATE_ADD(UTC_TIMESTAMP(), INTERVAL 10 YEAR) FROM roles WHERE name = @r",
                        ("@c", code), ("@a", accountId), ("@r", inviteeRole));
                    invites.Add((FormatCode(code), null));
                }

                return new Result {Ok = true, Username = username, Invites = invites};
            }
        }

        // --- Accès ---------------------------------------------------------------------------

        /// <summary>Vrai si le joueur appartient à un compte actif ; null s'il n'a pas de compte.</summary>
        public static async Task<bool?> PlayerAllowedAsync(MySqlConnection connection, long playerId)
        {
            using (var cmd = new MySqlCommand("SELECT disabled_at IS NULL FROM accounts WHERE player_id = @p",
                connection))
            {
                cmd.Parameters.AddWithValue("@p", playerId);
                var value = await cmd.ExecuteScalarAsync();
                return value == null || value is DBNull ? (bool?) null : Convert.ToBoolean(value);
            }
        }

        // --- Outils --------------------------------------------------------------------------

        private static async Task<string> TokenOfAsync(MySqlConnection connection, long playerId)
        {
            var cached = Resources.ObjectCache.GetCachedPlayer(playerId);
            if (cached != null) return cached.Home.UserToken;
            var player = await PlayerDb.GetAsync(playerId);
            return player?.Home.UserToken;
        }

        private static Result Error(string message)
        {
            return new Result {Ok = false, Message = message};
        }

        internal static async Task<long> ScalarAsync(MySqlConnection connection, MySqlTransaction tx, string sql,
            params (string name, object value)[] args)
        {
            using (var cmd = new MySqlCommand(sql, connection, tx))
            {
                foreach (var (name, value) in args) cmd.Parameters.AddWithValue(name, value);
                var result = await cmd.ExecuteScalarAsync();
                return result == null || result is DBNull ? 0 : Convert.ToInt64(result);
            }
        }

        internal static async Task<int> ExecAsync(MySqlConnection connection, MySqlTransaction tx, string sql,
            params (string name, object value)[] args)
        {
            using (var cmd = new MySqlCommand(sql, connection, tx))
            {
                foreach (var (name, value) in args) cmd.Parameters.AddWithValue(name, value);
                return await cmd.ExecuteNonQueryAsync();
            }
        }
    }
}
