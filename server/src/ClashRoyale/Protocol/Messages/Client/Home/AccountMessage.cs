using ClashRoyale.Core;
using ClashRoyale.Logic;
using ClashRoyale.Protocol.Messages.Server;
using ClashRoyale.Utilities.Netty;
using DotNetty.Buffers;

namespace ClashRoyale.Protocol.Messages.Client.Home
{
    /// <summary>
    ///     Message ClashRetro : comptes dans le jeu (voir Core/Accounts). Action 0 = créer (pseudo, mot de
    ///     passe, code d'invitation), 1 = se connecter (pseudo, mot de passe), 2 = nouveau mot de passe
    ///     (pseudo, code de l'admin, nouveau mot de passe), 3 = mon compte et mes codes d'invitation,
    ///     4 = créer un compte pour le joueur déjà connecté (pseudo, mot de passe). Accepté avant la
    ///     connexion du joueur (sauf 3 et 4).
    /// </summary>
    public class AccountMessage : PiranhaMessage
    {
        public AccountMessage(Device device, IByteBuffer buffer) : base(device, buffer)
        {
            Id = 14650;
            RequiredState = Device.State.NotDefinied;
        }

        public int Action { get; set; }
        public string Username { get; set; }
        public string Password { get; set; }
        public string Extra { get; set; }

        public override void Decode()
        {
            Action = Reader.ReadVInt();
            Username = Reader.ReadScString() ?? "";
            Password = Reader.ReadScString() ?? "";
            Extra = Reader.ReadScString() ?? "";
        }

        public override async void Process()
        {
            Accounts.Result result;
            var player = Device.Player;
            switch (Action)
            {
                case 0:
                    result = await Accounts.CreateAsync(Username, Password, Extra);
                    break;
                case 1:
                    result = await Accounts.LoginAsync(Username, Password);
                    break;
                case 2:
                    result = await Accounts.ResetAsync(Username, Password, Extra);
                    break;
                case 3 when player != null:
                    result = await Accounts.InvitesAsync(player.Home.Id);
                    break;
                case 4 when player != null:
                    result = await Accounts.CreateAsync(Username, Password, "", player.Home.Id);
                    if (result.Ok) result = await Accounts.InvitesAsync(player.Home.Id);
                    break;
                default:
                    return;
            }

            await new AccountResultMessage(Device) {Action = Action, Result = result}.SendAsync();
        }
    }
}
