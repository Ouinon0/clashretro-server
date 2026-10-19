using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json;

namespace ClashRoyale.Logic.Home
{
    /// <summary>
    ///     Statistiques du profil (ClashRetro) : victoires, défaites, victoires 3 couronnes, record de
    ///     trophées et cartes jouées (pour la carte favorite). Combats classés seulement.
    /// </summary>
    public class PlayerStats
    {
        [JsonProperty("games")] public int GamesPlayed { get; set; }
        [JsonProperty("wins")] public int Wins { get; set; }
        [JsonProperty("losses")] public int Losses { get; set; }
        [JsonProperty("three_crowns")] public int ThreeCrownWins { get; set; }
        [JsonProperty("highest_trophies")] public int HighestTrophies { get; set; }
        [JsonProperty("card_plays")] public Dictionary<int, int> CardPlays { get; set; } = new Dictionary<int, int>();

        public void Record(bool won, bool lost, int crowns, IEnumerable<int> cardsPlayed)
        {
            GamesPlayed++;
            if (won) Wins++;
            if (lost) Losses++;
            if (won && crowns >= 3) ThreeCrownWins++;
            foreach (var card in cardsPlayed)
                CardPlays[card] = CardPlays.TryGetValue(card, out var n) ? n + 1 : 1;
        }

        public int FavouriteCard(int fallback)
        {
            return CardPlays.Count == 0 ? fallback : CardPlays.OrderByDescending(kv => kv.Value).First().Key;
        }
    }
}
