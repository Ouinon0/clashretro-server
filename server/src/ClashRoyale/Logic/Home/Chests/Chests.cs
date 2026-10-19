using System;
using System.Collections.Generic;
using ClashRoyale.Core;
using ClashRoyale.Files;
using ClashRoyale.Files.CsvLogic;
using ClashRoyale.Logic.Home.Chests.Items;
using ClashRoyale.Logic.Home.Decks;
using ClashRoyale.Logic.Home.Decks.Items;
using Newtonsoft.Json;

namespace ClashRoyale.Logic.Home.Chests
{
    public class Chests
    {
        [JsonIgnore] public Home Home { get; set; }

        /// <summary>
        ///     Ouvre un coffre selon treasure_chests.csv (cartes, raretés, or) et le multiplicateur
        ///     de l'arène, comme le jeu d'origine, puis applique les réglages de progression.
        /// </summary>
        public Chest BuyChest(int instanceId, Chest.ChestType type)
        {
            var chests = Csv.Tables.Get(Csv.Files.TreasureChests);
            var mainchest = chests.GetDataWithInstanceId<TreasureChests>(instanceId);
            if (mainchest == null) return null;

            var baseChest = string.IsNullOrEmpty(mainchest.BaseChest)
                ? mainchest
                : chests.GetData<TreasureChests>(mainchest.BaseChest) ?? mainchest;
            var arena = Home.Arena.GetCurrentArenaData();
            var rewardMultiplier = arena?.ChestRewardMultiplier > 0 ? arena.ChestRewardMultiplier : 100;
            var chestArenas = Home.Arena.GetChestArenaNames();

            var chest = new Chest
            {
                ChestId = instanceId,
                IsDraft = mainchest.DraftChest,
                Type = type
            };

            if (type == Chest.ChestType.Shop)
            {
                var priceMultiplier = arena?.ChestShopPriceMultiplier > 0 ? arena.ChestShopPriceMultiplier : 100;
                var price = Core.Progression.ShopPrice(RoundPrice(baseChest.ShopPriceWithoutSpeedUp * priceMultiplier / 100));
                if (price > Home.Diamonds) return null;
                Home.Diamonds -= price;
            }

            var baseCards = Math.Max(1, baseChest.RandomSpells * rewardMultiplier / 100);
            var total = Progression.Cards(baseCards);
            var stacks = Math.Max(1, baseChest.DifferentSpells);

            var legendaries = Roll(total, baseChest.LegendaryChance);
            var epics = Roll(total, baseChest.EpicChance);
            var rares = Roll(total, baseChest.RareChance);
            var commons = Math.Max(0, total - legendaries - epics - rares);

            // Un paquet par légendaire et un pour les épiques ; communes et rares se partagent le reste.
            var free = Math.Max(2, stacks - legendaries - (epics > 0 ? 1 : 0));
            AddCards(chest, Card.Rarity.Legendary, legendaries, legendaries, chestArenas);
            AddCards(chest, Card.Rarity.Epic, epics, 1, chestArenas);
            AddCards(chest, Card.Rarity.Rare, rares, Math.Max(1, free / 3), chestArenas);
            AddCards(chest, Card.Rarity.Common, commons, Math.Max(1, free - free / 3), chestArenas);

            var minGold = Math.Max(0, baseChest.MinGoldPerCard);
            var maxGold = Math.Max(minGold, baseChest.MaxGoldPerCard);
            chest.Gold = Progression.Gold(baseCards * Random.Next(minGold, maxGold + 1));
            if (type == Chest.ChestType.Crown) chest.Gems = Random.Next(2, 11);

            Home.Gold += chest.Gold;
            Home.Diamonds += chest.Gems;

            return chest;
        }

        /// <summary>
        ///     Instance du coffre « {base}_{arène} » pour l'arène actuelle (Free, Star, Silver…).
        /// </summary>
        public int ArenaChestId(string baseName)
        {
            var chests = Csv.Tables.Get(Csv.Files.TreasureChests);
            var arena = Home.Arena.GetCurrentArenaData();
            var data = (arena != null ? chests.GetData<TreasureChests>($"{baseName}_{arena.ChestArena}") : null)
                       ?? chests.GetData<TreasureChests>(baseName);
            return data?.GetInstanceId() ?? 1;
        }

        private static readonly Random Random = new Random();

        /// <summary>
        ///     total / chance cartes, la partie fractionnaire devenant une probabilité.
        /// </summary>
        private static int Roll(int total, int chance)
        {
            if (chance <= 0) return 0;
            var expected = (double) total / chance;
            var count = (int) expected;
            if (Random.NextDouble() < expected - count) count++;
            return count;
        }

        private void AddCards(Chest chest, Card.Rarity rarity, int count, int stacks, List<string> chestArenas)
        {
            stacks = Math.Min(stacks, count);
            for (var i = 0; i < stacks; i++)
            {
                var amount = count / stacks + (i < count % stacks ? 1 : 0);
                var card = Cards.RandomByArena(rarity, chestArenas);
                if (card == null || amount <= 0) continue;

                card.Count = amount;
                card.IsNew = true;
                chest.Add(card);
                Home.Deck.Add(card);
            }
        }

        /// <summary>
        ///     by nameless
        /// </summary>
        /// <param name="price"></param>
        /// <returns></returns>
        private int RoundPrice(int price)
        {
            if (price > 500)
                return 100 * ((price + 50) / 100);
            if (price > 100)
                return 10 * ((price + 5) / 10);
            if (price > 20)
                return 5 * ((price + 3) / 5);

            return price;
        }
    }
}