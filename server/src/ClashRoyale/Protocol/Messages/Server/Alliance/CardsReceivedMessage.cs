using ClashRoyale.Logic;
using ClashRoyale.Utilities.Netty;

namespace ClashRoyale.Protocol.Messages.Server
{
    /// <summary>
    ///     ClashRetro : cartes reçues d'un membre du clan (carte, nombre, donneur).
    /// </summary>
    public class CardsReceivedMessage : PiranhaMessage
    {
        public CardsReceivedMessage(Device device) : base(device)
        {
            Id = 24193;
        }

        public int CardGlobalId { get; set; }
        public int Count { get; set; }
        public string From { get; set; }

        public override void Encode()
        {
            Writer.WriteVInt(CardGlobalId);
            Writer.WriteVInt(Count);
            Writer.WriteScString(From ?? "");
        }
    }
}
