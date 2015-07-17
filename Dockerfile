FROM quay.io/optimizely/java:oracle-java8

# Update packages
RUN apt-get update

# MySQL (Metadata store)
RUN apt-get install -y mysql-server

# Supervisor
RUN apt-get install -y supervisor

# Maven
RUN wget -q -O - http://archive.apache.org/dist/maven/maven-3/3.2.5/binaries/apache-maven-3.2.5-bin.tar.gz | tar -xzf - -C /usr/local \
      && ln -s /usr/local/apache-maven-3.2.5 /usr/local/apache-maven \
      && ln -s /usr/local/apache-maven/bin/mvn /usr/local/bin/mvn

# Zookeeper
RUN wget -q -O - http://www.us.apache.org/dist/zookeeper/zookeeper-3.4.6/zookeeper-3.4.6.tar.gz | tar -xzf - -C /usr/local \
      && cp /usr/local/zookeeper-3.4.6/conf/zoo_sample.cfg /usr/local/zookeeper-3.4.6/conf/zoo.cfg \
      && ln -s /usr/local/zookeeper-3.4.6 /usr/local/zookeeper

# git
RUN apt-get install -y git

# Druid system user
RUN adduser --system --group --no-create-home druid \
      && mkdir -p /var/lib/druid \
      && chown druid:druid /var/lib/druid

# Pre-cache Druid dependencies (this step is optional, but can help speed up re-building the Docker image)
RUN mvn dependency:get -Dartifact=io.druid:druid-services:0.8.0

##################################################
# Druid (release tarball)
#
#ENV DRUID_VERSION 0.7.3
#RUN wget -q -O - http://static.druid.io/artifacts/releases/druid-$DRUID_VERSION-bin.tar.gz | tar -xzf - -C /usr/local
#RUN ln -s /usr/local/druid-$DRUID_VERSION /usr/local/druid

##################################################
# Druid (from source)
#
RUN mkdir -p /usr/local/druid/lib /usr/local/druid/repository

# whichever github owner (user or org name) you would like to build from
ENV GITHUB_OWNER optimizely
# whichever branch you would like to build
ENV DRUID_VERSION optimizely

# trigger rebuild only if branch changed
ADD https://api.github.com/repos/$GITHUB_OWNER/druid/git/refs/heads/$DRUID_VERSION druid-version.json
RUN git clone -q --branch $DRUID_VERSION --depth 1 https://github.com/$GITHUB_OWNER/druid.git /tmp/druid
WORKDIR /tmp/druid
# package and install Druid locally
RUN mvn -U -B clean install -DskipTests=true -Dmaven.javadoc.skip=true \
  && cp services/target/druid-services-*-selfcontained.jar /usr/local/druid/lib
##################################################

# pull dependencies for Druid extensions
RUN java -Ddruid.extensions.coordinates=[\"io.druid.extensions:druid-hdfs-storage\",\"io.druid.extensions:mysql-metadata-storage\"] \
      -Ddruid.extensions.localRepository=/usr/local/druid/repository \
      -Ddruid.extensions.remoteRepositories=[\"file:///root/.m2/repository/\",\"https://repo1.maven.org/maven2/\"] \
      -cp "/usr/local/druid/lib/*" \
      io.druid.cli.Main tools pull-deps

# Druid may need to touch some files in there
RUN chown -R druid:druid /usr/local/druid/repository

WORKDIR /

# Setup metadata store
RUN /etc/init.d/mysql start && mysql -u root -e "GRANT ALL ON druid.* TO 'druid'@'localhost' IDENTIFIED BY 'diurd'; CREATE database druid CHARACTER SET utf8;" && /etc/init.d/mysql stop

# Setup supervisord
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Add Yarn conf
ADD yarn-conf /etc/hadoop/conf/

# Clean up
RUN apt-get clean && rm -rf /tmp/* /var/tmp/*

# Expose ports:
# - 8081: HTTP (coordinator)
# - 8082: HTTP (broker)
# - 8083: HTTP (historical)
# - 8090: HTTP (overlord)
# - 3306: MySQL
# - 2181 2888 3888: ZooKeeper
EXPOSE 8081
EXPOSE 8082
EXPOSE 8083
EXPOSE 8090
EXPOSE 3306
EXPOSE 2181 2888 3888

WORKDIR /var/lib/druid
ENTRYPOINT export HOSTIP="$(resolveip -s $HOSTNAME)" && exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
