#!/bin/bash
set -euo pipefail
set -x
if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
  echo "found java executable in JAVA_HOME"
else
  export JAVA_HOME=/usr/lib/jvm/java-openjdk
fi
sudo -E bash -c 'echo $JAVA_HOME'
installpath=/usr/lib/ranger-plugins
ranger_server_fqdn=$1
default_domain=ec2.internal
hostname=`hostname -I | xargs`
hdfs_namenode_fqdn=$hostname
hive_server2_fqdn=$hostname
ranger_policybucket=s3://hxh-tokyo/ranger/policies
#Update repo/policies
sudo rm -rf $installpath
sudo mkdir -p $installpath
sudo chmod -R 777 $installpath
cd $installpath
aws s3 cp $ranger_policybucket . --recursive --exclude "*" --include "*.json" --region ap-northeast-1
sudo sed -i "s|emr_masternode|$hdfs_namenode_fqdn|g" ranger-presto-repo.json
curl -iv -u admin:1qazxsw2 -d @ranger-presto-repo.json -H "Content-Type: application/json" -X POST http://$ranger_server_fqdn:6080/service/public/v2/api/service/
curl -iv -u admin:1qazxsw2 -d @ranger-presto-policy-HueTest.json -H "Content-Type: application/json" -X POST http://$ranger_server_fqdn:6080/service/public/v2/api/policy/apply
