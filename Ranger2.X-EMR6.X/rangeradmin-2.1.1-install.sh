#!/bin/bash
set -euo pipefail
set -x
# sudo yum -y install java-1.8.0
# sudo yum -y remove java-1.7.0-openjdk
export JAVA_HOME=/usr/lib/jvm/jre-1.8.0-openjdk-1.8.0.282.b08-1.amzn2.0.1.x86_64

##### Define variables 设置变量，需要根据实际环境修改！！！
# sudo su
hostip=`hostname -I | xargs`
installpath=/usr/lib/ranger
mysql_jar=mysql-connector-java-5.1.39.jar
ranger_admin=ranger-2.1.1-SNAPSHOT-admin  
ranger_user_sync=ranger-2.1.1-SNAPSHOT-usersync
ldap_domain=ap-northeast-1.compute.internal                                 
ldap_server_url=ldap://ip-172-31-36-146.ap-northeast-1.compute.internal:389                   
ldap_base_dn=dc=ap-northeast-1,dc=compute,dc=internal                  
ldap_bind_user_dn=uid=hive,dc=ap-northeast-1,dc=compute,dc=internal   
ldap_bind_password=123456                                 
# ranger_s3bucket=https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger
ranger_s3bucket=s3://hxh-tokyo/ranger

##### 准备Ranger安装环境
yum install -y openldap openldap-clients openldap-servers

sudo mkdir -p $installpath
cd $installpath

# wget $ranger_s3bucket/$ranger_admin.tar.gz
# wget $ranger_s3bucket/$ranger_user_sync.tar.gz
# wget $ranger_s3bucket/$mysql_jar
# wget $ranger_s3bucket/solr_for_audit_setup.tar.gz

aws s3 cp $ranger_s3bucke/$ranger_admin.tar.gz .
aws s3 cp $ranger_s3bucke/$ranger_user_sync.tar.gz .
aws s3 cp $ranger_s3bucke/$mysql_jar .
aws s3 cp $ranger_s3bucke/solr_for_audit_setup.tar.gz .
 .
sudo tar xvpfz $ranger_admin.tar.gz -C $installpath
sudo tar xvpfz $ranger_user_sync.tar.gz -C $installpath
# cp $mysql_jar $installpath
# cd $installpath

##### 安装 MySQL，用作Ranger数据库
#yum -y install mysql-server
#service mysqld start
#chkconfig mysqld on
yum -y install mariadb-server
service mariadb start
chkconfig mariadb on
mysqladmin -u root password rangeradmin || true
mysql -u root -prangeradmin -e "CREATE USER 'rangeradmin'@'localhost' IDENTIFIED BY 'rangeradmin';" || true
mysql -u root -prangeradmin -e "create database ranger;" || true
mysql -u root -prangeradmin -e "GRANT ALL PRIVILEGES ON *.* TO 'rangeradmin'@'localhost' IDENTIFIED BY 'rangeradmin'" || true
mysql -u root -prangeradmin -e "FLUSH PRIVILEGES;" || true


##### 安装Ranger admin
sudo ln -s $ranger_admin ranger-admin
cd $installpath/ranger-admin
sudo cp install.properties install.properties_original
#sudo sed -i "s|#setup_mode=SeparateDBA|setup_mode=SeparateDBA|g" install.properties
sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=$installpath/$mysql_jar|g" install.properties
#sudo sed -i "s|db_host=.*|db_host=$db_host|g" install.properties
#sudo sed -i "s|db_root_user=.*|db_root_user=ranger|g" install.properties
sudo sed -i "s|db_root_password=.*|db_root_password=rangeradmin|g" install.properties
#sudo sed -i "s|db_user=.*|db_user=ranger|g" install.properties
sudo sed -i "s|db_password=.*|db_password=rangeradmin|g" install.properties
#sudo sed -i "s|db_name=.*|db_name=ranger_2_0|g" install.properties
sudo sed -i "s|policymgr_external_url=.*|policymgr_external_url=http://$hostip:6080|g" install.properties
sudo sed -i "s|rangerAdmin_password=.*|rangerAdmin_password=1qazxsw2|g" install.properties
sudo sed -i "s|rangerTagsync_password=.*|rangerTagsync_password=1qazxsw2|g" install.properties
sudo sed -i "s|rangerUsersync_password=.*|rangerUsersync_password=1qazxsw2|g" install.properties
sudo sed -i "s|keyadmin_password=.*|keyadmin_password=1qazxsw2|g" install.properties
#Update audit properties
sudo sed -i "s|audit_db_password=.*|audit_db_password=rangerlogger|g" install.properties
sudo sed -i "s|audit_store=.*|audit_store=solr|g" install.properties
sudo sed -i "s|audit_solr_urls=.*|audit_solr_urls=http://$hostip:8983/solr/ranger_audits|g" install.properties

### 为Ranger admin配置连接LDAP server的参数
sudo sed -i "s|authentication_method=.*|authentication_method=LDAP|g" install.properties
sudo sed -i "s|xa_ldap_url=.*|xa_ldap_url=$ldap_server_url|g" install.properties
sudo sed -i "s|xa_ldap_userDNpattern=.*|xa_ldap_userDNpattern=uid={0},$ldap_base_dn|g" install.properties
sudo sed -i "s|xa_ldap_groupSearchBase=.*|xa_ldap_groupSearchBase=$ldap_base_dn|g" install.properties
sudo sed -i "s|xa_ldap_groupSearchFilter=.*|xa_ldap_groupSearchFilter=(member=uid={0},$ldap_base_dn)|g" install.properties
sudo sed -i "s|xa_ldap_groupRoleAttribute=.*|xa_ldap_groupRoleAttribute=cn|g" install.properties
sudo sed -i "s|xa_ldap_base_dn=.*|xa_ldap_base_dn=$ldap_base_dn|g" install.properties
sudo sed -i "s|xa_ldap_bind_dn=.*|xa_ldap_bind_dn=$ldap_bind_user_dn|g" install.properties
sudo sed -i "s|xa_ldap_bind_password=.*|xa_ldap_bind_password=$ldap_bind_password|g" install.properties
sudo sed -i "s|xa_ldap_referral=.*|xa_ldap_referral=ignore|g" install.properties
sudo sed -i "s|xa_ldap_userSearchFilter=.*|xa_ldap_userSearchFilter=(uid={0})|g" install.properties
sudo chmod +x setup.sh
sudo ./setup.sh

##### 安装Ranger user sync组件
cd $installpath
sudo ln -s $ranger_user_sync ranger-usersync
cd $installpath/ranger-usersync
sudo cp install.properties install.properties_original
sudo sed -i "s|POLICY_MGR_URL =.*|POLICY_MGR_URL=http://$hostip:6080|g" install.properties
sudo sed -i "s|SYNC_SOURCE =.*|SYNC_SOURCE=ldap|g" install.properties
sudo sed -i "s|SYNC_LDAP_URL =.*|SYNC_LDAP_URL=$ldap_server_url|g" install.properties
sudo sed -i "s|SYNC_LDAP_BIND_DN =.*|SYNC_LDAP_BIND_DN=$ldap_bind_user_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_BIND_PASSWORD =.*|SYNC_LDAP_BIND_PASSWORD=123456|g" install.properties
sudo sed -i "s|SYNC_LDAP_SEARCH_BASE =.*|SYNC_LDAP_SEARCH_BASE=$ldap_base_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_SEARCH_BASE =.*|SYNC_LDAP_USER_SEARCH_BASE=$ldap_base_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_OBJECT_CLASS =.*|SYNC_LDAP_USER_OBJECT_CLASS=inetOrgPerson|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_SEARCH_FILTER =.*|SYNC_LDAP_USER_SEARCH_FILTER=objectclass=inetOrgPerson|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_NAME_ATTRIBUTE =.*|SYNC_LDAP_USER_NAME_ATTRIBUTE=uid|g" install.properties
sudo sed -i "s|SYNC_GROUP_SEARCH_ENABLED=.*|SYNC_GROUP_SEARCH_ENABLED=true|g" install.properties
sudo sed -i "s|SYNC_INTERVAL =.*|SYNC_INTERVAL=30|g" install.properties
sudo sed -i "s|rangerUsersync_password=.*|rangerUsersync_password=1qazxsw2|g" install.properties
sudo sed -i "s|SYNC_LDAP_DELTASYNC =.*|SYNC_LDAP_DELTASYNC=true|g" install.properties
sudo sed -i "s|logdir=logs|logdir=/var/log/ranger/usersync|g" install.properties
sudo chmod +x setup.sh
sudo -E ./setup.sh

###### 安装Ranger Solr组件，用于审计
## need to manually down solr from URL, and decompress to /opt/solr
cd $installpath
wget http://archive.apache.org/dist/lucene/solr/5.2.1/solr-5.2.1.tgz
sudo tar -xvf solr-5.2.1.tgz -C /opt/
sudo mv /opt/solr-5.2.1 /opt/solr
sudo tar -xvf solr_for_audit_setup.tar.gz
cd solr_for_audit_setup
sudo sed -i "s|#JAVA_HOME=.*|JAVA_HOME=/usr/lib/jvm/jre-1.8.0-openjdk-1.8.0.282.b08-1.amzn2.0.1.x86_64|g" install.properties
sudo sed -i "s|SOLR_INSTALL=.*|SOLR_INSTALLL=true|g" install.properties
sudo sed -i "s|SOLR_DOWNLOAD_URL=.*|SOLR_DOWNLOAD_URL=http://archive.apache.org/dist/lucene/solr/5.2.1/solr-5.2.1.tgz|g" install.properties
sudo sed -i "s|SOLR_HOST_URL=.*|SOLR_HOST_URL=http://$hostip:8983|g" install.properties
sudo sed -i "s|SOLR_RANGER_PORT=.*|SOLR_RANGER_PORT=8983|g" install.properties
sudo chmod +x setup.sh
sudo -E ./setup.sh


# #Change password
# Change rangerusersync user password in Ranger Admin Console, then Execute:
# sudo -E python ./updatepolicymgrpassword.sh

##### Start Ranger Admin 
sudo /usr/bin/ranger-admin stop
sudo /usr/bin/ranger-admin start

##### Start Ranger Usersync 
sudo /usr/bin/ranger-usersync stop
sudo /usr/bin/ranger-usersync start

##### Start Ranger Audit 
# /opt/solr/ranger_audit_server/scripts/stop_solr.sh
sudo /opt/solr/ranger_audit_server/scripts/start_solr.sh

# The default usersync runs every 1 hour (cannot be changed). This is way to force usersync
#sudo echo /usr/bin/ranger-usersync restart | at now + 5 minutes
#sudo echo /usr/bin/ranger-usersync restart | at now + 7 minutes
#sudo echo /usr/bin/ranger-usersync restart | at now + 10 minutes