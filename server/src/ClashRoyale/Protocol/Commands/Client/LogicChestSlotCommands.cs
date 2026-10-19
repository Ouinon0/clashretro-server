using ClashRoyale.Logic;
using ClashRoyale.Protocol.Commands.Server;
using ClashRoyale.Protocol.Messages.Server;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Commands.Client
{
    /// <summary>
    ///     Commandes ClashRetro des emplacements de coffres. Champs : base (tick, 0), 2 réservés, emplacement.
    /// </summary>
    public abstract class LogicChestSlotCommand : LogicCommand
    {
        protected LogicChestSlotCommand(Device device, IByteBuffer buffer) : base(device, buffer)
        {
        }

        public int Slot { get; set; }

        public override void Decode()
        {
            base.Decode();
            Reader.ReadVInt();
            Reader.ReadVInt();
            Slot = Reader.ReadVInt();
        }

        protected async void SendChest(Logic.Home.Chests.Items.Chest chest)
        {
            if (chest == null)
            {
                Device.Disconnect();
                return;
            }

            await new AvailableServerCommand(Device)
            {
                Command = new ChestDataCommand(Device) {Chest = chest}
            }.SendAsync();
        }
    }

    /// <summary>590 : lance le déverrouillage d'un coffre.</summary>
    public class LogicStartUnlockChestCommand : LogicChestSlotCommand
    {
        public LogicStartUnlockChestCommand(Device device, IByteBuffer buffer) : base(device, buffer)
        {
        }

        public override void Process()
        {
            Device.Player.Home.ChestSlots.StartUnlock(Slot);
        }
    }

    /// <summary>591 : ouvre un coffre déverrouillé.</summary>
    public class LogicOpenChestSlotCommand : LogicChestSlotCommand
    {
        public LogicOpenChestSlotCommand(Device device, IByteBuffer buffer) : base(device, buffer)
        {
        }

        public override void Process()
        {
            SendChest(Device.Player.Home.ChestSlots.Open(Slot, false));
        }
    }

    /// <summary>592 : ouvre tout de suite en payant des gemmes.</summary>
    public class LogicSpeedUpChestCommand : LogicChestSlotCommand
    {
        public LogicSpeedUpChestCommand(Device device, IByteBuffer buffer) : base(device, buffer)
        {
        }

        public override void Process()
        {
            SendChest(Device.Player.Home.ChestSlots.Open(Slot, true));
        }
    }
}
