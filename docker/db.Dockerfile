# Base de données avec le schéma ClashRetro intégré (pour TrueNAS : rien à monter à part /data).
FROM mariadb:11.4
LABEL org.opencontainers.image.source=https://github.com/Ouinon0/clashretro-server
COPY db/init/ /docker-entrypoint-initdb.d/
# Données dans le volume unique /data (sous-dossier créé par l'utilisateur du conteneur).
RUN printf '[mariadb]\ndatadir=/data/mariadb\n' > /etc/mysql/conf.d/zz-clashretro.cnf
