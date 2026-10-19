using ClashRoyale.Logic;
using ClashRoyale.Protocol.Commands.Server;
using ClashRoyale.Protocol.Messages.Server;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Messages.Client.Home
{
    public class ChangeAvatarNameMessage : PiranhaMessage
    {
        public ChangeAvatarNameMessage(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Id = 10212;
        }

        public string Name { get; set; }

        public override void Decode()
        {
            Name = Reader.ReadScString();
        }

        public override async void Process()
        {
            // ClashRetro : nom nettoyé, changements illimités (serveur entre amis).
            Name = Name?.Trim();
            if (string.IsNullOrEmpty(Name)) return;
            if (Name.Length < 2 || Name.Length > 15) return;
            foreach (var c in Name)
                if (char.IsControl(c) || c == '<' || c == '>') return;

            var home = Device.Player.Home;

            home.Name = Name;

            var info = Device.Player.Home.AllianceInfo;

            if (info.HasAlliance)
            {
                var alliance = await Resources.Alliances.GetAllianceAsync(info.Id);

                alliance.GetMember(home.Id).Name = Name;

                alliance.Save();
            }

            await new AvailableServerCommand(Device)
            {
                Command = new LogicChangeNameCommand(Device)
                {
                    NameSet = home.NameSet
                }
            }.SendAsync();

            if (home.NameSet < 2) home.NameSet++;

            Device.Player.Save();
        }
    }
}