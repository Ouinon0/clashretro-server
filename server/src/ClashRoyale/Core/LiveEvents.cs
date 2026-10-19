using System;
using System.Threading.Tasks;
using MySql.Data.MySqlClient;

namespace ClashRoyale.Core
{
    /// <summary>
    ///     Évènement en cours (table events, gérée depuis le portail) : multiplicateurs d'or et de cartes
    ///     appliqués aux coffres, annonce montrée par le client. Relu toutes les 30 s par GameJobs.
    /// </summary>
    public static class LiveEvents
    {
        public class Event
        {
            public long Id;
            public string Title;
            public string Message;
            public DateTime EndsAt;
            public double GoldMultiplier = 1;
            public double CardMultiplier = 1;
        }

        public static Event Current { get; private set; }

        public static double GoldMultiplier => Current?.GoldMultiplier ?? 1;
        public static double CardMultiplier => Current?.CardMultiplier ?? 1;

        public static async Task RefreshAsync(MySqlConnection connection)
        {
            using (var cmd = new MySqlCommand(
                "SELECT id, title, message, ends_at, gold_multiplier, card_multiplier FROM events " +
                "WHERE starts_at <= UTC_TIMESTAMP() AND ends_at > UTC_TIMESTAMP() ORDER BY starts_at DESC LIMIT 1",
                connection))
            using (var reader = await cmd.ExecuteReaderAsync())
            {
                if (!await reader.ReadAsync())
                {
                    Current = null;
                    return;
                }

                Current = new Event
                {
                    Id = reader.GetInt64(0),
                    Title = reader.GetString(1),
                    Message = reader.IsDBNull(2) ? "" : reader.GetString(2),
                    EndsAt = DateTime.SpecifyKind(reader.GetDateTime(3), DateTimeKind.Utc),
                    GoldMultiplier = Math.Clamp((double) reader.GetDecimal(4), 0.1, 100),
                    CardMultiplier = Math.Clamp((double) reader.GetDecimal(5), 0.1, 100)
                };
            }
        }
    }
}
