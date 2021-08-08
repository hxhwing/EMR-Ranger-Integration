##Download LDAP server certificate and import it to all EMR nodes

aws s3 cp s3://hxh-tokyo/ranger/ldap.crt .

sudo keytool -import -keystore /usr/lib/jvm/jre/lib/security/cacerts -trustcacerts -alias ldap_server -file ./ldap.crt -storepass changeit -noprompt
