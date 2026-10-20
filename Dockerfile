# Serveur « Clash Royale : Modern Classic » : Godot 4.4 sans écran.
# Étape 1 : le projet Godot (godot/, sans aucun asset graphique ni sonore) est compilé en
# server.pck ; étape 2 : image légère avec Godot et ce paquet.
ARG GODOT=4.4.1-stable

FROM debian:bookworm-slim AS godot
ARG GODOT
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
    && curl -fsSL -o /tmp/godot.zip https://github.com/godotengine/godot/releases/download/${GODOT}/Godot_v${GODOT}_linux.x86_64.zip \
    && unzip /tmp/godot.zip -d /opt && mv /opt/Godot_v${GODOT}_linux.x86_64 /opt/godot && rm /tmp/godot.zip

FROM godot AS build
COPY godot /src
WORKDIR /src
ENV HOME=/tmp
RUN /opt/godot --headless --path /src --import >/dev/null 2>&1 || true \
    && mkdir -p build && /opt/godot --headless --path /src --export-pack "Serveur" build/server.pck \
    && test -s build/server.pck

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 tzdata tini \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data && chmod 777 /data
COPY --from=godot /opt/godot /opt/godot
COPY --from=build /src/build/server.pck /srv/server.pck
ENV HOME=/tmp CLASH_DATA=/data TZ=Europe/Paris
VOLUME /data
# 19340/udp : le jeu ; 19341/tcp : page d'accueil, invitations, téléchargement de l'appli, /admin.
EXPOSE 19340/udp 19341/tcp
HEALTHCHECK --interval=60s --timeout=5s CMD ["/bin/bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/19341 || exit 1"]
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/godot", "--headless", "--main-pack", "/srv/server.pck", "--", "--server"]
CMD ["--data=/data"]
