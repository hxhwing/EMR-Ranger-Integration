#set up after_provision_action.sh script to be executed after applications are provisioned. 
IS_MASTER=$(cat /mnt/var/lib/info/instance.json | jq -r ".isMaster" | grep "true" || true);

cd /tmp
if [ $IS_MASTER ]; then
	wget https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/install-hive-hdfs-ranger-plugin.sh;
	sudo chmod +x /tmp/install-hive-hdfs-ranger-plugin.sh;
	wget https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/Check-and-Install-Presto-Plugin.sh;
	sudo chmod +x /tmp/Check-and-Install-Presto-Plugin.sh;
	sudo sed 's/null &/null \&\& \/tmp\/install-hive-hdfs-ranger-plugin.sh 172.31.43.166 >> $STDOUT_LOG 2>> $STDERR_LOG \&\& \/tmp\/Check-and-Install-Presto-Plugin.sh 172.31.43.166 >> $STDOUT_LOG 2>> $STDERR_LOG \&\n/' /usr/share/aws/emr/node-provisioner/bin/provision-node > /tmp/provision-node.new;
	sudo cp /tmp/provision-node.new /usr/share/aws/emr/node-provisioner/bin/provision-node;

fi;

exit 0