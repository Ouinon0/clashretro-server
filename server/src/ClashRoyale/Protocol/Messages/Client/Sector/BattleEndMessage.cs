using ClashRoyale.Logic;
using ClashRoyale.Logic.Battle;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Messages.Client.Sector
{
    /// <summary>
    ///     Message ClashRetro : le client annonce la fin du combat tel qu'il l'a simulé
    ///     (ses couronnes, celles de l'adversaire, victoire / égalité / défaite, durée en ticks).
    /// </summary>
    public class BattleEndMessage : PiranhaMessage
    {
        public BattleEndMessage(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Id = 14199;
            RequiredState = Device.State.NotDefinied;
        }

        public LogicBattle.BattleReport Report { get; set; }

        public override void Decode()
        {
            Report = new LogicBattle.BattleReport
            {
                Crowns = Reader.ReadVInt(),
                EnemyCrowns = Reader.ReadVInt(),
                Outcome = Reader.ReadVInt(),
                Ticks = Reader.ReadVInt()
            };
        }

        public override void Process()
        {
            Device.Player?.Battle?.ReportEnd(Device.Player, Report);
        }
    }
}
