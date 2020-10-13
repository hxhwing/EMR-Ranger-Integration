##Check if local server is Presto server or not
host=$(hostname -f)
PrestoURI=$(echo https://$host:8446)
grep $PrestoURI /etc/presto/conf/config.properties
Presto_Installed=$(echo $?)

ranger_ip=$1

cd /tmp
if [ "$Presto_Installed" -eq "0" ]; then
	wget https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/install-presto-ranger-plugin.sh;
	sudo chmod +x /tmp/install-presto-ranger-plugin.sh;
	sudo -E bash /tmp/install-presto-ranger-plugin.sh $ranger_ip;
fi;

exit 0