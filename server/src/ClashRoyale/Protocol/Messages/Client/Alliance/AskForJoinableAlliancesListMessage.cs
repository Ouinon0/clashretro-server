using System.Linq;
using System.Collections.Generic;
using ClashRoyale.Logic;
using ClashRoyale.Protocol.Messages.Server;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Messages.Client.Alliance
{
    public class AskForJoinableAlliancesListMessage : PiranhaMessage
    {
        public AskForJoinableAlliancesListMessage(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Id = 14303;
        }

        public override async void Process()
        {
            await new JoinableAllianceListMessage(Device)
            {
                // ClashRetro : clans du serveur qui ont de la place (classement mis à jour toutes les 20 s).
                Alliances = Resources.Leaderboard.GlobalAllianceRanking
                    .Where(a => a != null && a.Members.Count > 0 && a.Members.Count < 50)
                    .Take(50).ToList()
            }.SendAsync();
        }
    }
}