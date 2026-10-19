using System;
using System.IO;
using Newtonsoft.Json;

namespace ClashRoyale.Core
{
    public class Configuration
    {
        [JsonIgnore] public static JsonSerializerSettings JsonSettings = new JsonSerializerSettings
        {
            ObjectCreationHandling = ObjectCreationHandling.Reuse,
            MissingMemberHandling = MissingMemberHandling.Ignore,
            DefaultValueHandling = DefaultValueHandling.Ignore,
            NullValueHandling = NullValueHandling.Ignore,
            TypeNameHandling = TypeNameHandling.Auto,
            Formatting = Formatting.None
        };

        // Make sure to edit these on prod
        [JsonProperty("cluster_encryption_key")]
        public string ClusterKey = "15uvmi8qnyuj9tm53ipaavvytltm582yatecyjzb";

        [JsonProperty("cluster_encryption_nonce")]
        public string ClusterNonce = "nonce";

        [JsonProperty("cluster_server_port")] public int ClusterServerPort = 9876;

        [JsonProperty("encryption_key")] public string EncryptionKey = "fhsd6f86f67rt8fw78fw789we78r9789wer6re";

        [JsonProperty("mysql_database")] public string MySqlDatabase = "rrdb";
        [JsonProperty("mysql_password")] public string MySqlPassword = "";
        [JsonProperty("mysql_server")] public string MySqlServer = "127.0.0.1";
        [JsonProperty("mysql_user")] public string MySqlUserId = "root";

        [JsonProperty("patch_url")] public string PatchUrl = "";
        [JsonProperty("sentry_api")] public string SentryApiUrl = "";

        [JsonProperty("server_port")] public int ServerPort = 9339;
        [JsonProperty("update_url")] public string UpdateUrl = "https://github.com/retroroyale/ClashRoyale";
        [JsonProperty("use_content_patch")] public bool UseContentPatch;

        [JsonProperty("use_udp")] public bool UseUdp;

        [JsonProperty("progression")] public ProgressionSettings Progression = new ProgressionSettings();
        [JsonProperty("access")] public AccessSettings Access = new AccessSettings();
        [JsonProperty("battle_logs")] public BattleLogSettings BattleLogs = new BattleLogSettings();

        /// <summary>
        ///     Loads the configuration
        /// </summary>
        public void Initialize()
        {
            if (File.Exists("config.json"))
                try
                {
                    var config = JsonConvert.DeserializeObject<Configuration>(File.ReadAllText("config.json"));

                    EncryptionKey = config.EncryptionKey;
                    SentryApiUrl = config.SentryApiUrl;

                    MySqlUserId = config.MySqlUserId;
                    MySqlServer = config.MySqlServer;
                    MySqlPassword = config.MySqlPassword;
                    MySqlDatabase = config.MySqlDatabase;

                    PatchUrl = config.PatchUrl;
                    UseContentPatch = config.UseContentPatch;

                    ServerPort = config.ServerPort;
                    UpdateUrl = config.UpdateUrl;

                    UseUdp = config.UseUdp;
                    ClusterServerPort = config.ClusterServerPort;

                    ClusterKey = config.ClusterKey;
                    ClusterNonce = config.ClusterNonce;
                    Progression = config.Progression ?? new ProgressionSettings();
                    Access = config.Access ?? new AccessSettings();
                    BattleLogs = config.BattleLogs ?? new BattleLogSettings();
                }
                catch (Exception)
                {
                    Console.WriteLine("Couldn't load configuration.");
                    Console.ReadKey(true);
                    Environment.Exit(0);
                }
            else
                try
                {
                    Save();

                    Console.ForegroundColor = ConsoleColor.DarkGreen;
                    Console.WriteLine("Server configuration has been created. Restart the server now.");
                    Console.ReadKey();
                    Environment.Exit(0);
                }
                catch (Exception)
                {
                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    Console.WriteLine("Couldn't create config file.");
                    Console.ReadKey();
                    Environment.Exit(0);
                }
        }

        public void Save()
        {
            File.WriteAllText("config.json", JsonConvert.SerializeObject(this, Formatting.Indented));
        }
    }

    public class ProgressionSettings
    {
        [JsonProperty("starting_gold")] public int StartingGold = 5000;
        [JsonProperty("starting_gems")] public int StartingGems = 1000000;
        [JsonProperty("card_multiplier")] public double CardMultiplier = 3.0;
        [JsonProperty("gold_multiplier")] public double GoldMultiplier = 5.0;
        [JsonProperty("min_chest_gold")] public int MinChestGold = 100;
        // Durée de déverrouillage des coffres en % de la durée d'origine (100 = jeu d'origine).
        [JsonProperty("unlock_time_percent")] public int UnlockTimePercent = 100;
        [JsonProperty("chat_cheats")] public bool ChatCheats;
        [JsonProperty("shop_price_percent")] public int ShopPricePercent = 100;
    }

    public class AccessSettings
    {
        // false = n'importe quel client peut créer un compte (mode de test).
        [JsonProperty("require_invite")] public bool RequireInvite = true;
        // Sel du code d'appairage : à générer par instance (voir .env).
        [JsonProperty("pairing_secret")] public string PairingSecret = "";
    }

    public class BattleLogSettings
    {
        // Journal anonyme des combats pour l'équilibrage (decks, poses, résultat), sans donnée personnelle.
        [JsonProperty("enabled")] public bool Enabled = true;
        [JsonProperty("directory")] public string Directory = "logs/battles";
        [JsonProperty("retention_days")] public int RetentionDays = 90;
        [JsonProperty("salt")] public string Salt = "";
    }
}
