#!/bin/bash

ALFRESCO_HOST=192.168.33.10
export ALFRESCO_HOST # used by sed later

ALF_DOWNLOAD_URL=https://download.alfresco.com/cloudfront/release/community/SearchServices/2.0.1/alfresco-search-services-2.0.1.zip

LOGFILE=/vagrant/vagralf-search.log

IFS=$'\n'

DEBUG=1
COLOUR=1

ALF_ZIP=$(sed s/^.*[\/]// <<< $ALF_DOWNLOAD_URL)
ALF_DIR="/opt/"$(sed 's/-[[:digit:]].*$//' <<< $ALF_ZIP)
export ALF_DIR #used by sed later

function info() {
	  for LINE in $1; do
		    if [ $COLOUR -eq 0 ]; then
			      echo "[I] $LINE"|tee -a $LOGFILE
		    else
			      echo -e "\033[0;32m[I]\033[0;370m $LINE" && echo "[I] $LINE" >> $LOGFILE
		    fi
	  done
}

function debug() {
	  for LINE in $1; do
		    if [ $DEBUG -eq 1 ]; then
			      if [ $COLOUR -eq 0 ]; then
				        echo "[D] $LINE"|tee -a $LOGFILE
			      else
				        echo -e "\033[0;33m[D]\033[0;370m $LINE" && echo "[D] $LINE" >> $LOGFILE
			      fi
		    fi
	  done
}

function fatal() {
	  for LINE in $1; do
		    if [ $COLOUR -eq 0 ]; then
			      echo "[F] $LINE"|tee -a $LOFGILE
		    else
			      echo -e "\033[0;31m[F]\033[0;370m $LINE" && echo "[F] $LINE" >> $LOGFILE
		    fi
		    exit 1
	  done
}

# update list of available packages
info "updating list of available packages"
apt update &> $LOGFILE

# install required packages
info "installing required packages"
apt install mg unzip --assume-yes &>> $LOGFILE
wget https://download.java.net/java/GA/jdk15.0.2/0d1cfde4252546c6931946de8db48ee2/7/GPL/openjdk-15.0.2_linux-x64_bin.tar.gz
tar zxvf openjdk-15.0.2_linux-x64_bin.tar.gz -C /opt/
ln -s /opt/jdk-15.0.2 /opt/java

cd /vagrant
# download and unzip Alfresco search services
info "downloading Alfresco search services"
if [ ! -f $ALF_ZIP ]; then
    wget $ALF_DOWNLOAD_URL &>> $LOGFILE
fi
unzip -o $ALF_ZIP -d /opt &>> $LOGFILE

info "configuring Alfresco search services"
# create solr group and user
groupadd solr
useradd -g solr solr

# tuning configuration
sed -r 's#^\#(SOLR_PID_DIR=).*$#printf "%s%s%s" "\1" $ALF_DIR "/var/run";#e' $ALF_DIR/solr.in.sh | sudo tee $ALF_DIR/solr.in.sh &>> $LOGFILE
sed -r 's#^\#(SOLR_JAVA_HOME=).*$#printf "%s%s%s" "\1" "/opt/java";#e' $ALF_DIR/solr.in.sh | sudo tee $ALF_DIR/solr.in.sh &>> $LOGFILE
sed '0,/^#GC_TUNE=.*/s/^#\(GC_TUNE=\).*$/\1\"\"/' $ALF_DIR/solr.in.sh | sudo tee $ALF_DIR/solr.in.sh &>> $LOGFILE
sed '0,/^#GC_LOG_OPTS=.*/s/^#\(GC_LOG_OPTS=.*$\).*$/\1/' $ALF_DIR/solr.in.sh | sudo tee $ALF_DIR/solr.in.sh &>> $LOGFILE
cp $ALF_DIR/solr.in.sh /etc/default/

sed -r 's#^(alfresco.host=).*$#printf "%s%s" "\1" $ALFRESCO_HOST;#e' $ALF_DIR/solrhome/templates/rerank/conf/solrcore.properties | sudo tee $ALF_DIR/solrhome/templates/rerank/conf/solrcore.properties &>> $LOGFILE
sed 's/^\(alfresco.secureComms=\).*$/\1none/' $ALF_DIR/solrhome/templates/rerank/conf/solrcore.properties | sudo tee $ALF_DIR/solrhome/templates/rerank/conf/solrcore.properties &>> $LOGFILE 

mkdir $ALF_DIR/contentstore
mkdir -p $ALF_DIR/var/run

# set permission
chown -R solr:solr $ALF_DIR/solrhome
chown -R solr:solr $ALF_DIR/logs
chown -R solr:solr $ALF_DIR/contentstore
chown -R solr:solr $ALF_DIR/var

# init script
sed 's/^\(SOLR_INSTALL_DIR=\).*$/\1"\/opt\/alfresco-search-services\/solr"/' $ALF_DIR/solr/bin/init.d/solr | sudo tee /etc/init.d/solr &>> $LOGFILE
chmod 700 /etc/init.d/solr
update-rc.d solr defaults
update-rc.d solr enable

# Solr first start
info "starting Solr"
sudo -u solr $ALF_DIR/solr/bin/solr start -a "-Dcreate.alfresco.defaults=alfresco,archive"
