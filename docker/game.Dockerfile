# Serveur de jeu (fork retroroyale, .NET Core 3.1).
FROM mcr.microsoft.com/dotnet/sdk:3.1 AS build
WORKDIR /src
COPY server/src/ .
RUN dotnet publish ClashRoyale/ClashRoyale.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/runtime:3.1
LABEL org.opencontainers.image.source=https://github.com/Ouinon0/clashretro-server
WORKDIR /app
COPY --from=build /app .
COPY --chmod=755 docker/game-entrypoint.sh /usr/local/bin/game-entrypoint.sh
# Logs/ (NLog) et logs/ restent inscriptibles si le conteneur tourne sous un autre uid (TrueNAS).
RUN useradd --system --uid 10001 --home /app game && mkdir -p /app/logs /app/Logs && chown -R game /app \
    && chmod 1777 /app/logs /app/Logs
USER game
EXPOSE 9339
ENTRYPOINT ["/usr/local/bin/game-entrypoint.sh"]
