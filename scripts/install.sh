#!/bin/bash -e

sudo add-apt-repository -y cloud-archive:mitaka

sudo apt-get update

sudo apt-get -y dist-upgrade

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common rabbitmq-server bind9 mysql-server-5.5 libmysqlclient-dev python-pip designate

sudo service rabbitmq-server start

sudo rabbitmqctl add_user designate designate
sudo rabbitmqctl set_permissions -p "/" designate ".*" ".*" ".*"



sudo rm /etc/bind/named.conf.options 
echo 'options {
  directory "/var/cache/bind";
  dnssec-validation auto;
  auth-nxdomain no; # conform to RFC1035
  listen-on-v6 { any; };
  allow-new-zones yes;
  request-ixfr no;
  recursion no;
};' | sudo tee --append /etc/bind/named.conf.options 

sudo service bind9 restart

sudo pip install pymysql
sudo mysql -u root << EOF
CREATE DATABASE \`designate\` CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE \`designate_pool_manager\` CHARACTER SET utf8 COLLATE utf8_general_ci;
EOF

sudo rm /etc/designate/designate.conf
echo '
[DEFAULT]
########################
## General Configuration
########################
# Show more verbose log output (sets INFO log level output)
verbose = True

# Show debugging output in logs (sets DEBUG log level output)
debug = True

# Top-level directory for maintaining designates state.
state_path = $pybasedir/state

# Log directory
logdir = $pybasedir/log

# Driver used for issuing notifications
notification_driver = messaging

# Use "sudo designate-rootwrap /etc/designate/rootwrap.conf" to use the real
# root filter facility.
# Change to "sudo" to skip the filtering and just run the command directly
# root_helper = sudo

# Supported record types
#supported_record_type = A, AAAA, CNAME, MX, SRV, TXT, SPF, NS, PTR, SSHFP, SOA

# RabbitMQ Config
rabbit_userid = designate
rabbit_password = designate
#rabbit_virtual_host = /
#rabbit_use_ssl = False
#rabbit_hosts = 127.0.0.1:5672

########################
## Service Configuration
########################
#-----------------------
# Central Service
#-----------------------
[service:central]
# Maximum domain name length
#max_domain_name_len = 255

# Maximum record name length
#max_record_name_len = 255

#-----------------------
# API Service
#-----------------------
[service:api]
# Address to bind the API server
api_host = 0.0.0.0

# Port to bind the API server
api_port = 9001

# Authentication strategy to use - can be either "noauth" or "keystone"
auth_strategy = noauth

# Enable API Version 1
enable_api_v1 = True

# Enabled API Version 1 extensions
enabled_extensions_v1 = diagnostics, quotas, reports, sync, touch

# Enable API Version 2
enable_api_v2 = True

# Enabled API Version 2 extensions
enabled_extensions_v2 = quotas, reports

#-----------------------
# mDNS Service
#-----------------------
[service:mdns]
#workers = None
#host = 0.0.0.0
#port = 5354
#tcp_backlog = 100

#-----------------------
# Pool Manager Service
#-----------------------
[service:pool_manager]
pool_id = 794ccc2c-d751-44fe-b57f-8894c9f5c842
#workers = None
#threshold_percentage = 100
#poll_timeout = 30
#poll_retry_interval = 2
#poll_max_retries = 3
#poll_delay = 1
#periodic_recovery_interval = 120
#periodic_sync_interval = 300
#periodic_sync_seconds = None
#cache_driver = sqlalchemy

###################################
## Pool Manager Cache Configuration
###################################
#-----------------------
# SQLAlchemy Pool Manager Cache
#-----------------------
[pool_manager_cache:sqlalchemy]
connection = mysql+pymysql://root@127.0.0.1/designate_pool_manager?charset=utf8
#connection_debug = 100
#connection_trace = False
#sqlite_synchronous = True
#idle_timeout = 3600
#max_retries = 10
#retry_interval = 10

########################
## Storage Configuration
########################
#-----------------------
# SQLAlchemy Storage
#-----------------------
[storage:sqlalchemy]
# Database connection string - to configure options for a given implementation
# like sqlalchemy or other see below
connection = mysql+pymysql://root@127.0.0.1/designate?charset=utf8
#connection_debug = 100
#connection_trace = True
#sqlite_synchronous = True
#idle_timeout = 3600
#max_retries = 10
#retry_interval = 10' | sudo tee --append /etc/designate/designate.conf

sudo mkdir /usr/lib/python2.7/dist-packages/log/
sudo chmod 777 /usr/lib/python2.7/dist-packages/log/

designate-manage database  sync

sudo service designate-central restart
sudo service designate-api restart

sudo apt-get install -y designate-pool-manager designate-mdns

designate-manage pool-manager-cache sync

sudo service designate-pool-manager restart
sudo service designate-mdns restart



echo '
- name: default
  description: Default BIND9 Pool

  attributes: {}

  # List out the NS records for zones hosted within this pool
  ns_records:
    - hostname: ns1-1.example.org.
      priority: 1

  # List out the nameservers for this pool. These are the actual BIND servers.
  # We use these to verify changes have propagated to all nameservers.
  nameservers:
    - host: 127.0.0.1
      port: 53

  targets:
    - type: bind9
      description: BIND9 Server 1
      masters:
        - host: 127.0.0.1
          port: 5354

      # BIND Configuration options
      options:
        host: 127.0.0.1
        port: 53
        rndc_host: 127.0.0.1
        rndc_port: 953
        rndc_key_file: /etc/bind/rndc.key
' | sudo tee --append pools.yaml

designate-manage pool update --file pools.yaml
