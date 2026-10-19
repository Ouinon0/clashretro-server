using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using ClashRoyale.Logic;
using ClashRoyale.Logic.Battle;
using ClashRoyale.Protocol.Messages.Server;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Messages.Client.Home
{
    /// <summary>
    ///     Message ClashRetro : combat amical par code. Action 0 = créer une salle (le serveur renvoie
    ///     un code de 6 caractères), 1 = rejoindre avec un code (le combat amical démarre), 2 = annuler.
    ///     Pas de trophées ni de statistiques ; le journal de combat le marque « friendly ».
    /// </summary>
    public class FriendlyRoomMessage : PiranhaMessage
    {
        private const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        private static readonly Dictionary<string, Player> Rooms = new Dictionary<string, Player>();

        public FriendlyRoomMessage(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Id = 14190;
        }

        public int Action { get; set; }
        public string Code { get; set; }

        public override void Decode()
        {
            Action = Reader.ReadVInt();
            Code = (Reader.ReadScString() ?? "").Trim().ToUpperInvariant();
        }

        public override async void Process()
        {
            var me = Device.Player;
            if (me == null) return;
            Player host = null;
            string code = null;
            var state = FriendlyRoomStateMessage.State.Cancelled;

            lock (Rooms)
            {
                RemoveRoomsOf(me);
                if (Action == 0 && me.Battle == null)
                {
                    code = NewCode();
                    Rooms[code] = me;
                    state = FriendlyRoomStateMessage.State.Created;
                }
                else if (Action == 1)
                {
                    if (Rooms.TryGetValue(Code, out host) && host != me && host.Device.IsConnected &&
                        host.Battle == null && me.Battle == null)
                    {
                        Rooms.Remove(Code);
                        code = Code;
                        state = FriendlyRoomStateMessage.State.Starting;
                    }
                    else
                    {
                        host = null;
                        state = FriendlyRoomStateMessage.State.NotFound;
                    }
                }
            }

            await new FriendlyRoomStateMessage(Device) {Status = state, Code = code ?? Code}.SendAsync();
            if (state != FriendlyRoomStateMessage.State.Starting) return;

            var battle = new LogicBattle(true, host.Home.Arena.CurrentArena + 1) {host, me};
            Resources.Battles.Add(battle);
            host.Battle = battle;
            me.Battle = battle;
            battle.Start();
        }

        private static void RemoveRoomsOf(Player player)
        {
            var stale = new List<string>();
            foreach (var (code, owner) in Rooms)
                if (owner == player || !owner.Device.IsConnected)
                    stale.Add(code);
            foreach (var code in stale) Rooms.Remove(code);
        }

        private static string NewCode()
        {
            var bytes = new byte[6];
            string code;
            do
            {
                RandomNumberGenerator.Fill(bytes);
                var chars = new char[6];
                for (var i = 0; i < 6; i++) chars[i] = Alphabet[bytes[i] % Alphabet.Length];
                code = new string(chars);
            } while (Rooms.ContainsKey(code));

            return code;
        }
    }
}
