# Origine

Copie de https://github.com/retroroyale/ClashRoyale (GPL-3.0),
commit `a633b3c87ac1c9cc366244d23c778a354f83a6cb` (2021-10-29). `ClashRoyale.Management` (WinForms) retiré.

## Modifications ClashRetro

| Fichier | Changement |
|---|---|
| `ClashRoyale/Core/AccessGate.cs` | nouveau : invitations + appairage des appareils au login |
| `ClashRoyale/Core/Progression.cs` | nouveau : multiplicateurs de récompenses |
| `ClashRoyale/Core/Configuration.cs` | sections `progression` et `access` |
| `ClashRoyale/Protocol/Messages/Client/Login/LoginMessage.cs` | appel d'`AccessGate` avant/après création du joueur ; langue courte ne fait plus planter la connexion |
| `ClashRoyale/Logic/Home/Chests/Chests.cs` | coffres calculés depuis `treasure_chests.csv` × multiplicateur d'arène (avant : quantités en dur, boucle qui retirait un nombre aléatoire à chaque tour), coût en gemmes des coffres de boutique déduit comme côté client, puis `Progression` |
| `ClashRoyale/Protocol/Commands/Client/LogicCollect{Crown,Free}ChestCommand.cs` | coffre de l'arène du joueur (`Star_ArenaN`, `Free_ArenaN`) au lieu de la ligne 1 du CSV (« Newbie2 ») pour tous |
| `ClashRoyale/Protocol/Commands/Client/LogicBuyChestCommand.cs` | coffre inconnu ou gemmes insuffisantes → resynchronisation au lieu d'une exception |
| `ClashRoyale/Logic/Home/Shop/Shop.cs` | prix des cartes du jour comme le jeu d'origine (`PRICE_*` + achats × `PRICE_INCREASE_*`, limite respectée) ; avant, chaque achat coûtait le prix de base |
| `ClashRoyale/Files/CsvHelpers/DataTable.cs` | `GetDataWithInstanceId` : indice hors limites corrigé |
| `ClashRoyale/Logic/Home/Home.cs` | or/gemmes de départ configurables |
| `ClashRoyale/Logic/Sessions/Location.cs` | plus de requête à ip-api.com |
| `ClashRoyale/Core/SentryReport.cs` | plus aucun envoi Sentry |
