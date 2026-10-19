using ClashRoyale.Utilities.Netty;
using System.Linq;
using System;
using System.Collections.Generic;
using ClashRoyale.Logic;
using ClashRoyale.Protocol.Messages.Server;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Messages.Client.Alliance
{
    public class SearchAlliancesMessage : PiranhaMessage
    {
        public SearchAlliancesMessage(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Id = 14324;
        }

        public string Query { get; set; }

        public override void Decode()
        {
            Query = (Reader.ReadScString() ?? "").Trim();
        }

        public override async void Process()
        {
            // ClashRetro : recherche par nom (sans filtres avancés) parmi les clans du serveur.
            var alliances = Resources.Leaderboard.GlobalAllianceRanking
                .Where(a => a != null && a.Members.Count > 0 &&
                            (Query.Length == 0 || (a.Name ?? "").IndexOf(Query, StringComparison.OrdinalIgnoreCase) >= 0))
                .Take(50).ToList();
            await new AllianceListMessage(Device)
            {
                Query = Query,
                Alliances = alliances
            }.SendAsync();
        }
    }
}