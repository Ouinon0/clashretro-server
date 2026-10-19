using ClashRoyale.Logic;
using ClashRoyale.Utilities.Netty;

namespace ClashRoyale.Protocol.Messages.Server
{
    /// <summary>
    ///     Message ClashRetro : état de la salle de combat amical (voir FriendlyRoomMessage).
    /// </summary>
    public class FriendlyRoomStateMessage : PiranhaMessage
    {
        public enum State
        {
            Created = 0,
            NotFound = 1,
            Cancelled = 2,
            Starting = 3
        }

        public FriendlyRoomStateMessage(Device device) : base(device)
        {
            Id = 24190;
        }

        public State Status { get; set; }
        public string Code { get; set; }

        public override void Encode()
        {
            Writer.WriteVInt((int) Status);
            Writer.WriteScString(Code ?? "");
        }
    }
}
