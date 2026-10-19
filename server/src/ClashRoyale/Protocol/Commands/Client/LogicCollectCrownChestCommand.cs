using System;
using ClashRoyale.Files;
using ClashRoyale.Files.CsvLogic;
using ClashRoyale.Logic;
using ClashRoyale.Logic.Home.Chests.Items;
using ClashRoyale.Protocol.Commands.Server;
using ClashRoyale.Protocol.Messages.Server;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Commands.Client
{
    public class LogicCollectCrownChestCommand : LogicCommand
    {
        public LogicCollectCrownChestCommand(Device device, IByteBuffer buffer) : base(device, buffer)
        {
        }

        public override async void Process()
        {
            var home = Device.Player.Home;
            var globals = Csv.Tables.Get(Csv.Files.Globals);
            var needed = globals.GetData<Globals>("CROWN_CHEST_CROWN_COUNT").NumberValue;

            // ClashRetro : 10 couronnes et délai écoulé, sinon rien.
            home.Reset();
            if (home.Crowns < needed || DateTime.UtcNow < home.CrownChestCooldown)
                return;

            await new AvailableServerCommand(Device)
            {
                Command = new ChestDataCommand(Device)
                {
                    Chest = home.Chests.BuyChest(home.Chests.ArenaChestId("Star"), Chest.ChestType.Crown)
                }
            }.SendAsync();

            home.Crowns -= needed;
            home.CrownChestCooldown = DateTime.UtcNow.AddHours(
                globals.GetData<Globals>("CROWN_CHEST_COOLDOWN_HOURS").NumberValue *
                Resources.Configuration.Progression.UnlockTimePercent / 100.0);
        }
    }
}