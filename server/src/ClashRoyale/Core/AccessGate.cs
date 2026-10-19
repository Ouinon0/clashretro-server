using System;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using ClashRoyale.Protocol.Messages.Client.Login;
using MySql.Data.MySqlClient;
using SharpRaven.Data;

namespace ClashRoyale.Core
{
    /// <summary>
    ///     Contrôle d'accès par invitation. Le client 1.9 n'a pas d'écran d'inscription : un nouvel
    ///     appareil reçoit un code d'appairage dans le message d'échec de connexion, que le joueur
    ///     saisit sur le portail avec son invitation. Tables : db/init/02_portal.sql.
    /// </summary>
    public static class AccessGate
    {
        private const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

        internal static string ConnectionString => new MySqlConnectionStringBuilder
        {
            Server = Resources.Configuration.MySqlServer,
            Database = Resources.Configuration.MySqlDatabase,
            UserID = Resources.Configuration.MySqlUserId,
            Password = Resources.Configuration.MySqlPassword,
            SslMode = MySqlSslMode.None,
            CharacterSet = "utf8mb4"
        }.ToString();

        public class Result
        {
            public bool Allowed;
            public long DeviceId;
            public string Reason;
        }

        public static async Task<Result> CheckAsync(LoginMessage login)
        {
            var settings = Resources.Configuration.Access;
            if (!settings.RequireInvite) return new Result {Allowed = true};

            try
            {
                using (var connection = new MySqlConnection(ConnectionString))
                {
                    await connection.OpenAsync();

                    return login.UserId > 0
                        ? await CheckExistingAsync(connection, login.UserId)
                        : await CheckNewDeviceAsync(connection, login);
                }
            }
            catch (Exception exception)
            {
                Logger.Log($"AccessGate: {exception.Message}", typeof(AccessGate), ErrorLevel.Error);
                return Deny("Serveur indisponible, réessaie plus tard.");
            }
        }

        public static async Task BindPlayerAsync(long deviceId, long playerId)
        {
            if (deviceId <= 0) return;

            using (var connection = new MySqlConnection(ConnectionString))
            {
                await connection.OpenAsync();
                using (var cmd = new MySqlCommand(
                    "UPDATE devices SET player_id = @player, last_seen_at = UTC_TIMESTAMP() WHERE id = @id",
                    connection))
                {
                    cmd.Parameters.AddWithValue("@player", playerId);
                    cmd.Parameters.AddWithValue("@id", deviceId);
                    await cmd.ExecuteNonQueryAsync();
                }
            }
        }

        private static async Task<Result> CheckExistingAsync(MySqlConnection connection, long playerId)
        {
            // Compte créé dans le jeu (pseudo + mot de passe) : lié directement au joueur.
            var account = await Accounts.PlayerAllowedAsync(connection, playerId);
            if (account == true) return new Result {Allowed = true};
            if (account == false) return Deny("Compte bloqué par l'admin.");

            using (var cmd = new MySqlCommand(
                "SELECT d.id, a.disabled_at FROM devices d JOIN accounts a ON a.id = d.account_id " +
                "WHERE d.player_id = @player AND d.status = 'approved' LIMIT 1", connection))
            {
                cmd.Parameters.AddWithValue("@player", playerId);
                using (var reader = await cmd.ExecuteReaderAsync())
                {
                    if (!await reader.ReadAsync())
                        return Deny("Ce compte n'est lié à aucun utilisateur. Contacte un admin.");
                    if (!reader.IsDBNull(1))
                        return Deny("Compte désactivé.");
                    return new Result {Allowed = true, DeviceId = reader.GetInt64(0)};
                }
            }
        }

        private static async Task<Result> CheckNewDeviceAsync(MySqlConnection connection, LoginMessage login)
        {
            var deviceKey = DeviceKey(login);
            var pairingCode = PairingCode(deviceKey);

            using (var upsert = new MySqlCommand(
                "INSERT INTO devices (device_key, pairing_code, platform, device_model, status) " +
                "VALUES (@key, @code, @platform, @model, 'pending') " +
                "ON DUPLICATE KEY UPDATE last_seen_at = UTC_TIMESTAMP()", connection))
            {
                upsert.Parameters.AddWithValue("@key", deviceKey);
                upsert.Parameters.AddWithValue("@code", pairingCode);
                upsert.Parameters.AddWithValue("@platform", login.IsAndroid == 1 ? "android" : "ios");
                upsert.Parameters.AddWithValue("@model", login.DeviceModel ?? "");
                await upsert.ExecuteNonQueryAsync();
            }

            using (var select = new MySqlCommand(
                "SELECT d.id, d.status, d.player_id, a.disabled_at FROM devices d " +
                "LEFT JOIN accounts a ON a.id = d.account_id WHERE d.device_key = @key", connection))
            {
                select.Parameters.AddWithValue("@key", deviceKey);
                using (var reader = await select.ExecuteReaderAsync())
                {
                    await reader.ReadAsync();
                    var status = reader.GetString(1);

                    if (status != "approved")
                        return Deny($"Nouvel appareil.\nCode d'appairage : {pairingCode}\n" +
                                    "Saisis-le sur le portail avec ton invitation, puis relance le jeu.\n" +
                                    "(Avec l'appli ClashRetro : « Créer un compte » au lancement.)");
                    if (!reader.IsDBNull(3))
                        return Deny("Compte désactivé.");
                    if (!reader.IsDBNull(2))
                        return Deny("Cet appareil a déjà un compte. Demande à un admin de le réinitialiser.");

                    return new Result {Allowed = true, DeviceId = reader.GetInt64(0)};
                }
            }
        }

        /// <summary>
        ///     Identifiant stable de l'appareil : AndroidId sur Android, OpenUDID/IDFV sur iOS.
        /// </summary>
        private static string DeviceKey(LoginMessage login)
        {
            string id = null;
            foreach (var candidate in new[] {login.AndroidId, login.OpenUdid, login.AdvertisingGuid, login.MacAddress})
                if (!string.IsNullOrWhiteSpace(candidate) && candidate.Trim('0', '-') != "")
                {
                    id = candidate;
                    break;
                }

            using (var sha = SHA256.Create())
            {
                var hash = sha.ComputeHash(Encoding.UTF8.GetBytes($"{id}|{login.DeviceModel}"));
                return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
            }
        }

        private static string PairingCode(string deviceKey)
        {
            using (var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(Resources.Configuration.Access.PairingSecret)))
            {
                var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(deviceKey));
                var code = new StringBuilder();
                for (var i = 0; i < 8; i++)
                {
                    if (i == 4) code.Append('-');
                    code.Append(Alphabet[hash[i] % Alphabet.Length]);
                }

                return code.ToString();
            }
        }

        private static Result Deny(string reason)
        {
            return new Result {Allowed = false, Reason = reason};
        }
    }
}
