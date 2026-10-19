using System;
using System.Collections.Generic;
using System.Linq;
using ClashRoyale.Files;
using ClashRoyale.Files.CsvLogic;
using ClashRoyale.Logic.Home.Chests.Items;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;
using Newtonsoft.Json;

namespace ClashRoyale.Logic.Home.Chests
{
    /// <summary>
    ///     Un emplacement de coffre : coffre gagné en combat, à déverrouiller puis ouvrir.
    /// </summary>
    public class ChestSlot
    {
        [JsonProperty("instance")] public int InstanceId { get; set; }
        [JsonProperty("slot")] public int Slot { get; set; }
        [JsonProperty("unlock_end")] public DateTime? UnlockEnd { get; set; }
        [JsonProperty("unlock_seconds")] public int UnlockSeconds { get; set; }
        // Valeur par défaut false : le sérialiseur omet les valeurs par défaut.
        [JsonProperty("new")] public bool IsNew { get; set; }

        [JsonIgnore] public bool IsUnlocking => UnlockEnd.HasValue && UnlockEnd > DateTime.UtcNow;
        [JsonIgnore] public bool IsReady => UnlockEnd.HasValue && UnlockEnd <= DateTime.UtcNow;
    }

    /// <summary>
    ///     Les 4 emplacements de coffres de l'accueil (cycle chest_order.csv « MainCycle »).
    /// </summary>
    public class ChestSlots : List<ChestSlot>
    {
        public const int Max = 4;

        [JsonIgnore] public Home Home { get; set; }

        /// <summary>
        ///     Coffre de victoire : le suivant du cycle, dans l'arène du joueur, si un emplacement est libre.
        /// </summary>
        public ChestSlot AddWinChest()
        {
            if (Count >= Max) return null;

            var order = Csv.Tables.Get(Csv.Files.ChestOrder).GetData<ChestOrder>("MainCycle");
            var cycle = order?.Chest?.Where(c => !string.IsNullOrEmpty(c)).ToArray() ?? new[] {"Silver"};
            var baseName = cycle[Home.ChestCycleIndex % cycle.Length];
            Home.ChestCycleIndex++;

            var chests = Csv.Tables.Get(Csv.Files.TreasureChests);
            var arena = Home.Arena.GetCurrentArenaData();
            var data = chests.GetData<TreasureChests>($"{baseName}_{arena?.ChestArena}") ??
                       chests.GetData<TreasureChests>(baseName);
            if (data == null) return null;

            var free = Enumerable.Range(0, Max).First(i => this.All(s => s.Slot != i));
            var slot = new ChestSlot {InstanceId = data.GetInstanceId(), Slot = free, IsNew = true};
            Add(slot);
            return slot;
        }

        public ChestSlot Get(int slot)
        {
            return this.FirstOrDefault(s => s.Slot == slot);
        }

        /// <summary>
        ///     Durée de déverrouillage (TimeTaken* du coffre de base) × réglage de progression.
        /// </summary>
        public static int UnlockSeconds(int instanceId)
        {
            var chests = Csv.Tables.Get(Csv.Files.TreasureChests);
            var data = chests.GetDataWithInstanceId<TreasureChests>(instanceId);
            if (data == null) return 0;
            var baseChest = string.IsNullOrEmpty(data.BaseChest) ? data : chests.GetData<TreasureChests>(data.BaseChest);
            var seconds = baseChest.TimeTakenDays * 86400 + baseChest.TimeTakenHours * 3600 +
                          baseChest.TimeTakenMinutes * 60 + baseChest.TimeTakenSeconds;
            return seconds * Resources.Configuration.Progression.UnlockTimePercent / 100;
        }

        public bool StartUnlock(int slotIndex)
        {
            var slot = Get(slotIndex);
            if (slot == null || slot.UnlockEnd.HasValue || this.Any(s => s.IsUnlocking)) return false;

            slot.UnlockSeconds = UnlockSeconds(slot.InstanceId);
            slot.UnlockEnd = DateTime.UtcNow.AddSeconds(slot.UnlockSeconds);
            slot.IsNew = false;
            return true;
        }

        /// <summary>
        ///     Coût en gemmes pour finir maintenant (globals SPEED_UP_DIAMOND_COST_*, interpolé).
        /// </summary>
        public static int SpeedUpCost(int seconds)
        {
            if (seconds <= 0) return 0;
            var globals = Csv.Tables.Get(Csv.Files.Globals);
            int Value(string key) => globals.GetData<Globals>(key)?.NumberValue ?? 0;
            var points = new[]
            {
                (60, Value("SPEED_UP_DIAMOND_COST_1_MIN")), (3600, Value("SPEED_UP_DIAMOND_COST_1_HOUR")),
                (86400, Value("SPEED_UP_DIAMOND_COST_24_HOURS")), (604800, Value("SPEED_UP_DIAMOND_COST_1_WEEK"))
            };
            if (seconds <= points[0].Item1) return Math.Max(1, points[0].Item2);
            for (var i = 1; i < points.Length; i++)
                if (seconds <= points[i].Item1)
                {
                    var (s0, c0) = points[i - 1];
                    var (s1, c1) = points[i];
                    return c0 + (int) ((long) (seconds - s0) * (c1 - c0) / (s1 - s0));
                }

            return points[points.Length - 1].Item2;
        }

        /// <summary>
        ///     Ouvre un coffre prêt (ou l'accélère avec des gemmes) et retire l'emplacement.
        /// </summary>
        public Chest Open(int slotIndex, bool speedUp)
        {
            var slot = Get(slotIndex);
            if (slot == null) return null;

            if (!slot.IsReady)
            {
                if (!speedUp) return null;
                var left = slot.UnlockEnd.HasValue
                    ? (int) (slot.UnlockEnd.Value - DateTime.UtcNow).TotalSeconds
                    : UnlockSeconds(slot.InstanceId);
                var cost = SpeedUpCost(left);
                if (Home.Diamonds < cost) return null;
                Home.Diamonds -= cost;
            }

            Remove(slot);
            return Home.Chests.BuyChest(slot.InstanceId, Chest.ChestType.Free);
        }

        /// <summary>
        ///     Encodage dans OwnHomeData : nombre, puis par emplacement : classe (19) / instance,
        ///     état (1 verrouillé, 8 en cours avec temps restant / total / horodatage, 2 prêt), nouveau, place.
        /// </summary>
        public void Encode(IByteBuffer packet)
        {
            packet.WriteVInt(Count);
            foreach (var slot in this)
            {
                packet.WriteVInt(19);
                packet.WriteVInt(slot.InstanceId);
                if (slot.IsUnlocking)
                {
                    packet.WriteVInt(8);
                    packet.WriteVInt((int) (slot.UnlockEnd.Value - DateTime.UtcNow).TotalSeconds);
                    packet.WriteVInt(slot.UnlockSeconds);
                    packet.WriteVInt((int) DateTimeOffset.UtcNow.ToUnixTimeSeconds());
                }
                else
                {
                    packet.WriteVInt(slot.IsReady ? 2 : 1);
                }

                packet.WriteBoolean(slot.IsNew);
                packet.WriteVInt(slot.Slot);
            }
        }
    }
}
