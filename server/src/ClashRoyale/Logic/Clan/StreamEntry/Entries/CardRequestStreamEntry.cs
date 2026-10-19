using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;
using Newtonsoft.Json;

namespace ClashRoyale.Logic.Clan.StreamEntry.Entries
{
    /// <summary>
    ///     ClashRetro : demande de cartes dans le fil du clan (type 30) — carte, cartes reçues, maximum.
    /// </summary>
    public class CardRequestStreamEntry : AllianceStreamEntry
    {
        public CardRequestStreamEntry()
        {
            StreamEntryType = 30;
        }

        [JsonProperty("card")] public int CardGlobalId { get; set; }
        [JsonProperty("given")] public int Given { get; set; }
        [JsonProperty("max")] public int Max { get; set; }

        public override void Encode(IByteBuffer packet)
        {
            base.Encode(packet);

            packet.WriteVInt(CardGlobalId);
            packet.WriteVInt(Given);
            packet.WriteVInt(Max);
        }
    }
}
