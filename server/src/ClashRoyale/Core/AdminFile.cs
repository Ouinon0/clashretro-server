using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using MySql.Data.MySqlClient;
using SharpRaven.Data;

namespace ClashRoyale.Core
{
    /// <summary>
    ///     Administration par fichier texte, dans le dossier de données du serveur (admin/) :
    ///     <list type="bullet">
    ///         <item>comptes.txt : un compte par ligne (pseudo | rôle | invitations | état | infos), réécrit par
    ///         le serveur ; l'admin y change un rôle, un quota, bloque un compte ou demande un nouveau mot
    ///         de passe (« nouveau-mdp » : le serveur y inscrit un code à donner au joueur).</item>
    ///         <item>premier-admin.txt : tant qu'aucun admin n'existe, le code qui crée le compte admin
    ///         depuis le jeu (fichier supprimé ensuite).</item>
    ///     </list>
    ///     Le fichier ne contient ni mot de passe ni jeton : seul l'accès au NAS donne ces droits.
    /// </summary>
    public static class AdminFile
    {
        private const string AccountsFile = "comptes.txt";
        private const string BootstrapFile = "premier-admin.txt";
        private static readonly string[] Roles = {"admin", "proche", "invite"};
        private static Timer _timer;
        private static int _running;
        private static DateTime _lastWrite = DateTime.MinValue;
        private static long _refreshAt;

        private static string Directory => Path.GetFullPath(Resources.Configuration.Access.AdminDirectory);

        public static void Start()
        {
            _timer = new Timer(_ => Run(), null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(3));
        }

        /// <summary>Réécrire le fichier bientôt (nouveau compte, mot de passe changé…).</summary>
        public static void RequestRefresh()
        {
            Interlocked.Exchange(ref _refreshAt, 1);
        }

        // --- Premier admin ---------------------------------------------------------------------

        private static string BootstrapCode()
        {
            using (var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(Resources.Configuration.Access.PairingSecret)))
            {
                var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes("clashretro-premier-admin"));
                return new string(hash.Take(8).Select(b => Accounts.CodeAlphabet[b % Accounts.CodeAlphabet.Length])
                    .ToArray());
            }
        }

        public static async Task<bool> IsBootstrapCodeAsync(MySqlConnection connection, MySqlTransaction tx,
            string code)
        {
            if (code != BootstrapCode()) return false;
            return await Accounts.ScalarAsync(connection, tx,
                "SELECT COUNT(*) FROM accounts a JOIN roles r ON r.id = a.role_id WHERE r.can_admin") == 0;
        }

        // --- Synchronisation -------------------------------------------------------------------

        private static int _tick;

        private static async void Run()
        {
            if (Interlocked.Exchange(ref _running, 1) == 1) return;
            try
            {
                System.IO.Directory.CreateDirectory(Directory);
                var path = Path.Combine(Directory, AccountsFile);
                var edited = File.Exists(path) && File.GetLastWriteTimeUtc(path) != _lastWrite;
                var refresh = Interlocked.Exchange(ref _refreshAt, 0) == 1 || edited || _tick++ % 20 == 0;
                if (!refresh) return;

                using (var connection = new MySqlConnection(AccessGate.ConnectionString))
                {
                    await connection.OpenAsync();
                    if (edited)
                        await ApplyAsync(connection, File.ReadAllLines(path, Encoding.UTF8));
                    await WriteAsync(connection, path);
                    await WriteBootstrapAsync(connection);
                }
            }
            catch (Exception exception)
            {
                Logger.Log($"Fichier d'administration : {exception.Message}", typeof(AdminFile), ErrorLevel.Error);
            }
            finally
            {
                Interlocked.Exchange(ref _running, 0);
            }
        }

        private static async Task ApplyAsync(MySqlConnection connection, IEnumerable<string> lines)
        {
            foreach (var raw in lines)
            {
                var line = raw.Trim();
                if (line == "" || line.StartsWith("#")) continue;
                var cells = line.Split('|').Select(c => c.Trim()).ToArray();
                if (cells.Length < 4) continue;
                var username = cells[0];
                var role = cells[1].ToLowerInvariant().Replace("é", "e");
                var quota = cells[2].ToLowerInvariant();
                var state = cells[3].ToLowerInvariant();

                if (Roles.Contains(role))
                    await Accounts.ExecAsync(connection, null,
                        "UPDATE accounts SET role_id = (SELECT id FROM roles WHERE name = @r) WHERE username = @u",
                        ("@r", role), ("@u", username));

                if (quota == "auto")
                    await Accounts.ExecAsync(connection, null,
                        "UPDATE accounts SET invite_quota_override = NULL WHERE username = @u", ("@u", username));
                else if (int.TryParse(quota, out var n) && n >= 0 && n <= 500)
                    await Accounts.ExecAsync(connection, null,
                        "UPDATE accounts SET invite_quota_override = @q WHERE username = @u", ("@q", n), ("@u", username));

                if (state.StartsWith("bloqu"))
                    await Accounts.ExecAsync(connection, null,
                        "UPDATE accounts SET disabled_at = COALESCE(disabled_at, UTC_TIMESTAMP()) WHERE username = @u",
                        ("@u", username));
                else if (state == "actif")
                    await Accounts.ExecAsync(connection, null,
                        "UPDATE accounts SET disabled_at = NULL WHERE username = @u", ("@u", username));

                if (state.StartsWith("nouveau-mdp") || state.StartsWith("nouveau mdp"))
                {
                    await Accounts.ExecAsync(connection, null,
                        "UPDATE accounts SET reset_code = @c, reset_expires = DATE_ADD(UTC_TIMESTAMP(), INTERVAL 48 HOUR), " +
                        "disabled_at = NULL WHERE username = @u", ("@c", Accounts.NewCode()), ("@u", username));
                    Logger.Log($"Comptes : code de nouveau mot de passe créé pour {username}.", typeof(AdminFile),
                        ErrorLevel.Info);
                }
            }
        }

        private static async Task WriteAsync(MySqlConnection connection, string path)
        {
            var rows = new List<string[]>();
            using (var cmd = new MySqlCommand(
                "SELECT a.username, r.name, a.invite_quota_override, r.invite_quota, a.disabled_at, a.reset_code, " +
                "a.reset_expires, b.username, a.created_at, a.last_login_at, a.player_id, " +
                "(SELECT COUNT(*) FROM invitations i WHERE i.created_by = a.id AND i.used_by IS NOT NULL) " +
                "FROM accounts a JOIN roles r ON r.id = a.role_id LEFT JOIN accounts b ON b.id = a.invited_by " +
                "ORDER BY a.created_at, a.id", connection))
            using (var reader = await cmd.ExecuteReaderAsync())
            {
                while (await reader.ReadAsync())
                {
                    var quota = reader.IsDBNull(2) ? "auto" : reader.GetInt32(2).ToString();
                    var roleQuota = reader.IsDBNull(3) ? "illimité" : reader.GetInt32(3).ToString();
                    string state;
                    if (!reader.IsDBNull(4)) state = "bloqué";
                    else if (!reader.IsDBNull(5) && !reader.IsDBNull(6) && reader.GetDateTime(6) > DateTime.UtcNow)
                        state = $"code {Accounts.FormatCode(reader.GetString(5))}";
                    else state = "actif";

                    var info = new List<string>();
                    if (quota == "auto") info.Add($"quota du rôle : {roleQuota}");
                    info.Add($"{reader.GetInt64(11)} invité(s)");
                    if (!reader.IsDBNull(7)) info.Add($"invité par {reader.GetString(7)}");
                    info.Add($"créé le {reader.GetDateTime(8):dd/MM/yyyy}");
                    if (!reader.IsDBNull(9)) info.Add($"vu le {reader.GetDateTime(9):dd/MM/yyyy}");
                    if (reader.IsDBNull(10)) info.Add("ancien compte du portail");
                    if (state.StartsWith("code") && !reader.IsDBNull(6))
                        info.Add($"code valable jusqu'au {reader.GetDateTime(6):dd/MM HH:mm} UTC");
                    rows.Add(new[] {reader.GetString(0), reader.GetString(1), quota, state, string.Join(" · ", info)});
                }
            }

            var widths = Enumerable.Range(0, 4)
                .Select(i => Math.Max(new[] {"pseudo", "rôle", "invitations", "état"}[i].Length,
                    rows.Count == 0 ? 0 : rows.Max(r => r[i].Length))).ToArray();
            var text = new StringBuilder();
            text.AppendLine("# Comptes ClashRetro — fichier lu et réécrit par le serveur (quelques secondes).");
            text.AppendLine("# Modifier une colonne puis enregistrer :");
            text.AppendLine("#   rôle        : admin, proche ou invite (quota d'invitations : admin illimité,");
            text.AppendLine("#                 proche 10, invite 3)");
            text.AppendLine("#   invitations : auto (quota du rôle) ou un nombre de codes pour ce joueur");
            text.AppendLine("#   état        : actif, bloqué, ou nouveau-mdp → le serveur écrit un code à donner");
            text.AppendLine("#                 au joueur (« Mot de passe oublié » dans le jeu, valable 48 h)");
            text.AppendLine("# La dernière colonne (infos) est ignorée à la lecture. Aucun mot de passe ici.");
            text.AppendLine("#");
            text.AppendLine("# " + string.Join(" | ", new[] {"pseudo", "rôle", "invitations", "état"}
                .Select((h, i) => h.PadRight(widths[i] - (i == 0 ? 2 : 0)))) + " | infos");
            foreach (var r in rows)
                text.AppendLine(string.Join(" | ", r.Take(4).Select((c, i) => c.PadRight(widths[i]))) + " | " + r[4]);

            var content = text.ToString();
            if (!File.Exists(path) || File.ReadAllText(path, Encoding.UTF8) != content)
            {
                var tmp = path + ".tmp";
                File.WriteAllText(tmp, content, new UTF8Encoding(false));
                File.Move(tmp, path, true);
            }

            _lastWrite = File.GetLastWriteTimeUtc(path);
        }

        private static async Task WriteBootstrapAsync(MySqlConnection connection)
        {
            var path = Path.Combine(Directory, BootstrapFile);
            var admins = await Accounts.ScalarAsync(connection, null,
                "SELECT COUNT(*) FROM accounts a JOIN roles r ON r.id = a.role_id WHERE r.can_admin");
            if (admins > 0)
            {
                if (File.Exists(path)) File.Delete(path);
                return;
            }

            if (File.Exists(path)) return;
            var code = Accounts.FormatCode(BootstrapCode());
            File.WriteAllText(path,
                "Premier compte administrateur\n\n" +
                $"Code : {code}\n\n" +
                "Dans le jeu : « Créer un compte », choisis ton pseudo et ton mot de passe, puis saisis ce code.\n" +
                "Le compte créé est admin ; ce fichier disparaît ensuite. Ne le partage pas.\n",
                new UTF8Encoding(false));
            Logger.Log($"Aucun admin : code du premier admin dans {path}", typeof(AdminFile), ErrorLevel.Info);
        }
    }
}
