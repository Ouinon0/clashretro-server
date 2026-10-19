using ClashRoyale.Core;
using ClashRoyale.Logic;
using ClashRoyale.Utilities.Netty;

namespace ClashRoyale.Protocol.Messages.Server
{
    /// <summary>
    ///     Message ClashRetro : réponse à AccountMessage. Action, succès, message d'erreur, joueur
    ///     (identifiant haut/bas, jeton) pour s'y connecter, pseudo du compte, codes d'invitation
    ///     (code, pseudo de l'invité ou vide).
    /// </summary>
    public class AccountResultMessage : PiranhaMessage
    {
        public AccountResultMessage(Device device) : base(device)
        {
            Id = 24650;
        }

        public int Action { get; set; }
        public Accounts.Result Result { get; set; }

        public override void Encode()
        {
            Writer.WriteVInt(Action);
            Writer.WriteVInt(Result.Ok ? 1 : 0);
            Writer.WriteScString(Result.Message ?? "");
            Writer.WriteVInt((int) (Result.PlayerId >> 32));
            Writer.WriteVInt((int) (Result.PlayerId & 0xFFFFFFFF));
            Writer.WriteScString(Result.Token ?? "");
            Writer.WriteScString(Result.Username ?? "");
            Writer.WriteVInt(Result.Invites.Count);
            foreach (var (code, usedBy) in Result.Invites)
            {
                Writer.WriteScString(code);
                Writer.WriteScString(usedBy ?? "");
            }
        }
    }
}
