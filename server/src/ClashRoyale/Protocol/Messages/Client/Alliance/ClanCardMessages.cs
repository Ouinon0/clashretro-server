using System;
using System.Linq;
using ClashRoyale.Files;
using ClashRoyale.Files.CsvLogic;
using ClashRoyale.Logic;
using ClashRoyale.Logic.Clan.StreamEntry.Entries;
using ClashRoyale.Logic.Home.Decks.Items;
using ClashRoyale.Protocol.Messages.Server;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Messages.Client.Alliance
{
    /// <summary>
    ///     ClashRetro : demander une carte (commune ou rare, déjà trouvée) au clan. Capacité : RequestSize
    ///     de l'arène / DonateCapacity de la rareté ; une demande à la fois, délai réduit par
    ///     unlock_time_percent (8 h dans le jeu d'origine).
    /// </summary>
    public class ClanCardRequestMessage : PiranhaMessage
    {
        public ClanCardRequestMessage(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Id = 14191;
        }

        public int CardGlobalId { get; set; }

        public override void Decode()
        {
            CardGlobalId = Reader.ReadVInt();
        }

        public override async void Process()
        {
            var home = Device.Player.Home;
            if (!home.AllianceInfo.HasAlliance) return;
            var card = home.Deck.GetCard(CardGlobalId);
            if (card == null) return;
            var rarity = card.GetRarityData;
            if (rarity == null || (rarity.Name != "Common" && rarity.Name != "Rare")) return;

            var cooldown = TimeSpan.FromHours(8.0 * Resources.Configuration.Progression.UnlockTimePercent / 100.0);
            if (DateTime.UtcNow - home.LastCardRequest < cooldown) return;

            var alliance = await Resources.Alliances.GetAllianceAsync(home.AllianceInfo.Id);
            if (alliance == null) return;

            // Une seule demande ouverte : l'ancienne est retirée.
            foreach (var old in alliance.Stream.OfType<CardRequestStreamEntry>()
                .Where(e => e.SenderId == home.Id && !e.IsRemoved).ToList())
                alliance.RemoveEntry(old);

            var size = home.Arena.GetCurrentArenaData()?.RequestSize ?? 10;
            var entry = new CardRequestStreamEntry
            {
                CardGlobalId = CardGlobalId,
                Max = Math.Max(1, size / Math.Max(1, rarity.DonateCapacity))
            };
            entry.SetSender(Device.Player);
            home.LastCardRequest = DateTime.UtcNow;
            alliance.AddEntry(entry);
            alliance.Save();
            Device.Player.Save();
        }
    }

    /// <summary>
    ///     ClashRetro : donner une carte à une demande du clan. Le donneur perd un exemplaire et gagne l'or
    ///     et l'expérience de la rareté (DonateReward, DonateXP) ; le demandeur reçoit la carte.
    /// </summary>
    public class ClanDonateMessage : PiranhaMessage
    {
        public ClanDonateMessage(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Id = 14192;
        }

        public int EntryId { get; set; }

        public override void Decode()
        {
            EntryId = Reader.ReadVInt();
        }

        public override async void Process()
        {
            var donor = Device.Player;
            var home = donor.Home;
            if (!home.AllianceInfo.HasAlliance) return;
            var alliance = await Resources.Alliances.GetAllianceAsync(home.AllianceInfo.Id);
            var entry = alliance?.Stream.OfType<CardRequestStreamEntry>().FirstOrDefault(e => e.Id == EntryId);
            if (entry == null || entry.IsRemoved || entry.Given >= entry.Max || entry.SenderId == home.Id) return;

            var card = home.Deck.GetCard(entry.CardGlobalId);
            if (card == null || card.Count < 1) return;
            var requester = await Resources.Players.GetPlayerAsync(entry.SenderId);
            if (requester == null || requester.Home.AllianceInfo.Id != alliance.Id) return;

            lock (entry)
            {
                if (entry.Given >= entry.Max) return;
                entry.Given++;
            }

            card.Count--;
            var rarity = card.GetRarityData;
            home.Gold += rarity?.DonateReward ?? 0;
            home.AddExpPoints(rarity?.DonateXP ?? 0);

            var received = requester.Home.Deck.GetCard(entry.CardGlobalId);
            if (received != null) received.Count++;
            else requester.Home.Deck.Add(new Card(entry.CardGlobalId / 1000000, entry.CardGlobalId % 1000000, true, 1));

            donor.Save();
            requester.Save();
            alliance.UpdateEntry(entry);
            alliance.Save();

            if (requester.Device != null && requester.Device.IsConnected)
                await new CardsReceivedMessage(requester.Device)
                {
                    CardGlobalId = entry.CardGlobalId, Count = 1, From = home.Name
                }.SendAsync();
        }
    }
}
