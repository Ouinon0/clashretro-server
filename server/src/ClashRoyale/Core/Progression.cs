using System;

namespace ClashRoyale.Core
{
    /// <summary>
    ///     Applique les réglages de progression (config.json → "progression") aux récompenses.
    /// </summary>
    public static class Progression
    {
        private static ProgressionSettings Settings => Resources.Configuration.Progression;

        public static int Cards(int count)
        {
            return Math.Max(1, (int) Math.Round(count * Settings.CardMultiplier * LiveEvents.CardMultiplier));
        }

        /// <summary>
        ///     Prix du magasin (cartes en or, coffres en gemmes) réduits par "shop_price_percent".
        /// </summary>
        public static int ShopPrice(int price)
        {
            return Math.Max(1, price * Math.Clamp(Settings.ShopPricePercent, 1, 1000) / 100);
        }

        public static int Gold(int gold)
        {
            return Math.Max(Settings.MinChestGold, (int) Math.Round(gold * Settings.GoldMultiplier * LiveEvents.GoldMultiplier));
        }
    }
}
