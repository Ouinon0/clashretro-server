using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;
using SharpRaven.Data;

namespace ClashRoyale.Core
{
    /// <summary>
    ///     Journal de combat pour l'équilibrage (une ligne JSON par combat, un fichier par jour).
    ///     Données minimales et anonymes : identifiants hachés avec un sel propre à l'instance,
    ///     ni pseudo, ni IP, ni appareil. Désactivable, avec une durée de conservation.
    /// </summary>
    public static class BattleLog
    {
        private static readonly object Lock = new object();

        private static BattleLogSettings Settings => Resources.Configuration.BattleLogs;

        public static string Anonymize(long playerId)
        {
            using (var sha = SHA256.Create())
            {
                var hash = sha.ComputeHash(Encoding.UTF8.GetBytes($"{Settings.Salt}:{playerId}"));
                return BitConverter.ToString(hash, 0, 8).Replace("-", "").ToLowerInvariant();
            }
        }

        public static void Write(object entry)
        {
            if (!Settings.Enabled) return;

            try
            {
                lock (Lock)
                {
                    Directory.CreateDirectory(Settings.Directory);
                    var file = Path.Combine(Settings.Directory, $"battles-{DateTime.UtcNow:yyyy-MM-dd}.jsonl");
                    File.AppendAllText(file, JsonConvert.SerializeObject(entry) + "\n");
                    Purge();
                }
            }
            catch (Exception exception)
            {
                Logger.Log($"BattleLog: {exception.Message}", typeof(BattleLog), ErrorLevel.Warning);
            }
        }

        /// <summary>
        ///     Supprime les journaux plus anciens que la durée de conservation.
        /// </summary>
        private static void Purge()
        {
            var limit = DateTime.UtcNow.AddDays(-Math.Max(1, Settings.RetentionDays));
            foreach (var file in Directory.GetFiles(Settings.Directory, "battles-*.jsonl")
                .Where(f => File.GetLastWriteTimeUtc(f) < limit))
                File.Delete(file);
        }
    }
}
