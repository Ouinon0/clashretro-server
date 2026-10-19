using System;
using System.Collections.Generic;
using System.Linq;
using ClashRoyale.Core;
using System.Timers;
using ClashRoyale.Core.Cluster;
using ClashRoyale.Extensions;
using ClashRoyale.Files;
using ClashRoyale.Files.CsvLogic;
using ClashRoyale.Protocol.Messages.Server;
using ClashRoyale.Utilities.Models.Battle.Replay;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;
using SharpRaven.Data;

namespace ClashRoyale.Logic.Battle
{
    public class LogicBattle : List<Player>
    {
        /// <summary>
        ///     1v1 Battle
        /// </summary>
        /// <param name="isFriendly"></param>
        /// <param name="arena"></param>
        public LogicBattle(bool isFriendly, int arena)
        {
            IsFriendly = isFriendly;
            Arena = arena;
            Location = Csv.Tables.Get(Csv.Files.Locations)
                           .GetData<Locations>(Csv.Tables.Get(Csv.Files.Arenas)
                               .GetDataWithInstanceId<Arenas>(Arena - 1).PvpLocation).GetInstanceId() +
                       1;
            Replay.Battle.Location = 15000000 + Location;

            BattleTimer.Elapsed += Tick;
        }

        /// <summary>
        ///     2v2 Battle
        /// </summary>
        /// <param name="isFriendly"></param>
        /// <param name="arena"></param>
        /// <param name="players"></param>
        public LogicBattle(bool isFriendly, int arena, IReadOnlyCollection<Player> players)
        {
            if (players.Count < 4)
            {
                Logger.Log("Not enough players to start a 2v2 battle.", GetType(), ErrorLevel.Error);
                return;
            }

            IsFriendly = isFriendly;
            Is2V2 = true;

            Arena = arena;
            Location = Csv.Tables.Get(Csv.Files.Locations)
                           .GetData<Locations>(Csv.Tables.Get(Csv.Files.Arenas)
                               .GetDataWithInstanceId<Arenas>(Arena - 1).TeamVsTeamLocation).GetInstanceId() +
                       1;

            Replay.Battle.Location = 15000000 + Location;

            AddRange(players);

            BattleTimer.Elapsed += Tick;
        }

        // Demi-secondes écoulées (le client ClashRetro cale sa simulation dessus : 1 demi-seconde = 10 ticks).
        public int BattleTime => (int) (DateTime.UtcNow.Subtract(StartTime).TotalMilliseconds / 500);
        public int BattleSeconds => BattleTime / 2;

        public bool IsRunning => BattleTimer.Enabled;
        public bool IsReady => Count >= (Is2V2 ? 4 : 2);

        public async void Start()
        {
            if (!IsReady) return;

            try
            {
                NodeInfo server = null;
                if (Resources.Configuration.UseUdp)
                    server = Resources.NodeManager.GetServer();

                //var second = false;
                _order = new List<Player>(this);
                foreach (var player in this)
                {
                    Commands.Add(player.Home.Id, new Queue<byte[]>());

                    // Add decks to replay
                    /*if (!second)
                    {
                        Replay.Battle.Avatar0 = player.Home.BattleAvatar;
                        Replay.Battle.Deck1 = player.Home.BattleDeck;
                        second = true;
                    }
                    else
                    {
                        Replay.Battle.Avatar1 = player.Home.BattleAvatar;
                        Replay.Battle.Deck0 = player.Home.BattleDeck;
                    }*/

                    if (server != null)
                        await new UdpConnectionInfoMessage(player.Device)
                        {
                            ServerPort = server.Port,
                            ServerHost = server.Ip,
                            SessionId = BattleId,
                            Nonce = server.Nonce,
                            Index = (byte)IndexOf(player)
                        }.SendAsync();

                    await new SectorStateMessage(player.Device)
                    {
                        Battle = this
                    }.SendAsync();
                }

                StartTime = DateTime.UtcNow;

                if (!Resources.Configuration.UseUdp || server == null)
                    BattleTimer.Start();
            }
            catch (Exception)
            {
                Logger.Log("Couldn't start battle", GetType(), ErrorLevel.Error);
            }
        }

        public void Encode(IByteBuffer packet)
        {
            #region SectorState

            const int towers = 6;

            packet.WriteVInt(Location); // LocationData

            packet.WriteVInt(Count); // PlayerCount
            packet.WriteVInt(0); // NpcData
            packet.WriteVInt(Arena); // ArenaData

            foreach (var player in this)
            {
                packet.WriteVInt(player.Home.HighId);
                packet.WriteVInt(player.Home.LowId);
                packet.WriteVInt(0);
            }

            // ConstantSizeIntArray
            {
                packet.WriteVInt(1);
                packet.WriteVInt(0);
                packet.WriteVInt(0);

                packet.WriteVInt(7);
                packet.WriteVInt(0);
                packet.WriteVInt(0);
            }

            packet.WriteBoolean(false); // IsReplay / Type?
            packet.WriteBoolean(false); // IsEndConditionMatched
            packet.WriteBoolean(false);

            packet.WriteBoolean(false); // IsNpc

            packet.WriteBoolean(false); // isBattleEndedWithTimeOut
            packet.WriteBoolean(false);

            packet.WriteBoolean(false); // hasPlayerFinishedNpcLevel
            packet.WriteBoolean(false);

            packet.WriteBoolean(false); // isInOvertime
            packet.WriteBoolean(false); // isTournamentMode

            packet.WriteVInt(0);

            packet.WriteVInt(towers);
            packet.WriteVInt(towers);

            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(1));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(1));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(1));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(1));

            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(0));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(0));

            // LogicGameObject::encodeComponent
            packet.WriteVInt(1);
            packet.WriteVInt(0);
            packet.WriteVInt(1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(1);

            for (var i = 0; i < towers; i++)
            {
                packet.WriteVInt(5);
                packet.WriteVInt(i);
            }

            var p = this[0].Home.ExpLevel - 1;
            var e = this[1].Home.ExpLevel - 1;

            // Player Right Princess Tower
            packet.WriteVInt(e);
            packet.WriteVInt(13);
            packet.WriteVInt(14500); // X
            packet.WriteVInt(25500); // Y
            packet.WriteHex("00007F00C07C0002000000000000");

            // Enemy Left Princess Tower
            packet.WriteVInt(p);
            packet.WriteVInt(13);
            packet.WriteVInt(3500); // X
            packet.WriteVInt(6500); // Y
            packet.WriteHex("00007F0080040001000000000000");

            // Player Left Princess Tower
            packet.WriteVInt(e);
            packet.WriteVInt(13);
            packet.WriteVInt(3500); // X
            packet.WriteVInt(25500); // Y
            packet.WriteHex("00007F00C07C0001000000000000");

            // Enemy Right Princess Tower
            packet.WriteVInt(p);
            packet.WriteVInt(13);
            packet.WriteVInt(14500); // X
            packet.WriteVInt(6500); // Y
            packet.WriteHex("00007F0080040002000000000000");

            // Enemy Crown Tower
            packet.WriteVInt(p);
            packet.WriteVInt(13);
            packet.WriteVInt(9000); // X
            packet.WriteVInt(3000); // Y
            packet.WriteHex("00007F0080040000000000000000");

            packet.WriteHex("000504077F7D7F0400050401007F7F0000");
            packet.WriteVInt(0); // Ms before regen mana
            packet.WriteVInt(6); // Mana Start 
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            packet.WriteHex("00007F7F7F7F7F7F7F7F00");

            // Player Crown Tower
            packet.WriteVInt(e);
            packet.WriteVInt(13);
            packet.WriteVInt(9000); // X
            packet.WriteVInt(29000); // Y
            packet.WriteHex("00007F00C07C0000000000000000");

            packet.WriteHex("00050401047D010400040706007F7F0000");
            packet.WriteVInt(0); // Ms before regen mana
            packet.WriteVInt(6); // Elexir Start Enemy
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            packet.WriteVInt(0);
            packet.WriteVInt(0);

            for (var index = 0; index < 8; index++)
                packet.WriteVInt(-1);

            for (var index = 0; index < 48; index++)
                packet.WriteVInt(0);

            // LogicHitpointComponent
            packet.WriteVInt(PrincessTowerHp[e]); // Enemy 
            packet.WriteVInt(0);
            packet.WriteVInt(PrincessTowerHp[p]); // Player
            packet.WriteVInt(0);
            packet.WriteVInt(PrincessTowerHp[e]); // Enemy
            packet.WriteVInt(0);
            packet.WriteVInt(PrincessTowerHp[p]); // Player
            packet.WriteVInt(0);
            packet.WriteVInt(KingTowerHp[p]); // Player
            packet.WriteVInt(0);
            packet.WriteVInt(KingTowerHp[e]); // Enemy
            packet.WriteVInt(0);

            // LogicCharacterBuffComponent
            for (var index = 0; index < towers; index++)
                packet.WriteHex("00000000000000A401A401");

            packet.WriteHex("FF01");
            this[0].Home.Deck.EncodeAttack(packet);

            packet.WriteVInt(0);

            packet.WriteHex("FE03");
            this[1].Home.Deck.EncodeAttack(packet);

            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(5);
            packet.WriteVInt(6);
            packet.WriteVInt(2);
            packet.WriteVInt(2);
            packet.WriteVInt(4);
            packet.WriteVInt(2);
            packet.WriteVInt(1);
            packet.WriteVInt(3);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(6);
            packet.WriteVInt(1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(9);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(12);

            packet.WriteHex("000000F69686FF0A002A002B");

            packet.WriteVInt(0);
            packet.WriteVInt(13);
            packet.WriteVInt(14500);
            packet.WriteVInt(25500);
            packet.WriteHex("00007F00C07C0002000000000000");

            packet.WriteVInt(0);
            packet.WriteVInt(13);
            packet.WriteVInt(3500);
            packet.WriteVInt(6500);
            packet.WriteHex("00007F0080040001000000000000");

            packet.WriteVInt(0);
            packet.WriteVInt(13);
            packet.WriteVInt(3500);
            packet.WriteVInt(25500);
            packet.WriteHex("00007F00C07C0001000000000000");

            packet.WriteVInt(0);
            packet.WriteVInt(13);
            packet.WriteVInt(14500);
            packet.WriteVInt(6500);
            packet.WriteHex("00007F0080040002000000000000");

            packet.WriteVInt(0);
            packet.WriteVInt(13);
            packet.WriteVInt(9000);
            packet.WriteVInt(3000);
            packet.WriteHex("00007F0080040000000000000000");

            packet.WriteVInt(0);
            packet.WriteVInt(5);
            packet.WriteVInt(1);
            packet.WriteVInt(0);

            packet.WriteHex("7F000000007F7F0000000100000000007F7F7F7F7F7F7F7F");
            packet.WriteVInt(0);

            packet.WriteVInt(0);
            packet.WriteVInt(13);
            packet.WriteVInt(9000);
            packet.WriteVInt(29000);
            packet.WriteHex("00007F00C07C0000000000000000");

            packet.WriteVInt(0);
            packet.WriteVInt(5);
            packet.WriteVInt(4);
            packet.WriteVInt(0);
            packet.WriteVInt(1);
            packet.WriteVInt(4);

            packet.WriteHex(
                "7F020203007F7F0000000500000000007F7F7F7F7F7F7F7F0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");

            packet.WriteVInt(0);
            packet.WriteVInt(1400);

            packet.WriteVInt(0);
            packet.WriteVInt(560);

            packet.WriteVInt(0);
            packet.WriteVInt(1400);

            packet.WriteVInt(0);
            packet.WriteVInt(560);

            packet.WriteVInt(0);
            packet.WriteVInt(960);

            packet.WriteVInt(0);
            packet.WriteVInt(2400);

            for (var index = 0; index < towers; index++)
                packet.WriteHex("00000000000000A401A401");

            #endregion 
        }

        public void EncodeDuo(IByteBuffer packet)
        {
            #region DuoSectorState

            const int towers = 10;

            packet.WriteVInt(Location); // LocationData

            packet.WriteVInt(Count); // PlayerCount
            packet.WriteVInt(0); // NpcData
            packet.WriteVInt(Arena); // ArenaData

            for (var i = 0; i < Count; i++)
            {
                packet.WriteVInt(this[i].Home.HighId);
                packet.WriteVInt(this[i].Home.LowId);
                packet.WriteVInt(0);
            }

            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            packet.WriteVInt(84);
            packet.WriteVInt(84);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            packet.WriteVInt(towers);
            packet.WriteVInt(towers);

            // KingTower
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(1));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(1));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(1));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(1));

            // PrincessTower
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(0));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(0));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(0));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(0));

            // KingTowerMiddle
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(16));
            packet.WriteData(Csv.Tables.Get(Csv.Files.Buildings).GetDataWithInstanceId<Buildings>(16));

            // LogicGameObject::encodeComponent
            packet.WriteVInt(1);
            packet.WriteVInt(2);
            packet.WriteVInt(3);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(1);
            packet.WriteVInt(2);
            packet.WriteVInt(3);
            packet.WriteVInt(1);
            packet.WriteVInt(0);

            for (var i = 0; i < towers; i++)
            {
                packet.WriteVInt(5);
                packet.WriteVInt(i);
            }

            packet.WriteVInt(7);
            packet.WriteVInt(13);
            packet.WriteVInt(14500);
            packet.WriteVInt(25500);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(2);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            packet.WriteVInt(0);

            packet.WriteVInt(7);
            packet.WriteVInt(13);
            packet.WriteVInt(3500);
            packet.WriteVInt(6500);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            var home1 = this[0];
            var home2 = this[2];

            var enemy1 = this[1];
            var enemy2 = this[3];

            packet.WriteVInt(0);
            packet.WriteVInt(7);
            packet.WriteVInt(13);
            packet.WriteVInt(3500);
            packet.WriteVInt(25500);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            packet.WriteVInt(0);
            packet.WriteVInt(7);
            packet.WriteVInt(13);
            packet.WriteVInt(14500);
            packet.WriteVInt(6500);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(2);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            // Home
            packet.WriteVInt(0);
            packet.WriteVInt(7);
            packet.WriteVInt(13);
            packet.WriteVInt(11000);
            packet.WriteVInt(3000);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(2);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(5);

            // Rotation
            packet.WriteByte(4);
            packet.WriteByte(0);
            packet.WriteByte(1);
            packet.WriteByte(1);
            packet.WriteByte(1);

            packet.WriteByte(4);
            for (var i = 4; i < 8; i++)
                packet.WriteByte(i);

            packet.WriteHex("007F7F00000005");

            packet.WriteHex(
                "00000000007F7F7F7F7F7F7F7F00");

            // Enemy
            packet.WriteVInt(7);
            packet.WriteVInt(13);
            packet.WriteVInt(11000);
            packet.WriteVInt(29000);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(2);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(5);

            // Rotation
            packet.WriteByte(4);
            packet.WriteByte(0);
            packet.WriteByte(1);
            packet.WriteByte(1);
            packet.WriteByte(1);

            packet.WriteByte(4);
            for (var i = 4; i < 8; i++)
                packet.WriteByte(i);

            packet.WriteHex("007F7F00000005");

            packet.WriteHex(
                "00000000007F7F7F7F7F7F7F7F00");

            // Home
            packet.WriteVInt(7);
            packet.WriteVInt(13);
            packet.WriteVInt(7000);
            packet.WriteVInt(3000);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(5);

            // Rotation
            packet.WriteByte(4);
            packet.WriteByte(0);
            packet.WriteByte(1);
            packet.WriteByte(1);
            packet.WriteByte(1);

            packet.WriteByte(4);
            for (var i = 4; i < 8; i++)
                packet.WriteByte(i);

            packet.WriteHex("007F7F00000005");

            packet.WriteHex(
                "00000000007F7F7F7F7F7F7F7F00");

            // Home
            packet.WriteVInt(7);
            packet.WriteVInt(13);
            packet.WriteVInt(7000);
            packet.WriteVInt(29000);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(5);

            // Rotation
            packet.WriteByte(4);
            packet.WriteByte(0);
            packet.WriteByte(1);
            packet.WriteByte(1);
            packet.WriteByte(1);

            packet.WriteByte(4);
            for (var i = 4; i < 8; i++)
                packet.WriteByte(i);

            packet.WriteHex("007F7F00000005");

            packet.WriteHex(
                "00000000007F7F7F7F7F7F7F7F00");

            packet.WriteVInt(0);
            packet.WriteVInt(9);
            packet.WriteVInt(9000);
            packet.WriteVInt(29000);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            packet.WriteVInt(0);
            packet.WriteVInt(9);
            packet.WriteVInt(9000);
            packet.WriteVInt(3000);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(-1);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);
            packet.WriteVInt(0);

            packet.WriteHex(
                "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");

            // LogicHitpointComponent
            packet.WriteVInt(2352);
            packet.WriteVInt(0);

            packet.WriteVInt(2352);
            packet.WriteVInt(0);

            packet.WriteVInt(2352);
            packet.WriteVInt(0);

            packet.WriteVInt(2352);
            packet.WriteVInt(0);

            packet.WriteVInt(4522);
            packet.WriteVInt(0);

            packet.WriteVInt(4522);
            packet.WriteVInt(0);

            packet.WriteVInt(4522);
            packet.WriteVInt(0);

            packet.WriteVInt(4522);
            packet.WriteVInt(0);

            for (var i = 0; i < towers; i++)
                packet.WriteHex("00000000000000A401A401");

            packet.WriteHex("FF01");
            home1.Home.Deck.EncodeAttack(packet);

            packet.WriteVInt(0);
            packet.WriteHex("FE01");
            home2.Home.Deck.EncodeAttack(packet);

            packet.WriteVInt(0);
            packet.WriteHex("FE03");
            enemy1.Home.Deck.EncodeAttack(packet);

            packet.WriteVInt(0);
            packet.WriteHex("FE03");
            enemy2.Home.Deck.EncodeAttack(packet);

            packet.WriteHex("00000506070802040202010300000000000000010200001800000C000000CCE9D7B507002A002B");

            #endregion 
        }

        /// <summary>
        ///     Stops the battle
        /// </summary>
        public void Stop()
        {
            if (!Resources.Configuration.UseUdp)
                BattleTimer.Stop();

            Resources.Battles.Remove(BattleId);

            //File.WriteAllText("replay.json", JsonConvert.SerializeObject(Replay));
        }

        /// <summary>
        ///     Checks wether the battle is over or we have to send sector heartbeat (TCP only)
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="args"></param>
        public async void Tick(object sender, ElapsedEventArgs args)
        {
            #region Tick

            try
            {
                foreach (var player in ToArray())
                    if (player.Device.IsConnected)
                    {
                        // Un joueur qui a déclaré la fin du combat attend le résultat de l'autre.
                        if (Reports.ContainsKey(player.Home.Id)) continue;

                        if (player.Device.SecondsSinceLastCommand > SilenceSeconds)
                        {
                            // ClashRetro : un joueur muet (appli fermée, réseau perdu) abandonne ;
                            // plus de victoire aléatoire comme dans le serveur d'origine.
                            Leave(player);
                        }
                        else
                        {
                            await new SectorHearbeatMessage(player.Device)
                            {
                                Turn = BattleTime,
                                Commands = GetOwnQueue(player.Home.Id)
                            }.SendAsync();
                        }
                    }
                    else
                    {
                        Leave(player);
                    }

                if (Count == 0)
                    Stop();
            }
            catch (Exception)
            {
                Logger.Log("BattleTick failed.", GetType(), ErrorLevel.Error);
            }

            #endregion
        }

        /// <summary>
        ///     Remove a player from the battle and stop it when it's empty
        /// </summary>
        /// <param name="player"></param>
        public class BattleReport
        {
            public int Crowns;
            public int EnemyCrowns;
            public int Outcome; // 1 victoire, 0 égalité, 2 défaite
            public int Ticks;
        }

        public const int ReportGraceSeconds = 8;
        public const int SilenceSeconds = 10;
        private List<Player> _order = new List<Player>();
        private readonly List<Player> _left = new List<Player>();

        /// <summary>
        ///     Un joueur quitte le combat (silence, déconnexion) : il est retiré, l'autre continue
        ///     contre ses tours ; le résultat sera déduit du rapport de celui qui reste.
        /// </summary>
        private void Leave(Player player)
        {
            if (!_left.Contains(player)) _left.Add(player);
            Remove(player);
            if (Count > 0 && Reports.Count >= Count && Reports.Count > 0)
                ReportEnd(this[0], Reports[this[0].Home.Id]);
        }

        private static BattleReport Mirror(BattleReport r)
        {
            return new BattleReport
            {
                Crowns = r.EnemyCrowns, EnemyCrowns = r.Crowns,
                Outcome = r.Outcome == 0 ? 0 : 3 - r.Outcome, Ticks = r.Ticks
            };
        }
        public Dictionary<long, BattleReport> Reports = new Dictionary<long, BattleReport>();
        public List<object> Placements = new List<object>();
        public Dictionary<long, List<int>> PlayedCards = new Dictionary<long, List<int>>();
        private bool _resolved;

        /// <summary>
        ///     Pose de carte relayée (pour le journal d'équilibrage).
        /// </summary>
        public void RecordPlacement(long playerId, int classId, int instanceId, int level, int x, int y, int tick)
        {
            lock (Placements)
            {
                if (!PlayedCards.TryGetValue(playerId, out var played))
                    PlayedCards[playerId] = played = new List<int>();
                played.Add(classId * 1000000 + instanceId);
                Placements.Add(new
                {
                    p = IndexOf(this.FirstOrDefault(pl => pl?.Home.Id == playerId)),
                    card = classId * 1000000 + instanceId, level, x, y, tick
                });
            }
        }

        /// <summary>
        ///     Fin annoncée par un client ClashRetro. Quand les deux rapports concordent, trophées,
        ///     couronnes et or sont attribués ; s'ils divergent, le combat est compté nul.
        /// </summary>
        public async void ReportEnd(Player player, BattleReport report)
        {
            lock (Reports)
            {
                Reports[player.Home.Id] = report;
                if (_resolved || Reports.Count < Count) return;
                _resolved = true;
            }

            // Joueurs dans l'ordre de départ (ceux qui sont partis compris) ; un abandon est déduit du
            // rapport de celui qui est resté.
            var a = _order[0];
            var b = _order[1];
            var ra = Reports.TryGetValue(a.Home.Id, out var reportA) ? reportA : Mirror(Reports[b.Home.Id]);
            var rb = Reports.TryGetValue(b.Home.Id, out var reportB) ? reportB : Mirror(ra);
            var agree = ra.Crowns == rb.EnemyCrowns && ra.EnemyCrowns == rb.Crowns &&
                        (ra.Outcome == 0 ? rb.Outcome == 0 : ra.Outcome + rb.Outcome == 3);
            var winner = !agree || ra.Outcome == 0 ? -1 : ra.Outcome == 1 ? 0 : 1;

            var trophies = new int[2];
            if (winner >= 0 && !IsFriendly)
            {
                var w = this[winner].Home.Arena.Trophies;
                var l = this[1 - winner].Home.Arena.Trophies;
                var delta = Math.Clamp(30 + (l - w) / 12, 20, 40);
                trophies[winner] = delta;
                trophies[1 - winner] = -Math.Min(delta, this[1 - winner].Home.Arena.Trophies);
            }

            for (var i = 0; i < 2; i++)
            {
                var participant = _order[i];
                var home = participant.Home;
                var r = i == 0 ? ra : rb;
                if (!IsFriendly)
                {
                    home.Stats.Record(winner == i, winner == 1 - i, r.Crowns,
                        PlayedCards.TryGetValue(home.Id, out var played) ? played : new List<int>());
                    home.AddCrowns(r.Crowns);
                    home.Arena.AddTrophies(trophies[i]);
                    home.Stats.HighestTrophies = Math.Max(home.Stats.HighestTrophies, home.Arena.Trophies);
                    if (winner == i)
                    {
                        home.Gold += Csv.Tables.Get(Csv.Files.Arenas)
                            .GetDataWithInstanceId<Arenas>(home.Arena.CurrentArena)?.BattleRewardGold ?? 0;
                        home.ChestSlots.AddWinChest();
                    }
                }

                if (_left.Contains(participant))
                {
                    participant.Save();
                    continue;
                }

                await new BattleResultMessage(participant.Device)
                {
                    TrophyReward = trophies[i],
                    OpponentTrophyReward = trophies[1 - i]
                }.SendAsync();
            }

            BattleLog.Write(new
            {
                time = DateTime.UtcNow.ToString("o"), arena = Arena, location = Location, friendly = IsFriendly,
                agree, winner, ticks = Math.Max(ra.Ticks, rb.Ticks),
                players = new[] {a, b}.Select((pl, i) => new
                {
                    id = BattleLog.Anonymize(pl.Home.Id), level = pl.Home.ExpLevel, trophies = pl.Home.Arena.Trophies,
                    crowns = i == 0 ? ra.Crowns : rb.Crowns,
                    deck = pl.Home.Deck.Take(8).Select(c => new {card = c.GlobalId, level = c.Level})
                }),
                placements = Placements
            });

            foreach (var player1 in ToArray())
                Remove(player1);
        }

        public new void Remove(Player player)
        {
            if (Count <= 1)
                Stop();

            player.Battle = null;

            if (Is2V2)
            {
                var index = FindIndex(x => x?.Home.Id == player.Home.Id);
                if (index <= -1) return;

                this[index] = null;
                Commands[player.Home.Id] = null;
            }
            else
                base.Remove(player);
        }

        /// <summary>
        ///     Stops the battle for a specific player (only UDP)
        /// </summary>
        public async void Stop(byte index)
        {
            #region Stop

            if (Count <= index) return;

            var player = this[index];

            if (player == null) return;

            var rnd = new Random();
            var trophies = IsFriendly || Is2V2 ? 0 : rnd.Next(15, 30);

            if (!IsFriendly)
            {
                player.Home.AddCrowns(3);
                player.Home.Arena.AddTrophies(trophies);
            }

            await new BattleResultMessage(player.Device)
            {
                TrophyReward = trophies
            }.SendAsync();

            player.Battle = null;
            this[index] = null;

            if (this.All(x => x == null)) Stop();

            #endregion
        }

        #region CommandStorage 

        public Queue<byte[]> GetEnemyQueue(long userId)
        {
            return Commands.FirstOrDefault(cmd => cmd.Key != userId).Value;
        }

        public Queue<byte[]> GetOwnQueue(long userId)
        {
            return Commands.FirstOrDefault(cmd => cmd.Key == userId).Value;
        }

        public List<Queue<byte[]>> GetOtherQueues(long userId)
        {
            var cmds = new List<Queue<byte[]>>();

            foreach (var (key, value) in Commands)
                if (key != userId && value != null)
                    cmds.Add(value);

            return cmds;
        }

        public Device GetEnemy(long userId)
        {
            return this.FirstOrDefault(p => p.Home.Id != userId)?.Device;
        }

        public Player GetTeammate(long userId)
        {
            var index = FindIndex(x => x?.Home.Id == userId);
            return this[index % 2 == 0 ? index == 0 ? 2 : 0 : index == 1 ? 3 : 1];
        }

        public List<Player> GetAllOthers(long userId)
        {
            return this.Where(x => x?.Home.Id != userId).ToList();
        }

        #endregion

        #region Objects 

        public Timer BattleTimer = new Timer(500);
        public LogicReplay Replay = new LogicReplay();
        public Dictionary<long, Queue<byte[]>> Commands = new Dictionary<long, Queue<byte[]>>();
        public long BattleId { get; set; }
        private DateTime StartTime { get; set; }
        public bool Is2V2 { get; set; }
        public bool IsFriendly { get; set; }
        public int Arena { get; set; }
        public int Location { get; set; }

        public static int[] KingTowerHp =
        {
            2400, 2568, 2736, 2904, 3096, 3312, 3528, 3768, 4008, 4392, 4824, 5304, 5832
        };

        public static int[] DuoKingTowerHp =
        {
            2880, 3082, 3284, 3485, 3716, 3975, 4234, 4522, 4810, 5271, 5789, 6365, 6999
        };

        public static int[] PrincessTowerHp =
        {
            1400, 1512, 1624, 1750, 1890, 2030, 2184, 2352, 2534, 2786, 3052, 3346, 3668
        };

        #endregion
    }
}