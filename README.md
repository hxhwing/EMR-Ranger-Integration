
# EMR 5.30集成Apache Ranger 2.x

## Table of Contents
========================
 * [说明](#说明)
  * [一. 安装OpenLDAP](#一-安装OpenLDAP)
  * [二. Build Ranger安装包](#二-Build-Ranger安装包)
  * [三. 安装 Ranger Server](#三-安装-Ranger-Server)
  * [四. 启动EMR集群](#四-启动EMR集群)
  * [五. 为EMR Master安装Ranger Plugin](#五-为EMR-Master安装Ranger-Plugin)
    + [5.1 准备安装包](#51-准备安装包)
    + [5.2 安装 Hive Plugin](#52-安装-Hive-Plugin)
    + [5.3 安装 Presto Plugin](#53-安装-Presto-Plugin)
  * [六. 配置 Ranger 授权策略](#六-配置-Ranger-授权策略)
    + [6.1 加载HDFS和Hive策略](#61-加载HDFS和Hive策略)
    + [6.2 加载Presto策略](#62-加载Presto策略)
  * [七. 验证Ranger权限控制](#七-验证Ranger权限控制)
    + [登录Ranger Admin UI查看Resource Access policy](#登录Ranger-Admin-UI查看Resource-Access-policy)
    + [登录Hue UI验证Ranger策略](#登录Hue-UI验证Ranger策略)
    + [登录EMR Master验证Ranger策略](#登录EMR-Master验证Ranger策略)
  * [八. 使用Bootstrap自动安装Ranger Plugin](#八-使用Bootstrap自动安装Ranger-Plugin)
  * [九. 为Hive启用LDAP认证](#九-为Hive启用LDAP认证)
  * [十. 为Presto启用LDAP认证](#十-为Presto启用LDAP认证)
  

## 说明
将Apache Ranger 2.1与Amazon EMR集成，实现Hive，Presto应用基于数据库，表，列的权限控制。

整套环境的组件包括：
 - LDAP Server： 作为访问Hive/Presto的用户的数据库，实现用户登录认证的工作
 - Ranger Admin：管理
   - Policy Manager: 负责对Hive/Presto基于数据库，表和列级别的授权
   - User Sync：负责与LDAP Server同步用户
   - Solr Audit：负责用户访问Hive/Presto应用的行为审计，包括读写，查询等，以及RangerAdmin登录
   - Plugin：安装在EMR Master上，与Hive和Presto Server集成，拦截用户与Hive/presto之间的交互，并基于Ranger policymanager进行授权

**注意：**

 - **第一部分为安装OpenLDAP，也可以使用Amazon Directory Service中的SimpleAD来代替**

 - **默认Ranger2.x要求Hive版本为3.x，对Presto只支持PrestoSQL，不支持Prestodb。而EMR 5.x只支持hive2和Prestodb，所以原生的Ranger 2.x不支持EMR 5.x。通过原生Ranger 2.x build出来的Plugin pacakage，只支持EMR 6.x的hive3**

 - **本文档中，使用的Ranger Hive Plugin和Ranger Prestodb Plugin安装包，均来自以下AWS Blog，安装包是由Blog作者基于基于原生Ranger 2.1手动做了很多定制化，用来兼容EMR 5.x版本的Hive 2.x和Prestodb**

    [Implementing Authorization and Auditing using Apache Ranger on Amazon EMR](https://aws.amazon.com/blogs/big-data/implementing-authorization-and-auditing-using-apache-ranger-on-amazon-emr/)

 - **本文档已完成EMR 5.30版本的兼容性测试，未对EMR 6.x进行测试**


## 一. 安装OpenLDAP

1. 安装OpenLDAP server

```shell
sudo yum install -y openldap openldap-servers openldap-clients openldap-devel
[ec2-user@ip-172-31-37-254 ~]$ sudo yum list installed | grep openldap
Existing lock /var/run/yum.pid: another copy is running as pid 3618.
Another app is currently holding the yum lock; waiting for it to exit...
  The other application is: yum
    Memory : 118 M RSS (335 MB VSZ)
    Started: Tue Sep 15 03:36:28 2020 - 00:04 ago
    State  : Running, pid: 3618
openldap.x86_64                       2.4.44-15.amzn2                installed
openldap-clients.x86_64               2.4.44-15.amzn2                @amzn2-core
openldap-devel.x86_64                 2.4.44-15.amzn2                @amzn2-core
openldap-servers.x86_64               2.4.44-15.amzn2                @amzn2-core
```

2. set OpenLDAP admin password
```
[ec2-user@ip-172-31-37-254 ~]$ slappasswd
New password:
Re-enter new password:
{SSHA}2+plyEGECw0IcAvelyt6LYHdbDAUN+Dx
```

3. 启动LDAP服务
```
sudo systemctl start slapd //启动 stop停止
sudo systemctl enable slapd //开机运行
sudo systemctl status slapd //查看运行状态及相关输出日志
```

4. Configure OpenLDAP
使用ldif配置修改OpenLDAP配置
```
vim domain_config.ldif
>> 
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=rangeradmin,dc=ap-northeast-1,dc=compute,dc=internal" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: {SSHA}7mJdo1oc+MMnl+oNjAASkz9U45oAYWmP   
-
replace: olcRootDN
olcRootDN: cn=rangeradmin,dc=ap-northeast-1,dc=compute,dc=internal
-
replace: olcSuffix
olcSuffix: dc=ap-northeast-1,dc=compute,dc=internal
-
add: olcAccess
olcAccess: {0}to attrs=userPassword by self write by dn.base="cn=rangeradmin,dc=ap-northeast-1,dc=compute,dc=internal" write by anonymous auth by * none
olcAccess: {1}to * by dn.base="cn=rangeradmin,dc=ap-northeast-1,dc=compute,dc=internal" write by self write by * read

##应用配置
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f domain_config.ldif
```

5. 导入LDAP Schema
```
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/core.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

```

6. 创建Domain
```
vim domain.ldif
>> 
dn: dc=ap-northeast-1,dc=compute,dc=internal
objectClass: dcObject
objectClass: organization
#dc: compute
o : compute

##应用配置
sudo ldapadd -D "cn=rangeradmin,dc=ap-northeast-1,dc=compute,dc=internal" -W -f domain.ldif
```

7. 导入Ldap数据库
```
sudo cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
sudo chown ldap:ldap -R /var/lib/ldap
sudo chmod 700 -R /var/lib/ldap
```

8. 创建Ldap用户
```
##设置用户密码
slappasswd
{SSHA}ZBe7cAFfSv/63uKUuFIgdVRtLLQkFx4o
123456

##创建LDAP用户
vim users.ldif
>> 
dn: uid=hive,dc=ap-northeast-1,dc=compute,dc=internal
sn: hive
cn: hive
objectClass: inetOrgPerson
userPassword: {SSHA}TiONe309UkyVzfrNslYxtjY1mJv5f7fC
uid: hive

dn: uid=presto,dc=ap-northeast-1,dc=compute,dc=internal
sn: presto
cn: presto
objectClass: inetOrgPerson
userPassword: {SSHA}TiONe309UkyVzfrNslYxtjY1mJv5f7fC
uid: presto

dn: uid=presto,dc=ap-northeast-1,dc=compute,dc=internal
sn: hue
cn: hue
objectClass: inetOrgPerson
userPassword: {SSHA}TiONe309UkyVzfrNslYxtjY1mJv5f7fC
uid: hue

##应用LDAP用户配置
sudo ldapadd -D "cn=rangeradmin,dc=ap-northeast-1,dc=compute,dc=internal" -W -f users.ldif
```

9. 验证LDAP服务
```
sudo slaptest -u
config file testing succeeded #验证成功，否则失败
```
10. 测试User LDAP 连接
```
ldapsearch -x -b dc=ap-northeast-1,dc=compute,dc=internal -H ldap://ip-172-31-36-146.ap-northeast-1.compute.internal -D cn=rangeradmin,dc=ap-northeast-1,dc=compute,dc=internal -W

ldapwhoami -x -D uid=hive,dc=ap-northeast-1,dc=compute,dc=internal -H ldap://ip-172-31-36-146.ap-northeast-1.compute.internal -W

ldapwhoami -x -w "123456" -D uid=presto,dc=ap-northeast-1,dc=compute,dc=internal -H ldap://ip-172-31-36-146.ap-northeast-1.compute.internal

```

11. 限制anonymous登录
```
# Disable anonymous access
vim ldap_disable_bind_anon.ldif
>>
dn: cn=config
changetype: modify
add: olcDisallows
olcDisallows: bind_anon

dn: cn=config
changetype: modify
add: olcRequires
olcRequires: authc

dn: olcDatabase={-1}frontend,cn=config
changetype: modify
add: olcRequires
olcRequires: authc

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f ldap_disable_bind_anon.ldif

##验证anonymous登录
[ec2-user@ip-172-31-46-68 ~]$ ldapsearch -x -LLL -b ldap://127.0.0.1
ldap_bind: Inappropriate authentication (48)
	additional info: anonymous bind disallowed
```

12. LDAPS 配置

12.1. 为LDAPS创建CA key和CA证书

```
# Create certificates
ls -l /etc/pki/CA/
cd /etc/pki/CA
echo 0001 > serial
touch index.txt

## 生成CA private key
openssl genrsa -aes256 -out /etc/pki/CA/private/ca.key.pem    ***changeit***

## 生成CA Certiricate
openssl req -new -x509 -days 3650 -key /etc/pki/CA/private/ca.key.pem -extensions v3_ca -out /etc/pki/CA/certs/ca.cert.pem
	# Country Name (2 letter code) [XX]:CN
	# State or Province Name (full name) []:SH
	# Locality Name (eg, city) [Default City]:SH
	# Organization Name (eg, company) [Default Company Ltd]:Ranger
	# Organizational Unit Name (eg, section) []:Test
	# Common Name (eg, your name or your server's hostname) []:ip-172-31-36-146.ap-northeast-1.compute.internal
	# Email Address []:hxh@amazon.com

```

12.2. 为LDAPS创建Server CSR，并使用CA证书签发Server证书

** ！！注意LDAP server证书的CN，要和客户端在连接LDAPS认证时指定的LDAPS URL对应，一般使用LDAP server可解析的主机名，或者使用通配符证书（未验证），否则会出现证书不匹配的错误，导致LDAPS连接失败** 
```
cd /etc/pki/CA/
##创建LDAP server private key
openssl genrsa -out private/ldap.key

##创建LDAP server CSR
openssl req -new -key private/ldap.key -out certs/ldap.csr  -days 3650
	# Country Name (2 letter code) [XX]:CN
	# State or Province Name (full name) []:SH
	# Locality Name (eg, city) [Default City]:SH
	# Organization Name (eg, company) [Default Company Ltd]:Ranger
	# Organizational Unit Name (eg, section) []:Test
	# Common Name (eg, your name or your server's hostname) []:ip-172-31-36-146.ap-northeast-1.compute.internal
	# Email Address []:hxh@amazon.com

##使用CA证书，根据CSR签发server证书
openssl ca -keyfile private/ca.key.pem -cert certs/ca.cert.pem -in certs/ldap.csr -out certs/ldap.crt -days 3650
cat index.txt
##创建LDAP server CSR
openssl verify -CAfile certs/ca.cert.pem certs/ldap.crt
```

12.3. 将CA证书和Server证书复制到LDAP证书目录

```
cp -v certs/* /etc/openldap/certs/
cp -v private/ldap.key /etc/openldap/certs/
mkdir /etc/openldap/cacerts/
cp -v certs/ca.cert.pem /etc/openldap/cacerts/
chown -R ldap. /etc/openldap/certs/
chown -R ldap. /etc/openldap/cacerts/
ll /etc/openldap/cacerts/
ll /etc/openldap/certs/
```

12.4. 修改LDAP TLS配置

```
# Config ldap tls 
slapcat -b "cn=config" | egrep "olcTLSCertificateFile|olcTLSCertificateKeyFile"

vim /tmp/certs.ldif
>> 
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/ldap.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/ldap.key

##应用配置
sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/certs.ldif
sudo slapcat -b "cn=config" | egrep "olcTLSCertificateFile|olcTLSCertificateKeyFile"


vim /tmp/ca.ldif
>> 
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/openldap/cacerts/ca.cert.pem

##应用配置
sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/ca.ldif
sudo slapcat -b "cn=config" | egrep "olcTLSCertificateFile|olcTLSCertificateKeyFile|olcTLSCACertificateFile"

sudo slaptest -u
```

12.5. 启用LDAPS，并重启服务

```
# Enable ldaps
vim /etc/sysconfig/slapd
>>
SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"

service slapd restart
service slapd status

# Verify ldaps
# ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config | grep olcTLS
netstat -antupl | grep 636
netstat -antupl | grep 389
```

12.6. 验证LDAPS连接

```
##Test LDAPS connection
ldapsearch -x -b dc=ap-northeast-1,dc=compute,dc=internal -H ldaps://ip-172-31-36-146.ap-northeast-1.compute.internal -D cn=rangeradmin,dc=ap-northeast-1,dc=compute,dc=internal -W

ldapwhoami -x -D uid=hive,dc=ap-northeast-1,dc=compute,dc=internal -H ldaps://ip-172-31-36-146.ap-northeast-1.compute.internal -W

## ！！注意：需要将LDAP server的CA证书和LDAP server证书，复制到LDAP client所在的机器
## 需要在LDAP client的配置文件/etc/openldap/ldap.conf中，指定LDAP server的CA证书路径，将LDAP server的CA证书复制到下面路径
##/etc/openldap/ldap.conf
TLS_CACERTDIR   /etc/openldap/certs

##或者通过环境变量指定LDAP server的CA证书和LDAP证书
export LDAPTLS_CACERT=/path/ca.cert.pem
export LDAPTLS_CERT=/path/ldap.crt

##如果以下错误，则基本上是证书问题，LDAP client上的LDAP CA证书和LDAP证书的路径没配置正确
ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)

ldap_sasl_interactive_bind_s: Can't contact LDAP server (-1)
	additional info: error:14090086:SSL routines:ssl3_get_server_certificate:certificate verify failed (self signed certificate in certificate chain)

ldap_sasl_interactive_bind_s: Can't contact LDAP server (-1)
    additional info: TLS error -8172:Peer's certificate issuer has been marked as not trusted by the user.

```

## 二. Build Ranger安装包

以下步骤以Ranger 2.0举例，Ranger 2.x版本均要求Hive版本3.x，所以默认不支持EMR 5.x版本，可以支持EMR 6.x

另外，Ranger2.x版本支持了PrestoSQL的官方插件，但是不支持Prestodb，所以无法支持EMR 5.x版本

**在后面安装Ranger Plugin的章节中，实际使用的是由AWS Blog提供的基于Ranger 2.1手动修改定制的Ranger Hive Plugin和Ranger Prestodb Plugin的安装包。**

1. 安装Build所需的包
```
#set -euo pipefail
#set -x
sudo yum -y install java-1.8.0
sudo yum install java-1.8.0-openjdk-devel.x86_64 -y

sudo yum -y remove java-1.7.0-openjdk

sudo yum install git -y
sudo yum install python3 -y
sudo pip3 install requests -y 
sudo yum install gcc g++ -y
```

2. Build Ranger
```
#git clone https://github.com/apache/ranger ##这是下载最新版本，目前是3.0.0-snapshot
#wget https://downloads.apache.org/ranger/2.0.0/apache-ranger-2.0.0.tar.gz
wget https://mirrors.koehn.com/apache/ranger/2.1.0/apache-ranger-2.1.0.tar.gz

#tar xzvf apache-ranger-2.0.0.tar.gz
tar xzvf apache-ranger-2.1.0.tar.gz

##需要mvn 3.6.3, python3, requests(pip3)
wget https://mirrors.tuna.tsinghua.edu.cn/apache/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz

##Download and Setup maven
sudo tar xf apache-maven-3.6.3-bin.tar.gz -C /opt
sudo su
export PATH=/opt/apache-maven-3.6.3/bin:$PATH
export MAVEN_OPTS=-Xmx2048m

##需要通过ls -l /etc/alternatives/java 查找JAVA HOME
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.265.b01-1.amzn2.0.1.x86_64
export PATH=$JAVA_HOME/bin:$PATH

## Start to build
#cd apache-ranger-2.0.0
cd apache-ranger-2.1.0

##可以在根目录下的pom.xml文件中查看Ranger对Maven，以及对各个Hadoop生态应用要求的版本
<hadoop.version>3.1.1</hadoop.version>
<ozone.version>0.4.0-alpha</ozone.version>
<hamcrest.all.version>1.3</hamcrest.all.version>
<hbase.version>2.0.2</hbase.version>
<hive.version>3.1.0</hive.version>
<hbase-shaded-protobuf>2.0.0</hbase-shaded-protobuf>
<hbase-shaded-netty>2.0.0</hbase-shaded-netty>
<hbase-shaded-miscellaneous>2.0.0</hbase-shaded-miscellaneous>

## 开始build
sudo mvn -DskipTests=false clean compile package install assembly:assembly 

[INFO] Reactor Summary for ranger 2.0.0:
[INFO] 
[INFO] ranger ............................................. SUCCESS [  0.513 s]
[INFO] Jdbc SQL Connector ................................. SUCCESS [  1.524 s]
[INFO] Credential Support ................................. SUCCESS [  0.731 s]
[INFO] Audit Component .................................... SUCCESS [  2.212 s]
[INFO] Common library for Plugins ......................... SUCCESS [  6.701 s]
[INFO] Installer Support Component ........................ SUCCESS [  0.229 s]
[INFO] Credential Builder ................................. SUCCESS [  0.521 s]
[INFO] Embedded Web Server Invoker ........................ SUCCESS [  0.776 s]
[INFO] Key Management Service ............................. SUCCESS [  1.664 s]
[INFO] ranger-plugin-classloader .......................... SUCCESS [  0.240 s]
[INFO] HBase Security Plugin Shim ......................... SUCCESS [  1.677 s]
[INFO] HBase Security Plugin .............................. SUCCESS [  2.372 s]
[INFO] Hdfs Security Plugin ............................... SUCCESS [  0.967 s]
[INFO] Hive Security Plugin ............................... SUCCESS [  1.727 s]
[INFO] Knox Security Plugin Shim .......................... SUCCESS [  0.454 s]
[INFO] Knox Security Plugin ............................... SUCCESS [  0.712 s]
[INFO] Storm Security Plugin .............................. SUCCESS [  0.545 s]
[INFO] YARN Security Plugin ............................... SUCCESS [  0.557 s]
[INFO] Ozone Security Plugin .............................. SUCCESS [  0.556 s]
[INFO] Ranger Util ........................................ SUCCESS [  1.551 s]
[INFO] Unix Authentication Client ......................... SUCCESS [  0.330 s]
[INFO] Security Admin Web Application ..................... SUCCESS [ 53.462 s]
[INFO] KAFKA Security Plugin .............................. SUCCESS [  0.515 s]
[INFO] SOLR Security Plugin ............................... SUCCESS [  0.747 s]
[INFO] NiFi Security Plugin ............................... SUCCESS [  2.609 s]
[INFO] NiFi Registry Security Plugin ...................... SUCCESS [  0.450 s]
[INFO] Unix User Group Synchronizer ....................... SUCCESS [  1.340 s]
[INFO] Ldap Config Check Tool ............................. SUCCESS [  0.351 s]
[INFO] Unix Authentication Service ........................ SUCCESS [  0.512 s]
[INFO] KMS Security Plugin ................................ SUCCESS [  0.649 s]
[INFO] Tag Synchronizer ................................... SUCCESS [  0.814 s]
[INFO] Hdfs Security Plugin Shim .......................... SUCCESS [  0.365 s]
[INFO] Hive Security Plugin Shim .......................... SUCCESS [  0.909 s]
[INFO] YARN Security Plugin Shim .......................... SUCCESS [  0.361 s]
[INFO] OZONE Security Plugin Shim ......................... SUCCESS [  0.425 s]
[INFO] Storm Security Plugin shim ......................... SUCCESS [  0.352 s]
[INFO] KAFKA Security Plugin Shim ......................... SUCCESS [  0.345 s]
[INFO] SOLR Security Plugin Shim .......................... SUCCESS [  0.573 s]
[INFO] Atlas Security Plugin Shim ......................... SUCCESS [  0.427 s]
[INFO] KMS Security Plugin Shim ........................... SUCCESS [  0.362 s]
[INFO] ranger-examples .................................... SUCCESS [  0.045 s]
[INFO] Ranger Examples - Conditions and ContextEnrichers .. SUCCESS [  0.325 s]
[INFO] Ranger Examples - SampleApp ........................ SUCCESS [  0.150 s]
[INFO] Ranger Examples - Ranger Plugin for SampleApp ...... SUCCESS [  0.457 s]
[INFO] Ranger Tools ....................................... SUCCESS [  0.662 s]
[INFO] Atlas Security Plugin .............................. SUCCESS [  0.655 s]
[INFO] Sqoop Security Plugin .............................. SUCCESS [  0.484 s]
[INFO] Sqoop Security Plugin Shim ......................... SUCCESS [  0.347 s]
[INFO] Kylin Security Plugin .............................. SUCCESS [  0.373 s]
[INFO] Kylin Security Plugin Shim ......................... SUCCESS [  0.309 s]
[INFO] Elasticsearch Security Plugin Shim ................. SUCCESS [  0.207 s]
[INFO] Elasticsearch Security Plugin ...................... SUCCESS [  0.407 s]
[INFO] Presto Security Plugin ............................. SUCCESS [  0.599 s]
[INFO] Presto Security Plugin Shim ........................ SUCCESS [  0.565 s]
[INFO] Unix Native Authenticator .......................... SUCCESS [  0.763 s]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  26:41 min
[INFO] Finished at: 2020-09-16T05:44:04Z
[INFO] ------------------------------------------------------------------------
[root@ip-172-31-43-166 apache-ranger-2.0.0]# 
[root@ip-172-31-43-166 apache-ranger-2.0.0]# cd target/
[root@ip-172-31-43-166 target]# ls -l
total 1605044
drwxr-xr-x 2 root root        28 Sep 16 05:17 antrun
drwxr-xr-x 2 root root       113 Sep 16 05:42 archive-tmp
drwxr-xr-x 3 root root        22 Sep 16 05:17 maven-shared-archive-resources
-rw-r--r-- 1 root root 248549123 Sep 16 05:39 ranger-2.0.0-admin.tar.gz
-rw-r--r-- 1 root root 249664689 Sep 16 05:40 ranger-2.0.0-admin.zip
-rw-r--r-- 1 root root  27792642 Sep 16 05:41 ranger-2.0.0-atlas-plugin.tar.gz
-rw-r--r-- 1 root root  27831326 Sep 16 05:41 ranger-2.0.0-atlas-plugin.zip
-rw-r--r-- 1 root root  31560345 Sep 16 05:42 ranger-2.0.0-elasticsearch-plugin.tar.gz
-rw-r--r-- 1 root root  31605153 Sep 16 05:42 ranger-2.0.0-elasticsearch-plugin.zip
-rw-r--r-- 1 root root  26633840 Sep 16 05:37 ranger-2.0.0-hbase-plugin.tar.gz
-rw-r--r-- 1 root root  26665160 Sep 16 05:37 ranger-2.0.0-hbase-plugin.zip
-rw-r--r-- 1 root root  23970754 Sep 16 05:37 ranger-2.0.0-hdfs-plugin.tar.gz
-rw-r--r-- 1 root root  23996749 Sep 16 05:37 ranger-2.0.0-hdfs-plugin.zip
-rw-r--r-- 1 root root  23825939 Sep 16 05:37 ranger-2.0.0-hive-plugin.tar.gz
-rw-r--r-- 1 root root  23854012 Sep 16 05:37 ranger-2.0.0-hive-plugin.zip
-rw-r--r-- 1 root root  39934681 Sep 16 05:38 ranger-2.0.0-kafka-plugin.tar.gz
-rw-r--r-- 1 root root  39983157 Sep 16 05:38 ranger-2.0.0-kafka-plugin.zip
-rw-r--r-- 1 root root  90979985 Sep 16 05:40 ranger-2.0.0-kms.tar.gz
-rw-r--r-- 1 root root  91104656 Sep 16 05:41 ranger-2.0.0-kms.zip
-rw-r--r-- 1 root root  28379986 Sep 16 05:37 ranger-2.0.0-knox-plugin.tar.gz
-rw-r--r-- 1 root root  28410407 Sep 16 05:37 ranger-2.0.0-knox-plugin.zip
-rw-r--r-- 1 root root  23940279 Sep 16 05:41 ranger-2.0.0-kylin-plugin.tar.gz
-rw-r--r-- 1 root root  23979339 Sep 16 05:41 ranger-2.0.0-kylin-plugin.zip
-rw-r--r-- 1 root root     34248 Sep 16 05:40 ranger-2.0.0-migration-util.tar.gz
-rw-r--r-- 1 root root     37740 Sep 16 05:40 ranger-2.0.0-migration-util.zip
-rw-r--r-- 1 root root  26387332 Sep 16 05:38 ranger-2.0.0-ozone-plugin.tar.gz
-rw-r--r-- 1 root root  26420407 Sep 16 05:38 ranger-2.0.0-ozone-plugin.zip
-rw-r--r-- 1 root root  40297789 Sep 16 05:42 ranger-2.0.0-presto-plugin.tar.gz
-rw-r--r-- 1 root root  40340865 Sep 16 05:42 ranger-2.0.0-presto-plugin.zip
-rw-r--r-- 1 root root  22230522 Sep 16 05:41 ranger-2.0.0-ranger-tools.tar.gz
-rw-r--r-- 1 root root  22247463 Sep 16 05:41 ranger-2.0.0-ranger-tools.zip
-rw-r--r-- 1 root root     42230 Sep 16 05:40 ranger-2.0.0-solr_audit_conf.tar.gz
-rw-r--r-- 1 root root     45636 Sep 16 05:40 ranger-2.0.0-solr_audit_conf.zip
-rw-r--r-- 1 root root  26963884 Sep 16 05:38 ranger-2.0.0-solr-plugin.tar.gz
-rw-r--r-- 1 root root  27009332 Sep 16 05:39 ranger-2.0.0-solr-plugin.zip
-rw-r--r-- 1 root root  23952147 Sep 16 05:41 ranger-2.0.0-sqoop-plugin.tar.gz
-rw-r--r-- 1 root root  23985313 Sep 16 05:41 ranger-2.0.0-sqoop-plugin.zip
-rw-r--r-- 1 root root   4014441 Sep 16 05:41 ranger-2.0.0-src.tar.gz
-rw-r--r-- 1 root root   6257752 Sep 16 05:41 ranger-2.0.0-src.zip
-rw-r--r-- 1 root root  37234498 Sep 16 05:38 ranger-2.0.0-storm-plugin.tar.gz
-rw-r--r-- 1 root root  37268004 Sep 16 05:38 ranger-2.0.0-storm-plugin.zip
-rw-r--r-- 1 root root  32770127 Sep 16 05:40 ranger-2.0.0-tagsync.tar.gz
-rw-r--r-- 1 root root  32780737 Sep 16 05:40 ranger-2.0.0-tagsync.zip
-rw-r--r-- 1 root root  16255231 Sep 16 05:40 ranger-2.0.0-usersync.tar.gz
-rw-r--r-- 1 root root  16279286 Sep 16 05:40 ranger-2.0.0-usersync.zip
-rw-r--r-- 1 root root  23956192 Sep 16 05:38 ranger-2.0.0-yarn-plugin.tar.gz
-rw-r--r-- 1 root root  23991651 Sep 16 05:38 ranger-2.0.0-yarn-plugin.zip
-rw-r--r-- 1 root root         5 Sep 16 05:42 version
[root@ip-172-31-43-166 target]# 

```
## 三. 安装 Ranger Server

**可以登录到Ranger Server，直接运行install-ranger-admin-server.sh脚本**

如果需要手动一步步安装，请参考以下步骤

1. 设置环境变量
```
sudo su
hostip=`hostname -I | xargs`
installpath=/usr/lib/ranger
mysql_jar=mysql-connector-java-5.1.39.jar
ranger_admin=ranger-2.1.0-admin
ranger_user_sync=ranger-2.1.0-usersync
ldap_domain=ap-northeast-1.compute.internal      
ldap_server_url=ldap://ip-172-31-36-146.ap-northeast-1.compute.internal:389 
ldap_base_dn=dc=ap-northeast-1,dc=compute,dc=internal
ldap_bind_user_dn=uid=hive,dc=ap-northeast-1,dc=compute,dc=internal 
ldap_bind_password=123456
ranger_s3bucket=https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger
```

2. 安装
```
sudo mkdir -p $installpath
cd $installpath

wget $ranger_s3bucket/$ranger_admin_server.tar.gz
wget $ranger_s3bucket/$ranger_user_sync.tar.gz
wget $ranger_s3bucket/$mysql_jar
wget $ranger_s3bucket/solr_for_audit_setup.tar.gz

#Install mySQL
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

#准备安装包
sudo tar xvpfz $ranger_admin.tar.gz -C $installpath
sudo tar xvpfz $ranger_user_sync.tar.gz -C $installpath
cp $mysql_jar $installpath
cd $installpath

# Update ranger admin install.properties
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
sudo sed -i "s|#audit_solr_urls=.*|audit_solr_urls=http://$hostip:8983/solr/ranger_audits|g" install.properties


#Update LDAP properties
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

# Update ranger usersync install.properties
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

#Download the install solr for ranger
cd $installpath
sudo tar -xvf solr_for_audit_conf.tar.gz
cd solr_for_audit_setup
sudo sed -i "s|#JAVA_HOME=.*|JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.252.b09-2.amzn2.0.1.x86_64/jre|g" install.properties
sudo sed -i "s|SOLR_INSTALL=.*|SOLR_INSTALLL=true|g" install.properties
sudo sed -i "s|SOLR_DOWNLOAD_URL=.*|SOLR_DOWNLOAD_URL=http://archive.apache.org/dist/lucene/solr/5.2.1/solr-5.2.1.tgz|g" install.properties
sudo sed -i "s|SOLR_HOST_URL=.*|SOLR_HOST_URL=http://$hostip:8983|g" install.properties
sudo sed -i "s|SOLR_RANGER_PORT=.*|SOLR_RANGER_PORT=8983|g" install.properties
sudo chmod +x setup.sh
sudo -E ./setup.sh


# #Change password
# Change rangerusersync user password in Ranger Admin Console, then Execute:
# sudo -E python ./updatepolicymgrpassword.sh

#Start Ranger Admin
# sudo /usr/bin/ranger-admin stop


#Start Ranger Usersync
# sudo /usr/bin/ranger-usersync stop
sudo /usr/bin/ranger-usersync start

#Start Ranger Audit 
# /opt/solr/ranger_audit_server/scripts/stop_solr.sh
sudo /opt/solr/ranger_audit_server/scripts/start_solr.sh

# The default usersync runs every 1 hour (cannot be changed). This is way to force usersync
#sudo echo /usr/bin/ranger-usersync restart | at now + 5 minutes
#sudo echo /usr/bin/ranger-usersync restart | at now + 7 minutes
#sudo echo /usr/bin/ranger-usersync restart | at now + 10 minutes
```

通过浏览器打开http://ranger-server:6080 验证ranger是否安装成功，默认用户名密码为admin/admin，如果在配置中修改了默认密码，请使用配置中的密码登录。


## 四. 启动EMR集群

启动EMR集群，选择Advanced Option
- 选择EMR 5.30.1版本，Hadoop，Hive，Hue，Spark，Presto
- 使用Glue作为Hive，Presto和Spark的Metadata
- 指定EMR Launch Configuration，包括Hue的LDAP配置，External Database，以及Metastore的配置
- 在Launch Configuration中添加Hive和Presto使用LDAP认证的配置
![Launch EMR](./pics/EMR-application.png)

- 为EMR集群指定EC2 Key Pair
- Presto如果启用用户名密码认证（例如LDAP），则Presto节点之间通信需要使用HTTPS，所以需要提前生成证书，加载到集群中。
 1. 生成证书，用于EMR in-transit encryption
```
## self-generate 证书，用于EMR in-transit encryption，在EMR security configuration里配置
## EMR presto使用用户名密码，必须使用https
openssl req -x509 -newkey rsa:1024 -keyout privateKey.pem -out certificateChain.pem -days 365 -nodes -subj '/C=CN/ST=SH/L=SH/O=AWS/OU=AWS/CN=*.ap-northeast-1.compute.internal'
cp certificateChain.pem trustedCertificates.pem
##将生成的证书打包，上传到S3
zip -r -X emr-certs-new.zip certificateChain.pem privateKey.pem trustedCertificates.pem
```
 2. 在EMR中，提前创建Security Configuration，选择之前打包上传到S3的证书文件

![SecurityConfiguration](./pics/SecurityConfiguration.png)

 3. 在启动EMR集群时，选择创建的Security Configuration
 ![EMR Security](./pics/EMR-security.png)


EMR集群启动参考配置如下，包括：
 - Hive LDAP
 - Presto LDAP
 - Hue LDAP
 - Hive使用Glue作为metastore
 - Presto使用Hive metastore
 - Spark使用Hive etastore
 - 当启动类型为Multi master时（单Master集群也适用，不强制），要求Hue使用外部数据库，这里使用RDS
 - 当启动类型为Multi master时（单Master集群也适用，不强制），Multi master要求启用Ozzie，并使用外部数据库，这里使用RDS

```
[
  {
    "Classification": "presto-config",
    "Properties": {
      "http-server.authentication.type": "PASSWORD"
    }
  },
  {
    "Classification": "presto-password-authenticator",
    "Properties": {
      "password-authenticator.name": "ldap",
      "ldap.url": "ldaps://ip-172-31-36-146.ap-northeast-1.compute.internal:636",
      "ldap.user-bind-pattern": "uid=${USER},dc=ap-northeast-1,dc=compute,dc=internal",
      "internal-communication.authentication.ldap.user": "presto",
      "internal-communication.authentication.ldap.password": "123456"
    }
  },
  {
    "Classification": "oozie-site",
    "Properties": {
      "oozie.service.JPAService.jdbc.driver": "com.mysql.jdbc.Driver",
      "oozie.service.JPAService.jdbc.url": "jdbc:mysql://database-1.cluqkc7jqkna.ap-northeast-1.rds.amazonaws.com:3306/oozie",
      "oozie.service.JPAService.jdbc.username": "admin",
      "oozie.service.JPAService.jdbc.password": "1qazxsw2"
    },
    "Configurations": []
  },
  {
    "Classification": "spark-hive-site",
    "Properties": {
      "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
    }
  },
  {
    "Classification": "presto-connector-hive",
    "Properties": {
      "hive.metastore": "glue"
    }
  },
  {
    "Classification": "hive-site",
    "Properties": {
      "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory",
      "hive.server2.authentication": "LDAP",
      "hive.server2.authentication.ldap.url": "ldap://ip-172-31-36-146.ap-northeast-1.compute.internal:389",
      "hive.server2.authentication.ldap.baseDN": "dc=ap-northeast-1,dc=compute,dc=internal"
    }
  },
  {
    "Classification": "hue-ini",
    "Properties": {},
    "Configurations": [
      {
        "Classification": "desktop",
        "Properties": {},
        "Configurations": [
          {
            "Classification": "database",
            "Properties": {
              "name": "hue",
              "user": "admin",
              "password": "1qazxsw2",
              "host": "database-1.cluqkc7jqkna.ap-northeast-1.rds.amazonaws.com",
              "port": "3306",
              "engine": "mysql"
            },
            "Configurations": []
          },
          {
            "Classification": "ldap",
            "Properties": {},
            "Configurations": [
              {
                "Classification": "ldap_servers",
                "Properties": {},
                "Configurations": [
                  {
                    "Classification": "ldap-hue",
                    "Properties": {
                      "base_dn": "dc=ap-northeast-1,dc=compute,dc=internal",
                      "ldap_url": "ldap://ip-172-31-36-146.ap-northeast-1.compute.internal",
                      "search_bind_authentication": "false",
                      "ldap_username_pattern": "uid=<username>,dc=ap-northeast-1,dc=compute,dc=internal",
                      "bind_dn": "uid=hive,dc=ap-northeast-1,dc=compute,dc=internal",
                      "bind_password": "123456"
                    },
                    "Configurations": [
                      {
                        "classification": "groups",
                        "properties": {
                          "group_filter": "objectclass=groupOfNames",
                          "group_name_attr": "cn"
                        },
                        "configurations": []
                      },
                      {
                        "classification": "users",
                        "properties": {
                          "user_name_attr": "uid",
                          "user_filter": "objectclass=inetOrgPerson"
                        },
                        "configurations": []
                      }
                    ]
                  }
                ]
              }
            ]
          },
          {
            "Classification": "auth",
            "Properties": {
              "backend": "desktop.auth.backend.LdapBackend"
            }
          }
        ]
      }
    ]
  }
]
```

## 五. 为EMR Master安装Ranger Plugin

### 5.1 准备安装包
需要将以下安装包放到S3上，并记录S3的路径，需要在Plugin的安装脚本中指定S3路径

[HDFS Plugin](https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/ranger-2.1.0-SNAPSHOT-hdfs-plugin.tar.gz)

[Hive Plugin](https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/ranger-2.1.0-SNAPSHOT-hive-plugin.tar.gz)

[Prestodb Plugin](https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/ranger-2.1.0-SNAPSHOT-prestodb-plugin-presto232.tar.gz)

[javax.mail-api-1.6.0.jar](https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/javax.mail-api-1.6.0.jar)

[rome-0.9.jar](https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/rome-0.9.jar)

[jdom-1.1.3.jar](https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/jdom-1.1.3.jar)

[mysql-connector-java-5.1.39.jar](https://hxh-tokyo.s3-ap-northeast-1.amazonaws.com/ranger/mysql-connector-java-5.1.39.jar)

### 5.2 安装 Hive Plugin

首先需要将HDFS/Hive安装脚本install-hive-hdfs-ranger-plugin.sh中的s3 bucket路径替换成自己的路径：
```
ranger_s3bucket=s3://hxh-tokyo/ranger
```

然后可以通过Step提交脚本，或者直接登录到EMR Master执行脚本`install-hive-hdfs-ranger-plugin.sh`.

**以通过Step提交脚本为例：脚本文件可以放在S3上，注意需要指定Ranger Server的IP地址作为脚本参数**

```
##运行Shell脚本的JAR包：
s3://elasticmapreduce/libs/script-runner/script-runner.jar

##Step 参数，172.31.43.166为Ranger Admin的IP地址
s3://hxh-tokyo/ranger/install-hive-hdfs-ranger-plugin.sh 172.31.43.166
```

![Install Hive Plugin](./pics/HivePlugin.png)

注意：如果手动运行脚本安装Plugin的时候，运行enable-hive-plugin.sh这个脚本出现以下报错，或者在/var/log/hive/hive-server2.log出现类似报错，是由于Hive Plugin安装包在定制的过程中，缺少一部分Jar包，但不影响Plugin正常工作，该报错可以忽略，实际上HDFS和Hive的Plugin均已正常安装和运行

![Hive Plugin Error](./pics/HivePlugin-error.jpg)




### 5.3 安装 Presto Plugin

首先需要将Presto安装脚本install-presto-ranger-plugin.sh中的s3 bucket路径替换成自己的路径：

```
ranger_s3bucket=s3://hxh-tokyo/ranger
```

然后可以通过Step提交脚本，或者直接登录到EMR Master执行脚本`install-presto-ranger-plugin.s`.

**以通过Step提交脚本为例：脚本文件可以放在S3上，注意需要指定Ranger Server的IP地址作为脚本参数**

```
##运行Shell脚本的JAR包：
s3://elasticmapreduce/libs/script-runner/script-runner.jar

##Step 参数，172.31.43.166为Ranger Admin的IP地址
s3://hxh-tokyo/ranger/install-presto-ranger-plugin.sh 172.31.43.166
```

![Install Presto Plugin](./pics/PrestoPlugin.png)


## 六. 配置 Ranger 授权策略

为Ranger配置基于Resource的授权策略，可以通过Ranger Admin的Web UI手动配置，也可以通过脚本的方式，利用Ranger API配置。建议先使用脚本配置初始策略，再通过Ranger UI进行修改。

**示例策略：为用户Hue分配Hive和Presto Metastore中Default数据库的读写权限。**

首先将Ranger Policies的策略文件放到S3上，并记录路径，例如s3://hxh-tokyo/ranger/policies

### 6.1 加载HDFS和Hive策略

首先确认将脚本中的策略文件S3路径，修改为自己的S3路径
```
ranger_policybucket=s3://hxh-tokyo/ranger/policies
```

然后可以通过Step提交脚本，或者直接登录到EMR Master执行脚本`install-hive-hdfs-ranger-policies.sh`.

**以通过Step提交脚本为例：脚本文件可以放在S3上，注意需要指定Ranger Server的IP地址作为脚本参数**

```
##运行Shell脚本的JAR包：
s3://elasticmapreduce/libs/script-runner/script-runner.jar

##Step 参数，172.31.43.166为Ranger Admin的IP地址
s3://hxh-tokyo/ranger/install-hive-hdfs-ranger-policies.sh 172.31.43.166
```

![Install HDFS/Hive Policy](./pics/HivePolicies.png)


### 6.2 加载Presto策略

首先确认将脚本中的策略文件S3路径，修改为自己的S3路径
```
ranger_policybucket=s3://hxh-tokyo/ranger/policies
```

然后可以通过Step提交脚本，或者直接登录到EMR Master执行脚本`install-presto-ranger-policies.sh`.

**以通过Step提交脚本为例：脚本文件可以放在S3上，注意需要指定Ranger Server的IP地址作为脚本参数**

```
##运行Shell脚本的JAR包：
s3://elasticmapreduce/libs/script-runner/script-runner.jar

##Step 参数，172.31.43.166为Ranger Admin的IP地址
s3://hxh-tokyo/ranger/install-presto-ranger-policies.sh 172.31.43.166
```

![Install Presto Policy](./pics/PrestoPolicies.png)


## 七. 验证Ranger权限控制


### 登录Ranger Admin UI查看Resource Access policy


1. 查看Hive 策略

![HiveRangerPolicy](./pics/HiveRangerPolicy.png)

2. 查看Hive的Hue示例策略

![Hive-HueTest](./pics/Hive-HueTest.png)

3. 查看Presto 策略

![PrestoRangerPolicy](./pics/PrestoRangerPolicy.png)

4. 查看Presto的Hue示例策略

![Presto-HueTest](./pics/Presto-HueTest.png)


### 登录Hue UI验证Ranger策略

1. 使用用户名为hue的LDAP用户登录Hue应用，密码为LDAP上的密码

使用Hive应用进行查询

![Hue-Hive](./pics/Hue-Hive.png)

使用Presto应用进行查询

![Hue-Presto](./pics/Hue-Presto.png)

2. 使用用户名为hiveadmin的LDAP用户登录Hue应用，密码为LDAP上的密码

使用Presto应用，提示无权限

![Hue-error1](./pics/Hue-error1.png)

使用Hive应用，提示无权限

![Hue-error2](./pics/Hue-error2.png)

### 登录EMR Master验证Ranger策略

另外也可以通过在EMR Master上执行命令进行验证

**Hive应用验证**
```
[ec2-user@ip-172-31-42-119 ~]$ beeline -u jdbc:hive2://127.0.0.1:10000 -n hue -p 123456
Connecting to jdbc:hive2://127.0.0.1:10000
Connected to: Apache Hive (version 2.3.6-amzn-2)
Driver: Hive JDBC (version 2.3.6-amzn-2)
Transaction isolation: TRANSACTION_REPEATABLE_READ
Beeline version 2.3.6-amzn-2 by Apache Hive
0: jdbc:hive2://127.0.0.1:10000> show tables;
INFO  : Compiling command(queryId=hive_20200927104906_ac036b3e-8a66-4548-9e16-5ab848a1f068): show tables
INFO  : Semantic Analysis Completed
INFO  : Returning Hive schema: Schema(fieldSchemas:[FieldSchema(name:tab_name, type:string, comment:from deserializer)], properties:null)
INFO  : Completed compiling command(queryId=hive_20200927104906_ac036b3e-8a66-4548-9e16-5ab848a1f068); Time taken: 0.101 seconds
INFO  : Concurrency mode is disabled, not creating a lock manager
INFO  : Executing command(queryId=hive_20200927104906_ac036b3e-8a66-4548-9e16-5ab848a1f068): show tables
INFO  : Starting task [Stage-0:DDL] in serial mode
INFO  : Completed executing command(queryId=hive_20200927104906_ac036b3e-8a66-4548-9e16-5ab848a1f068); Time taken: 0.176 seconds
INFO  : OK
+------------------+
|     tab_name     |
+------------------+
| cloudfront_logs  |
+------------------+
1 row selected (0.35 seconds)
0: jdbc:hive2://127.0.0.1:10000>
[ec2-user@ip-172-31-42-119 ~]$ beeline -u jdbc:hive2://127.0.0.1:10000 -n hiveadmin -p 123456
Connecting to jdbc:hive2://127.0.0.1:10000
Connected to: Apache Hive (version 2.3.6-amzn-2)
Driver: Hive JDBC (version 2.3.6-amzn-2)
Transaction isolation: TRANSACTION_REPEATABLE_READ
Beeline version 2.3.6-amzn-2 by Apache Hive
0: jdbc:hive2://127.0.0.1:10000>
0: jdbc:hive2://127.0.0.1:10000> show tables;
Error: Error while compiling statement: FAILED: HiveAccessControlException Permission denied: user [hiveadmin] does not have [USE] privilege on [default] (state=42000,code=40000)
0: jdbc:hive2://127.0.0.1:10000>
```

**使用Presto应用验证**
```
[ec2-user@ip-172-31-42-119 ~]$ presto-cli --catalog hive --schema default --user hue
presto:default> show tables;
      Table
-----------------
 cloudfront_logs
(1 row)

Query 20200927_105108_00015_8krzd, FINISHED, 3 nodes
Splits: 36 total, 36 done (100.00%)
0:01 [1 rows, 32B] [1 rows/s, 49B/s]

presto:default>
presto:default> exit
[ec2-user@ip-172-31-42-119 ~]$ presto-cli --catalog hive --schema default --user hiveadmin
presto:default> show tables;
Query 20200927_105128_00019_8krzd failed: Access Denied: Cannot access catalog hive

presto:default>
```

**使用Presto用户名+密码认证授权，需要使用HTTPS，且要求在集群启动的时候，已通过Security Configuration中的传输加密配置了证书**
```
[ec2-user@ip-172-31-42-119 ~]$ presto-cli \
> --server https://ip-172-31-42-119.ap-northeast-1.compute.internal:8446  \
> --truststore-path /usr/share/aws/emr/security/conf/truststore.jks \
> --truststore-password ri9waMHRNk \
> --catalog hive \
> --schema default \
> --user hue \
> --password
Password:
presto:default> show tables;
      Table
-----------------
 cloudfront_logs
(1 row)

Query 20200927_105541_00022_8krzd, FINISHED, 3 nodes
Splits: 36 total, 36 done (100.00%)
0:00 [1 rows, 32B] [2 rows/s, 75B/s]

presto:default> exit
[ec2-user@ip-172-31-42-119 ~]$ presto-cli --server https://ip-172-31-42-119.ap-northeast-1.compute.internal:8446  --truststore-path /usr/share/aws/emr/security/conf/truststore.jks --truststore-password ri9waMHRNk --catalog hive --schema default --user hiveadmin --password
Password:
presto:default> show tables;
Query 20200927_105804_00025_8krzd failed: Access Denied: Cannot access catalog hive

presto:default>
```

## 八. 使用Bootstrap自动安装Ranger Plugin

众所周知，EMR Bootstrap脚本是在EMR安装和配置各个EMR应用之前运行，由于Ranger Plugin的安装需要依赖Plugin对应的应用，例如安装Ranger Hive Plugin时需要依赖Hive server，所以不能在Bootstrap中直接安装Ranger Plugin。

在EMR的启动过程中，对于需要在应用安装部署完成之后才运行的脚本，可以放到/usr/share/aws/emr/node-provisioner/bin/provision-node 中去执行。

所以本文档是在Bootstrap过程中，将需要执行的Ranger Hive和Presto Plugin安装脚本，加载到/usr/share/aws/emr/node-provisioner/bin/provision-node中，从而让节点在完成EMR应用的配置和启动后，再去安装Ranger Plugin。

**该Boostrap脚本主要是用于EMR Multi Master环境，自动在各个Master节点上，安装Ranger Plugin，而在Master节点发生故障，被新启动的Master替换的时候，也会自动加载Bootstrap，完成Ranger Plugin的安装**

**对于单Master的EMR集群，只是在启动时安装配置一次，且不存在Master故障替换的情况，所以可以选择第五章节中介绍的，通过Step提交Ranger Plugin的安装任务。当然也可以使用本章节中的Bootstrap脚本进行Ranger Plugin的安装。**

![EMR Bootstrap](./pics/EMR-bootstrap.png)

Bootstrap脚本如下：

**(!!!注意需要将脚本里的IP地址 172.31.43.166 替换成自己的Ranger Admin Server的IP地址)**

```
## Ranger-bootstrap.sh ##
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
```
Bootstrap步骤：
1. 检查通过/mnt/var/lib/info/instance.json，检查节点是否是Master，Ranger Plugin只需要在Master节点上安装
2. 如果是Master，下载两个脚本，并将两个脚本加入到/usr/share/aws/emr/node-provisioner/bin/provision-node，使脚本在Master节点上的Hive/Presto应用安装部署完成后才运行。
  - 第一个脚本： install-hive-hdfs-ranger-plugin.sh ， 即在所有Master节点上安装运行HDFS和Hive的Ranger Plugin，对于Multi Master集群的三台Master，Hive server会在三台上分别启动，HDFS Name Node会在其中两台Master中启动，所以在所有Master节点上运行该脚本之后，会自动完成Hive和HDFS Ranger Plugin的安装，对于非HDFS Name Node的Master节点，HDFS会安装失败，但不影响该节点上Ranger Hive Plugin的安装和运行
  
  - 第二个脚本：Check-and-Install-Presto-Plugin.sh ， 对于Multi Master集群的三台Master，只有一台Master是Presto Server，而三台都会运行Presto Client，且EMR会自动将Presto Server所在的Host FQDN加载到Presto client的配置文件中/etc/presto/conf/config.properties。所以该脚本会先检查该Master是否是Presto Server，如果是，才会运行Presto Ranger Plugin的安装
  ```
## Check-and-Install-Presto-Plugin.sh  ##
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

```

对于Multi Master的EMR集群，如果某台Master节点发生故障，则EMR服务会重启启动一台Master，新的Master保留原有Master的Hostname，IP地址以及EMR application。

例如Presto Server所在的Master节点故障，EMR服务会重新启动一台相同IP和Hostname的Master，重新部署所有EMR应用，集群其他Master节点上Presto Client的配置不变，还是指向这台新的Presto Server。

同时，Bootstrap脚本也会在新Master启动的时候运行，重新安装Ranger Plugin。

![Master Failure](./pics/Master-failure.png)


## 九. 为Hive启用LDAP认证

Hive启用LDAP，需要在hive-site.xml配置文件中，添加LDAP相关配置。

可以通过在启用EMR集群的时候，在Launch Configuration中添加Hive LDAP的配置项，该配置会自动添加到hive-site.xml中

```
  {
    "Classification": "hive-site",
    "Properties": {
      "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory",
      "hive.server2.authentication": "LDAP",
      "hive.server2.authentication.ldap.url": "ldap://ip-172-31-36-146.ap-northeast-1.compute.internal:389",
      "hive.server2.authentication.ldap.baseDN": "dc=ap-northeast-1,dc=compute,dc=internal"
    }
  }
```
**验证Hive LDAP认证**

```
[hadoop@ip-172-31-46-190 ~]$ beeline -u jdbc:hive2://ip-172-31-46-190.ap-northeast-1.compute.internal:10000/default -n presto -p 123456
Connecting to jdbc:hive2://ip-172-31-46-190.ap-northeast-1.compute.internal:10000/default
Connected to: Apache Hive (version 2.3.6-amzn-2)
Driver: Hive JDBC (version 2.3.6-amzn-2)
Transaction isolation: TRANSACTION_REPEATABLE_READ
Beeline version 2.3.6-amzn-2 by Apache Hive
0: jdbc:hive2://ip-172-31-46-190.ap-northeast> show tables;
INFO  : Compiling command(queryId=hive_20201106082332_9b859422-e4a1-4f0e-8a19-44b923b22f45): show tables
INFO  : Semantic Analysis Completed
INFO  : Returning Hive schema: Schema(fieldSchemas:[FieldSchema(name:tab_name, type:string, comment:from deserializer)], properties:null)
INFO  : Completed compiling command(queryId=hive_20201106082332_9b859422-e4a1-4f0e-8a19-44b923b22f45); Time taken: 1.175 seconds
INFO  : Concurrency mode is disabled, not creating a lock manager
INFO  : Executing command(queryId=hive_20201106082332_9b859422-e4a1-4f0e-8a19-44b923b22f45): show tables
INFO  : Starting task [Stage-0:DDL] in serial mode
INFO  : Completed executing command(queryId=hive_20201106082332_9b859422-e4a1-4f0e-8a19-44b923b22f45); Time taken: 0.244 seconds
INFO  : OK
+------------------+
|     tab_name     |
+------------------+
| cloudfront_logs  |
+------------------+
1 row selected (1.8 seconds)


###如果用户名或密码错误，则无法连接Hive
[hadoop@ip-172-31-46-190 ~]$ beeline -u jdbc:hive2://ip-172-31-46-190.ap-northeast-1.compute.internal:10000/default -n presto -p 123
Connecting to jdbc:hive2://ip-172-31-46-190.ap-northeast-1.compute.internal:10000/default
20/11/06 09:39:57 [main]: WARN jdbc.HiveConnection: Failed to connect to ip-172-31-46-190.ap-northeast-1.compute.internal:10000
Unknown HS2 problem when communicating with Thrift server.
Error: Could not open client transport with JDBC Uri: jdbc:hive2://ip-172-31-46-190.ap-northeast-1.compute.internal:10000/default: Peer indicated failure: Error validating the login (state=08S01,code=0)
Beeline version 2.3.6-amzn-2 by Apache Hive
```
LDAP认证成功后，会根据Ranger上对应用户的授权策略，获取相应的权限。

## 十. 为Presto启用LDAP认证

Presto启用LDAP认证，需要在Presto配置文件中，添加LDAP相关配置。

可以通过启动EMR时的Launch Configuration添加。
```
  {
    "Classification": "presto-config",
    "Properties": {
      "http-server.authentication.type": "PASSWORD"
    }
  },
  {
    "Classification": "presto-password-authenticator",
    "Properties": {
      "password-authenticator.name": "ldap",
      "ldap.url": "ldaps://ip-172-31-36-146.ap-northeast-1.compute.internal:636",
      "ldap.user-bind-pattern": "uid=${USER},dc=ap-northeast-1,dc=compute,dc=internal",
      "internal-communication.authentication.ldap.user": "presto",
      "internal-communication.authentication.ldap.password": "123456"
    }
  }
```

另外Presto LDAP认证，只支持LDAPS，所以需要将LDAP server的证书导入到EMR集群中，作为LDAP over TLS的证书。

通过Bootstrap的方式，将证书下载到每个集群节点，并导入到JAVA的信任证书中.
```
Download-import-LDAP-cert.sh
##Download LDAP server certificate and import it to all EMR nodes

aws s3 cp s3://hxh-tokyo/ranger/ldap.crt .

sudo keytool -import -keystore /usr/lib/jvm/jre/lib/security/cacerts -trustcacerts -alias ldap_server -file ./ldap.crt -storepass changeit -noprompt

```
![LDAP Certificate](./pics/Download-import-LDAP-Cert.png)

**验证Presto LDAP认证**

Presto的配置文件位于/etc/presto/conf/config.properties，可以查看Presto Server的URL，端口号（默认8446）等信息
```
[hadoop@ip-172-31-46-190 ~]$ more /etc/presto/conf/config.properties
coordinator=false
node-scheduler.include-coordinator=false
discovery.uri=https://ip-172-31-37-239.ap-northeast-1.compute.internal:8446
http-server.threads.max=500
sink.max-buffer-size=1GB
query.max-memory=4915MB
query.max-memory-per-node=6532645258B
query.max-total-memory-per-node=7839174309B
query.max-history=40
query.min-expire-age=30m
query.client.timeout=30m
query.stage-count-warning-threshold=100
query.max-stage-count=150
http-server.http.port=8889
http-server.log.path=/var/log/presto/http-request.log
http-server.log.max-size=67108864B
http-server.log.max-history=5
log.max-size=268435456B
log.max-history=5
internal-communication.authentication.ldap.user=presto
internal-communication.authentication.ldap.password=123456
graceful-shutdown-timeout = 0s
internal-communication.https.keystore.key = bWnuhKTNv0
node.internal-address = ip-172-31-46-190.ap-northeast-1.compute.internal
http-server.https.enabled = true
internal-communication.https.keystore.path = /usr/share/aws/emr/security/conf/truststore.jks
http-server.https.port = 8446
http-server.authentication.type = PASSWORD
internal-communication.https.required = true
http-server.http.enabled =
http-server.https.keystore.path = /usr/share/aws/emr/security/conf/keystore.jks
http-server.https.keystore.key = 6E8PSYjNk7
http-server.https.keymanager.password = yZFA0rgEXA
```

另外通过HTTPS连接Presto，还需要指定trustsore证书路径和密钥，
位于/etc/hadoop/conf/ssl-client.xml文件中
```
[hadoop@ip-172-31-46-190 ~]$ more /etc/hadoop/conf/ssl-client.xml
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!--
   Licensed to the Apache Software Foundation (ASF) under one or more
   contributor license agreements.  See the NOTICE file distributed with
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with
   the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->
<configuration>

  <property>
    <name>ssl.client.keystore.keypassword</name>
    <value>yZFA0rgEXA</value>
  </property>

  <property>
    <name>ssl.client.truststore.reload.interval</name>
    <value>10000</value>
  </property>

  <property>
    <name>ssl.client.keystore.location</name>
    <value>/usr/share/aws/emr/security/conf/keystore.jks</value>
  </property>

  <property>
    <name>ssl.client.truststore.password</name>
    <value>bWnuhKTNv0</value>
  </property>

  <property>
    <name>ssl.client.truststore.type</name>
    <value>jks</value>
  </property>

  <property>
    <name>ssl.client.truststore.location</name>
    <value>/usr/share/aws/emr/security/conf/truststore.jks</value>
  </property>

  <property>
    <name>ssl.client.keystore.password</name>
    <value>6E8PSYjNk7</value>
  </property>

  <property>
    <name>ssl.client.keystore.type</name>
    <value>jks</value>
  </property>
</configuration>
```

验证连接
```
[hadoop@ip-172-31-46-190 ~]$ presto-cli --server https://ip-172-31-37-239.ap-northeast-1.compute.internal:8446 --truststore-path /usr/share/aws/emr/security/conf/truststore.jks --truststore-password bWnuhKTNv0 --user presto --password
Password:
presto> show catalogs;
    Catalog
----------------
 awsdatacatalog
 hive
 system
(3 rows)

Query 20201106_094310_00003_mhbf2, FINISHED, 1 node
Splits: 19 total, 19 done (100.00%)
0:00 [0 rows, 0B] [0 rows/s, 0B/s]

##如果用户名或密码错误，则会提示认证失败
[hadoop@ip-172-31-46-190 ~]$ presto-cli --server https://ip-172-31-37-239.ap-northeast-1.compute.internal:8446 --truststore-path /usr/share/aws/emr/security/conf/truststore.jks --truststore-password bWnuhKTNv0 --user presto --password
Password:
presto> show catalogs;
Error running command: Error starting query at https://ip-172-31-37-239.ap-northeast-1.compute.internal:8446/v1/statement returned an invalid response: JsonResponse{statusCode=500, statusMessage=Server Error, headers={cache-control=[must-revalidate,no-cache,no-store], connection=[close], content-length=[14050], content-type=[text/html;charset=iso-8859-1]}, hasValue=false} [Error: <html>
<head>
<meta http-equiv="Content-Type" content="text/html;charset=utf-8"/>
<title>Error 500 Server Error</title>
</head>
<body><h2>HTTP ERROR 500</h2>
<p>Problem accessing /v1/statement. Reason:
<pre>    Server Error</pre></p><h3>Caused by:</h3><pre>java.lang.RuntimeException: Authentication error
	at com.facebook.presto.server.security.PasswordAuthenticator.authenticate(PasswordAuthenticator.java:71)
```
LDAP认证成功后，会根据Ranger上对应用户的授权策略，获取相应的权限。