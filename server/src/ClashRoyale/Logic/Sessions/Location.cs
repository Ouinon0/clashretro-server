using System;
using System.Net.Http;
using System.Threading.Tasks;
using Newtonsoft.Json;
using SharpRaven.Data;

namespace ClashRoyale.Logic.Sessions
{
    public class Location
    {
        [JsonProperty("country")] public string CountryName { get; set; }
        [JsonProperty("countryCode")] public string CountryCode { get; set; }
        [JsonProperty("city")] public string City { get; set; }

        // Pas de géolocalisation externe : aucune IP joueur ne quitte le serveur.
        public static Task<Location> GetByIpAsync(string ip)
        {
            return Task.FromResult<Location>(null);
        }
    }
}