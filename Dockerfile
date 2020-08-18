FROM ubuntu:16.04


####################### Install apt-packages #########
###################################
RUN apt-get update &&\ 
    apt-get install -y vim openjdk-8-jdk-headless maven git


###################### Copy sources and scripts 

# copy scripts 
COPY docker/scripts /opt/scripts

# copy solr cores cores and config
COPY solr.core /opt/solr_home
COPY docker/scripts/solr.xml /opt/solr_home/

USER root

#########################################################################################
############################### begin solr ##############################################
#########################################################################################

# Override the solr download location with e.g.:
#   docker build -t mine --build-arg SOLR_DOWNLOAD_SERVER=http://www-eu.apache.org/dist/lucene/solr .
ARG SOLR_DOWNLOAD_SERVER

RUN apt-get update && \
  apt-get -y install acl dirmngr gnupg lsof procps wget && \
  rm -rf /var/lib/apt/lists/*

ENV SOLR_USER="solr" \
    SOLR_UID="8983" \
    SOLR_GROUP="solr" \
    SOLR_GID="8983" \
    SOLR_VERSION="6.6.6" \
    SOLR_URL="${SOLR_DOWNLOAD_SERVER:-https://archive.apache.org/dist/lucene/solr}/6.6.6/solr-6.6.6.tgz" \
    SOLR_SHA256="149ec1a7ee950867ab6257a1a96246df79ccda983983389dc639220f3447b6e8" \
    SOLR_KEYS="2085660D9C1FCCACC4A479A3BF160FF14992A24C" \
    PATH="/opt/solr/bin:/opt/docker/scripts:$PATH"

ENV GOSU_VERSION 1.11
ENV GOSU_KEY B42F6819007F00F88E364FD4036A9C25BF357DD4

ENV TINI_VERSION v0.18.0
ENV TINI_KEY 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7

RUN groupadd -r --gid "$SOLR_GID" "$SOLR_GROUP" && \
    useradd  -r --uid "$SOLR_UID" --gid "$SOLR_GID" "$SOLR_USER"

RUN set -e; \
  export GNUPGHOME="/tmp/gnupg_home" && \
  mkdir -p "$GNUPGHOME" && \
  chmod 700 "$GNUPGHOME" && \
  echo "disable-ipv6" >> "$GNUPGHOME/dirmngr.conf" && \
  for key in $SOLR_KEYS $GOSU_KEY $TINI_KEY; do \
    found=''; \
    for server in \
      ha.pool.sks-keyservers.net \
      hkp://keyserver.ubuntu.com:80 \
      hkp://p80.pool.sks-keyservers.net:80 \
      pgp.mit.edu \
    ; do \
      echo "  trying $server for $key"; \
      gpg --batch --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$key" && found=yes && break; \
      gpg --batch --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$key" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch $key from several disparate servers -- network issues?" && exit 1; \
  done; \
  exit 0

RUN set -e; \
  export GNUPGHOME="/tmp/gnupg_home" && \
  pkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" && \
  wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$pkgArch" && \
  wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$pkgArch.asc" && \
  gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu && \
  rm /usr/local/bin/gosu.asc && \
  chmod +x /usr/local/bin/gosu && \
  gosu nobody true && \
  wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-$pkgArch" && \
  wget -O /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-$pkgArch.asc" && \
  gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini; \
  rm /usr/local/bin/tini.asc && \
  chmod +x /usr/local/bin/tini && \
  tini --version && \
  echo "downloading $SOLR_URL" && \
  wget -nv "$SOLR_URL" -O "/opt/solr-$SOLR_VERSION.tgz" && \
  echo "downloading $SOLR_URL.asc" && \
  wget -nv "$SOLR_URL.asc" -O "/opt/solr-$SOLR_VERSION.tgz.asc" && \
  echo "$SOLR_SHA256 */opt/solr-$SOLR_VERSION.tgz" | sha256sum -c - && \
  (>&2 ls -l "/opt/solr-$SOLR_VERSION.tgz" "/opt/solr-$SOLR_VERSION.tgz.asc") && \
  gpg --batch --verify "/opt/solr-$SOLR_VERSION.tgz.asc" "/opt/solr-$SOLR_VERSION.tgz" && \
  tar -C /opt --extract --file "/opt/solr-$SOLR_VERSION.tgz" && \
  mv "/opt/solr-$SOLR_VERSION" /opt/solr && \
  rm "/opt/solr-$SOLR_VERSION.tgz"* && \
  rm -Rf /opt/solr/docs/ && \
  mkdir -p /opt/solr/server/solr/lib /docker-entrypoint-initdb.d /opt/scripts && \
  mkdir -p /opt/solr/server/logs /opt/solr_home && \
  sed -i -e "s/\"\$(whoami)\" == \"root\"/\$(id -u) == 0/" /opt/solr/bin/solr && \
  sed -i -e 's/lsof -PniTCP:/lsof -t -PniTCP:/' /opt/solr/bin/solr && \
  if [ -f "/opt/solr/contrib/prometheus-exporter/bin/solr-exporter" ]; then chmod 0755 "/opt/solr/contrib/prometheus-exporter/bin/solr-exporter"; fi && \
  chmod -R 0755 /opt/solr/server/scripts/cloud-scripts && \
  chown -R "$SOLR_USER:$SOLR_GROUP" /opt/solr && \
  #chown -R "$SOLR_USER:$SOLR_GROUP" /opt/mysolrhome && \
  { command -v gpgconf && gpgconf --kill all || :; } && \
  rm -r "$GNUPGHOME"

###################################################################################
############################### end solr ##########################################
###################################################################################

USER root

EXPOSE 8983


# start services and keep running
CMD /opt/scripts/init.sh && tail -f /dev/null
