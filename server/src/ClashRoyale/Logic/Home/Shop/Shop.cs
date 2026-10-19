using System;
using System.Collections.Generic;
using System.Linq;
using ClashRoyale.Files;
using ClashRoyale.Files.CsvLogic;
using ClashRoyale.Logic.Home.Decks;
using ClashRoyale.Logic.Home.Decks.Items;
using ClashRoyale.Logic.Home.Shop.Items;
using ClashRoyale.Utilities.Netty;
using ClashRoyale.Utilities.Utils;
using DotNetty.Buffers;
using Newtonsoft.Json;

namespace ClashRoyale.Logic.Home.Shop
{
    public class Shop : List<ShopItem>
    {
        [JsonIgnore] public Home Home { get; set; }
        [JsonIgnore] public bool CanRefresh => Home.ShopDay != (int) DateTime.UtcNow.DayOfWeek;
        [JsonIgnore] public bool IsEpicSunday => DateTime.UtcNow.DayOfWeek == DayOfWeek.Sunday;

        public void Refresh()
        {
            Home.ShopDay = (int) DateTime.UtcNow.DayOfWeek;
            Clear();

            /*if (IsEpicSunday)
            {
                Add(RandomSpell(Card.Rarity.Rare));
                Add(RandomSpell(Card.Rarity.Epic));
                Add(RandomSpell(Card.Rarity.Legendary));
            }
            else*/
            {
                Add(RandomSpell(Card.Rarity.Common));
                Add(RandomSpell(Card.Rarity.Rare));
                Add(RandomSpell(Card.Rarity.Epic));
            }
        }

        public void Encode(IByteBuffer packet)
        {
            if (CanRefresh)
                Refresh();

            packet.WriteVInt((int) DateTime.UtcNow.DayOfWeek + 1); // Shop Day
            packet.WriteVInt((int) DateTime.UtcNow.DayOfWeek + 1); // Shop Seed
            packet.WriteVInt((int) DateTime.UtcNow.DayOfWeek + 1); // Shop Day Seen

            packet.WriteVInt(TimeUtils.GetSecondsUntilTomorrow * 20);
            packet.WriteVInt(TimeUtils.GetSecondsUntilTomorrow * 20);

            packet.WriteVInt(TimeUtils.CurrentUnixTimestamp);

            packet.WriteVInt(Count);

            for (var i = 0; i < Count; i++)
            {
                var item = this[i];
                item.ShopIndex = i;
                item.Encode(packet);
            }

            packet.WriteVInt(0); // Special Offers
        }

        public void BuyItem(int amount, int classId, int instanceId, int index)
        {
            if (this[index] is SpellShopItem item)
            {
                var globals = Csv.Tables.Get(Csv.Files.Globals);
                var rarity = new[] {"COMMON", "RARE", "EPIC", "LEGENDARY"}[Math.Clamp(item.Rarity, 0, 3)];
                var price = globals.GetData<Globals>("PRICE_" + rarity).NumberValue;
                var increase = globals.GetData<Globals>("PRICE_INCREASE_" + rarity).NumberValue;
                var limit = globals.GetData<Globals>("BUY_LIMIT_" + rarity).NumberValue;

                // Prix du jeu d'origine : chaque exemplaire déjà acheté augmente le prix du suivant.
                var count = amount != 1 ? limit - item.Bought : 1;
                if (count <= 0 || item.Bought + count > limit) return;

                var total = 0;
                for (var i = 0; i < count; i++)
                    total += Core.Progression.ShopPrice(price + (item.Bought + i) * increase);

                if (!Home.UseGold(total)) return;
                item.Bought += count;
                Home.Deck.Add(new Card(classId, instanceId, true, count));
            }
        }

        public SpellShopItem RandomSpell(Card.Rarity rarity)
        {
            var card = Cards.Random(rarity);

            return new SpellShopItem
            {
                ClassId = card.ClassId,
                InstanceId = card.InstanceId,
                Rarity = (int)card.CardRarity
            };
        }
    }
}