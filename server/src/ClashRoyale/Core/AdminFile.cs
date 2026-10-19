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
    ///         <item>admins.txt : créé au démarrage avec un exemple ; une ligne « pseudo : mot de passe »
    ///         crée un compte admin (ou « pseudo » passe admin un compte existant), puis le mot de passe
    ///         est effacé du fichier.</item>
    ///     </list>
    ///     Le fichier ne contient ni mot de passe ni jeton : seul l'accès au NAS donne ces droits.
    /// </summary>
    public static class AdminFile
    {
        private const string AccountsFile = "comptes.txt";
        private const string BootstrapFile = "premier-admin.txt";   // ancienne version, supprimé
        private const string AdminsFile = "admins.txt";
        private static DateTime _adminsWrite = DateTime.MinValue;

        private const string AdminsExample =
            "# Comptes administrateurs ClashRetro\n" +
            "#\n" +
            "# Pour ajouter un admin : écrire une ligne « pseudo : mot de passe » (8 caractères minimum)\n" +
            "# sous ces explications, puis enregistrer. En quelques secondes, le serveur crée le compte\n" +
            "# (avec son joueur) et remplace la ligne par « # pseudo — admin ✓ » : le mot de passe ne reste\n" +
            "# pas dans ce fichier. Dans l'appli : « Me connecter » avec ce pseudo et ce mot de passe.\n" +
            "#\n" +
            "# Joueur déjà inscrit dans l'appli : écrire seulement son pseudo pour le passer admin.\n" +
            "# Retirer un admin : changer son rôle dans comptes.txt.\n" +
            "#\n" +
            "# Exemples (sans le # du début) :\n" +
            "#   bad : MonMotDePasse123\n" +
            "#   alice\n" +
            "\n";
        private static readonly string[] Roles = {"admin", "proche", "invite"};
        private static Timer _timer;
        private static int _running;
        private static DateTime _lastWrite = DateTime.MinValue;
        private static long _refreshAt;

        private static string Directory => Path.GetFullPath(Resources.Configuration.Access.AdminDirectory);

        public static void Start()
        {
            try
            {
                System.IO.Directory.CreateDirectory(Directory);
                var admins = Path.Combine(Directory, AdminsFile);
                if (!File.Exists(admins)) File.WriteAllText(admins, AdminsExample, new UTF8Encoding(false));
                Logger.Log($"Administration : {Directory} (admins.txt, comptes.txt)", typeof(AdminFile), ErrorLevel.Info);
            }
            catch (Exception exception)
            {
                Logger.Log($"Dossier d'administration : {exception.Message}", typeof(AdminFile), ErrorLevel.Error);
            }

            _timer = new Timer(_ => Run(), null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(3));
        }

        /// <summary>Réécrire le fichier bientôt (nouveau compte, mot de passe changé…).</summary>
        public static void RequestRefresh()
        {
            Interlocked.Exchange(ref _refreshAt, 1);
        }

        // --- Synchronisation -------------------------------------------------------------------

        private static int _tick;

        private static async void Run()
        {
            if (Interlocked.Exchange(ref _running, 1) == 1) return;
            try
            {
                System.IO.Directory.CreateDirectory(Directory);
                await ProcessAdminsAsync();
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
                    var old = Path.Combine(Directory, BootstrapFile);
                    if (File.Exists(old)) File.Delete(old);
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

        /// <summary>
        ///     admins.txt : chaque ligne « pseudo » ou « pseudo : mot de passe » est traitée puis remplacée
        ///     par un commentaire (succès ou erreur) ; le mot de passe est effacé du fichier.
        /// </summary>
        private static async Task ProcessAdminsAsync()
        {
            var path = Path.Combine(Directory, AdminsFile);
            if (!File.Exists(path))
            {
                File.WriteAllText(path, AdminsExample, new UTF8Encoding(false));
                return;
            }

            var stamp = File.GetLastWriteTimeUtc(path);
            if (stamp == _adminsWrite) return;
            var lines = File.ReadAllLines(path, Encoding.UTF8);
            var changed = false;
            for (var i = 0; i < lines.Length; i++)
            {
                var line = lines[i].Trim();
                if (line == "" || line.StartsWith("#")) continue;
                var sep = line.IndexOf(':');
                var username = (sep < 0 ? line : line.Substring(0, sep)).Trim();
                var password = sep < 0 ? "" : line.Substring(sep + 1).Trim();
                var error = await Accounts.MakeAdminAsync(username, password);
                lines[i] = error == null
                    ? $"# {username} — admin ✓ ({DateTime.Now:dd/MM/yyyy HH:mm})"
                    : $"# {username} — erreur : {error}";
                Logger.Log($"admins.txt : {lines[i].TrimStart('#', ' ')}", typeof(AdminFile), ErrorLevel.Info);
                changed = true;
            }

            if (changed)
            {
                File.WriteAllText(path, string.Join("\n", lines) + "\n", new UTF8Encoding(false));
                RequestRefresh();
            }

            _adminsWrite = File.GetLastWriteTimeUtc(path);
        }
    }
}
