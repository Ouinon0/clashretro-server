using System.Collections.Generic;
using ClashRoyale.Logic;
using ClashRoyale.Utilities.Netty;

namespace ClashRoyale.Protocol.Messages.Server
{
    public class SectorHearbeatMessage : PiranhaMessage
    {
        public SectorHearbeatMessage(Device device) : base(device)
        {
            Id = 21902;
        }

        public int Turn { get; set; }
        public Queue<byte[]> Commands { get; set; }

        public override void Encode()
        {
            Writer.WriteVInt(Turn);
            Writer.WriteVInt(0);

            // ClashRetro : la boucle d'origine (i < Count avec Dequeue) n'écrivait que la moitié des
            // commandes annoncées ; on vide la file d'un coup, sous verrou (remplie par un autre fil).
            byte[][] commands;
            if (Commands == null)
                commands = new byte[0][];
            else
                lock (Commands)
                {
                    commands = Commands.ToArray();
                    Commands.Clear();
                }

            Writer.WriteVInt(commands.Length);
            foreach (var command in commands) Writer.WriteBytes(command);
        }
    }
}