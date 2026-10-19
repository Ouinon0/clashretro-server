using ClashRoyale.Logic;
using ClashRoyale.Logic.Home.Decks.Items;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Commands.Server
{
    public class DoSpellCommand : LogicCommand
    {
        public DoSpellCommand(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Type = 1;
        }

        public int ClientTick { get; set; }
        public int Checksum { get; set; }
        public int SenderHighId { get; set; }
        public int SenderLowId { get; set; }
        public int SpellDeckIndex { get; set; }
        public int SpellIndex { get; set; }
        public int ClassId { get; set; }
        public int InstanceId { get; set; }
        public int TroopLevel { get; set; }
        public int X { get; set; }
        public int Y { get; set; }

        public override void Decode()
        {
            // Header
            {
                ClientTick = Reader.ReadVInt();
                Checksum = Reader.ReadVInt();

                SenderHighId = Reader.ReadVInt();
                SenderLowId = Reader.ReadVInt();
            }

            SpellDeckIndex = Reader.ReadVInt();

            ClassId = Reader.ReadVInt();
            InstanceId = Reader.ReadVInt();

            SpellIndex = Reader.ReadVInt();

            TroopLevel = Reader.ReadVInt();

            X = Reader.ReadVInt();
            Y = Reader.ReadVInt();
        }

        public override void Encode()
        {
            // Header
            {
                Data.WriteVInt(Type);

                Data.WriteVInt(ClientTick);
                Data.WriteVInt(Checksum);

                Data.WriteVInt(SenderHighId);
                Data.WriteVInt(SenderLowId);
            }

            Data.WriteVInt(SpellDeckIndex);

            Data.WriteVInt(ClassId);
            Data.WriteVInt(InstanceId);

            Data.WriteVInt(SpellIndex);
        }

        /// <summary>
        ///     Seuls les octets écrits sont relayés : le tableau entier du tampon (Array) contenait des zéros
        ///     de remplissage, et une deuxième pose dans le même battement était lue de travers (perdue).
        /// </summary>
        private static void Enqueue(System.Collections.Generic.Queue<byte[]> queue, IByteBuffer buffer)
        {
            if (queue == null) return;
            var bytes = new byte[buffer.ReadableBytes];
            buffer.GetBytes(buffer.ReaderIndex, bytes);
            lock (queue)
            {
                queue.Enqueue(bytes);
            }
        }

        public override void Process()
        {
            var battle = Device.Player.Battle;
            if (battle == null) return;
            // ClashRetro : le tick d'exécution est fixé par le serveur pour qu'aucun client ne l'ait déjà
            // dépassé quand le relais arrive (un client simule au plus 15 ticks au-delà du dernier tour
            // reçu ; on garde un tour de marge pour la gigue du minuteur). Les deux clients exécutent
            // donc la pose au même tick, même si l'émetteur est en retard.
            // ClashRetro 0.3 : le client fixe lui-même un tick d'exécution sûr (horloge du serveur + délai) et
            // programme sa pose sans attendre l'écho ; le serveur ne le repousse que s'il est déjà dépassé.
            ClientTick = System.Math.Max(ClientTick, battle.BattleTime * 10 + 4);
            battle.RecordPlacement(Device.Player.Home.Id, ClassId, InstanceId, TroopLevel, X, Y, ClientTick);

            Data = Unpooled.Buffer();
            Encode();
            var data = new byte[Data.ReadableBytes];
            Data.ReadBytes(data);

            var buffer = Unpooled.Buffer(9);
            {
                buffer.WriteBytes(data);

                buffer.WriteVInt(TroopLevel);

                buffer.WriteVInt(X);
                buffer.WriteVInt(Y);

                Enqueue(battle.GetOwnQueue(Device.Player.Home.Id), buffer);
            }

            var enemyBuffer = Unpooled.Buffer(9);
            {
                enemyBuffer.WriteBytes(data);

                enemyBuffer.WriteVInt(1); // IsAttack
                {
                    enemyBuffer.WriteVInt(Card.Id(ClassId, InstanceId));
                }

                enemyBuffer.WriteVInt(TroopLevel);

                enemyBuffer.WriteVInt(X);
                enemyBuffer.WriteVInt(Y);

                if (battle.Is2V2)
                {
                    var others = battle.GetOtherQueues(Device.Player.Home.Id);

                    foreach (var queue in others)
                    {
                        Enqueue(queue, enemyBuffer);
                    }
                }
                else 
                    Enqueue(battle.GetEnemyQueue(Device.Player.Home.Id), enemyBuffer);
            }

            //battle.Replay.AddCommand(Type, ClientTick - 20, ClientTick, SenderHighId, SenderLowId, ClassId * 1000000 + InstanceId, X, Y, SpellDeckIndex);
        }
    }
}