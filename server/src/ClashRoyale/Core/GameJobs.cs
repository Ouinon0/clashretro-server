using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using ClashRoyale.Database;
using MySql.Data.MySqlClient;
using Newtonsoft.Json.Linq;
using SharpRaven.Data;

namespace ClashRoyale.Core
{
    /// <summary>
    ///     Tâches confiées par le portail (table game_jobs) : le serveur garde les joueurs en mémoire,
    ///     c'est donc lui qui supprime un joueur (effacement des données) ou lui donne or / gemmes.
    /// </summary>
    public static class GameJobs
    {
        private static Timer _timer;
        private static int _running;

        public static void Start()
        {
            _timer = new Timer(_ => Run(), null, TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(30));
        }

        private static async void Run()
        {
            if (Interlocked.Exchange(ref _running, 1) == 1) return;
            try
            {
                using (var connection = new MySqlConnection(AccessGate.ConnectionString))
                {
                    await connection.OpenAsync();
                    try
                    {
                        await LiveEvents.RefreshAsync(connection);
                    }
                    catch (MySqlException)
                    {
                        // table events absente (base pas encore mise à niveau par le portail)
                    }

                    var jobs = new List<(long id, string kind, long player, string payload)>();
                    using (var cmd = new MySqlCommand(
                        "SELECT id, kind, player_id, payload FROM game_jobs WHERE done_at IS NULL ORDER BY id LIMIT 50",
                        connection))
                    using (var reader = await cmd.ExecuteReaderAsync())
                        while (await reader.ReadAsync())
                            jobs.Add((reader.GetInt64(0), reader.GetString(1), reader.GetInt64(2),
                                reader.IsDBNull(3) ? null : reader.GetString(3)));

                    foreach (var job in jobs)
                    {
                        string result;
                        try
                        {
                            result = job.kind == "delete_player"
                                ? await DeletePlayer(job.player)
                                : await Grant(job.player, job.payload);
                        }
                        catch (Exception e)
                        {
                            result = "erreur : " + e.Message;
                        }

                        using (var done = new MySqlCommand(
                            "UPDATE game_jobs SET done_at = UTC_TIMESTAMP(), result = @r WHERE id = @id", connection))
                        {
                            done.Parameters.AddWithValue("@r", result.Length > 128 ? result.Substring(0, 128) : result);
                            done.Parameters.AddWithValue("@id", job.id);
                            await done.ExecuteNonQueryAsync();
                        }
                    }
                }
            }
            catch (Exception e)
            {
                Logger.Log($"GameJobs: {e.Message}", typeof(GameJobs), ErrorLevel.Warning);
            }
            finally
            {
                Interlocked.Exchange(ref _running, 0);
            }
        }

        /// <summary>
        ///     Retire le joueur de la mémoire sans le sauvegarder, puis l'efface de la base.
        /// </summary>
        private static async Task<string> DeletePlayer(long playerId)
        {
            Logic.Device device = null;
            lock (Resources.Players.SyncObject)
            {
                if (Resources.Players.TryGetValue(playerId, out var online))
                {
                    device = online.Device;
                    Resources.Players.Remove(playerId);
                }
            }

            Resources.ObjectCache.UncachePlayer(playerId);
            await PlayerDb.DeleteAsync(playerId);
            device?.Disconnect();
            return "supprimé";
        }

        private static async Task<string> Grant(long playerId, string payload)
        {
            var data = JObject.Parse(payload ?? "{}");
            var gold = Math.Max(0, data.Value<int?>("gold") ?? 0);
            var gems = Math.Max(0, data.Value<int?>("gems") ?? 0);
            var player = await Resources.Players.GetPlayerAsync(playerId);
            if (player == null) return "joueur introuvable";
            player.Home.Gold += gold;
            player.Home.Diamonds += gems;
            player.Save();
            return $"+{gold} or, +{gems} gemmes (visible à la prochaine connexion)";
        }
    }
}
