using System;
using ClashRoyale.Logic;
using ClashRoyale.Logic.Home.Chests.Items;
using ClashRoyale.Protocol.Commands.Server;
using ClashRoyale.Protocol.Messages.Server;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Commands.Client
{
    public class LogicCollectFreeChestCommand : LogicCommand
    {
        public LogicCollectFreeChestCommand(Device device, IByteBuffer buffer) : base(device, buffer)
        {
        }

        public override async void Process()
        {
            var home = Device.Player.Home;

            // ClashRetro : aucun coffre si aucun n'est disponible (l'original en donnait un).
            if (!home.IsFirstFreeChestAvailable())
                return;

            if (home.IsSecondFreeChestAvailable())
                home.FreeChestTime = DateTime.UtcNow - Logic.Home.Home.FreeChestInterval;
            else
                home.FreeChestTime += Logic.Home.Home.FreeChestInterval;

            await new AvailableServerCommand(Device)
            {
                Command = new ChestDataCommand(Device)
                {
                    Chest = Device.Player.Home.Chests.BuyChest(Device.Player.Home.Chests.ArenaChestId("Free"), Chest.ChestType.Free)
                }
            }.SendAsync();
        }
    }
}