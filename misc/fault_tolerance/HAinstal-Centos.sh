#!/bin/bash
#@Author: Joris Bremond

#Script for CentOs, tested with heartbeat 2.1.3

#Requirements : this script must be started with admin (root) right

#-----------------------Variables---------------------------------------------------

#########to be deleted in the future##############

service iptables stop

###############################################





####--Package---#####

DRBD="drbd82"
DRBDKMOD="kmod-drbd82"
HEARTBEAT2="heartbeat"

####--BDD---#####
# "mysql" or "postgresql"
BD="mysql"
##only for postgres
PGVERSION="8.3"

###----Nodes name-----------####

MASTER_OAR="grelon-39"
MASTER_DB="grelon-40"
BACKUP_OAR="grelon-41"
BACKUP_DB="grelon-42"

#-----Nodes properties-----####
#Interface
ETH="eth0"
#OAR-server Virtual IP (ex : )
IP="172.28.54.220"
#Database Virtual IP (ex : 172.16.16.221)
IP_DB="172.28.54.221"
#enter CIDR netmask (ex : 24)
MASK="24"

####------------------Heartbeat----------------#####
##Password sha
PASSWORD="oarteam"

##UDP Port
HBPORT="694"

####-------------------DRBD--------------------#####

##---Device-------#

#--low-level storage for the drbd data (partition)---#
#It could be a loopback device, like /dev/loop0
DISKPARTITION=/dev/loop0

#Do you want create a partition in a file ?  ("y" or "n") --> The DISKPARTITION Must be a loopback interface
#Non tested with real partition ("n")
USEFILEPARTITION="y"

# -----If we have choose yes before -----:

#-PATH File image-#
IMAGE=/image.img

#Size in MegaBytes
SIZE="200"

#---------------------------#



#----DRBD partition alias---#
DRBDPARTITION=/dev/drbd0

#----DRBD mount point---#
DRBDDATA=/mnt/drbddata

#---FileSystem type (ext2,ext3)---#
FSTYPE="ext3"

#----LoopBack----#




##DRBD communication Port
DBRDPORT="7788"


####-------------------CGI script--------------------#####
#enable cgi script for monitor heartbeat ? require httpd (apache)
#"y" or "n"
CGI="y"

#---------------------------Initialisation--------------------------------------------------------------------#

HOSTNAME=$(uname -n)

#High Availability configuration : "2nodes" or "4nodes"
if [ "$MASTER_OAR" = "$MASTER_DB" ]; then
	CONF="2nodes"
else
	CONF="4nodes"
fi


case $HOSTNAME in
$MASTER_OAR)
	ISMASTER="y"
	if [ "$CONF" = "2nodes" ]; then
		ISDATABASE="y"
	else
		ISDATABASE="n"
	fi
	;;
$MASTER_DB)
	ISMASTER="y"
	ISDATABASE="y"
	;;
$BACKUP_OAR)
	ISMASTER="n"
	if [ "$CONF" = "2nodes" ]; then
		ISDATABASE="y"
	else
		ISDATABASE="n"
	fi
	;;
$BACKUP_DB)
	ISMASTER="n"
	ISDATABASE="y"
	;;
*)
	echo "Error : nodes not match with current machine hostname (uname -n)"
	echo "Verify nodes name in the script configuration"
	exit 1
	;;
esac




echo "You are now ready to configure High Availabity with $CONF configuration"
echo "Press enter to continue ..."
read

#Restore mysql configuration
if [ -e /etc/mysql/my.cnf.backup ]; then
	cp /etc/mysql/my.cnf.backup /etc/mysql/my.cnf
fi


########-----------------------------------useful Function  ----------------------############

#Exist commande test
exists()
{
	if which $1 &> /dev/null; then
    		return 0
	else
		echo "$1 command not found."
		echo "Please install $1 before start the script"    		
		exit 1
	fi
}


######----------------------------------require test----------------------------------------#########

exists yum
exists losetup
exists mkfs
exists shred
exists dd
exists mknod
exists tune2fs
exists host



#-----------------------Installation on debian---------------------------------------------------

if [ "$ISDATABASE" = "y" ]; then
	yum -y install $DRBD $DRBDKMOD
	exists drbdadm		#DRBD test
fi

yum -y install $HEARTBEAT2
yum -y install $HEARTBEAT2	#2 times beacause there is a bug ...

#-----Installation tests-----#

exists crmadmin		#Heartbeat test


#-----------------------Stop services---------------------------------------------------
if [ "$ISDATABASE" = "y" ]; then
	if [ "$BD" = "mysql" ]; then
		/etc/init.d/$BD"d" stop
	elif [ "$BD" = "postgresql" ]; then
		echo "not emplemented with postgres"
		exit 1
		/etc/init.d/$BD"-"$PGVERSION stop
	else
		exit 1
	fi
fi
if [ "$ISDATABASE" = "n" ]||[ "$CONF" = "2nodes" ]; then
	/etc/init.d/oar-server stop
fi

#-----------------------Delete old heartbeat configurations---------------------------------------------------

if [ -f /var/lib/heartbeat/crm/cib.xml ]; then
	rm /var/lib/heartbeat/crm/cib.xml
fi
if [ -f /var/lib/heartbeat/crm/cib.xml.sig ]; then
	rm /var/lib/heartbeat/crm/cib.xml.sig
fi

##############-----------------------Heartbeat Configurations---------------------------------------------------################

#-----------------------/etc/ha.d/authkeys---------------------------------------------------
echo 'auth 1' > /etc/ha.d/authkeys
echo "1 sha1 $PASSWORD" >> /etc/ha.d/authkeys
chmod 0600 /etc/ha.d/authkeys


#-----------------------/etc/ha.d/ha.cf---------------------------------------------------



echo '#logfacility local7 ' > /etc/ha.d/ha.cf
echo 'logfile /var/log/ha-log' >> /etc/ha.d/ha.cf
echo 'debugfile /var/log/ha-debug' >> /etc/ha.d/ha.cf
echo '#use_logd on' >> /etc/ha.d/ha.cf
echo "udpport $HBPORT" >> /etc/ha.d/ha.cf
echo 'keepalive 1 # 1 second' >> /etc/ha.d/ha.cf
echo 'deadtime 10' >> /etc/ha.d/ha.cf
echo 'initdead 80' >> /etc/ha.d/ha.cf

if [ "$ISMASTER" = "y" ]; then
	if [ "$ISDATABASE" = "y" ]; then
		ipmaster_oar=$(host $MASTER_OAR | cut -d" " -f4)
		ipmaster_db=$(host `uname -n` | cut -d" " -f4)	#don't use ifconfig beacause can beug if it is a non english system
		ipbackup_oar=$(host $BACKUP_OAR | cut -d" " -f4)
		ipbackup_db=$(host $BACKUP_DB | cut -d" " -f4)		
	elif [ "$ISDATABASE" = "n" ]; then
		ipmaster_oar=$(host `uname -n` | cut -d" " -f4)
		ipmaster_db=$(host $MASTER_DB | cut -d" " -f4)
		ipbackup_oar=$(host $BACKUP_OAR | cut -d" " -f4)
		ipbackup_db=$(host $BACKUP_DB | cut -d" " -f4)
	fi	
elif [ "$ISMASTER" = "n" ]; then
	if [ "$ISDATABASE" = "y" ]; then
		ipmaster_oar=$(host $MASTER_OAR | cut -d" " -f4)
		ipmaster_db=$(host $MASTER_DB | cut -d" " -f4)
		ipbackup_oar=$(host $BACKUP_OAR | cut -d" " -f4)
		ipbackup_db=$(host `uname -n` | cut -d" " -f4)	
	elif [ "$ISDATABASE" = "n" ]; then
		ipmaster_oar=$(host $MASTER_OAR | cut -d" " -f4)
		ipmaster_db=$(host $MASTER_DB | cut -d" " -f4)
		ipbackup_oar=$(host `uname -n` | cut -d" " -f4)
		ipbackup_db=$(host $BACKUP_DB | cut -d" " -f4)
	fi
else
	exit 1
fi

if [ "$CONF" = "2nodes" ]; then
	echo "ucast $ETH $ipmaster_oar" >> /etc/ha.d/ha.cf
	echo "ucast $ETH $ipbackup_oar" >> /etc/ha.d/ha.cf

	echo "node $MASTER_OAR" >> /etc/ha.d/ha.cf
	echo "node $BACKUP_OAR" >> /etc/ha.d/ha.cf
else
	echo "ucast $ETH $ipmaster_oar" >> /etc/ha.d/ha.cf
	echo "ucast $ETH $ipmaster_db" >> /etc/ha.d/ha.cf
	echo "ucast $ETH $ipbackup_oar" >> /etc/ha.d/ha.cf
	echo "ucast $ETH $ipbackup_db" >> /etc/ha.d/ha.cf

	echo "node $MASTER_OAR" >> /etc/ha.d/ha.cf
	echo "node $MASTER_DB" >> /etc/ha.d/ha.cf
	echo "node $BACKUP_OAR" >> /etc/ha.d/ha.cf
	echo "node $BACKUP_DB" >> /etc/ha.d/ha.cf
fi


echo 'crm yes' >> /etc/ha.d/ha.cf

#Don't work with release two of heartbeat, to be deleted
#echo 'auto_failback on' >> /etc/ha.d/ha.cf


#-----------------------Create file cib.xml, configure ressources for Heartbeat---------------------------------------------------

if [ "$CONF" = "4nodes" ]; then

	echo ' <cib generated="true" admin_epoch="0" have_quorum="true" ignore_dtd="false" num_peers="4" cib_feature_revision="2.0" ccm_transition="4" dc_uuid="9e4dbe89-6177-4cd1-ad9c-bce7107f6c85" epoch="72" num_updates="1" cib-last-written="Tue Jun 23 17:20:30 2009">' > /var/lib/heartbeat/crm/cib.xml
	echo '   <configuration>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     <crm_config>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <cluster_property_set id="cib-bootstrap-options">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-dc-version" name="dc-version" value="2.1.3-node: 552305612591183b1628baa5bc6e903e0f1e26a3"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-symmetric-cluster" name="symmetric-cluster" value="false"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-no-quorum-policy" name="no-quorum-policy" value="ignore"/>' >> /var/lib/heartbeat/crm/cib.xml


	echo '		<nvpair id="cib-bootstrap-options-default-resource-stickiness" name="default-resource-stickiness" value="0"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-default-resource-failure-stickiness" name="default-resource-failure-stickiness" value="0"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-stonith-enabled" name="stonith-enabled" value="false"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-stonith-action" name="stonith-action" value="reboot"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-startup-fencing" name="startup-fencing" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-stop-orphan-resources" name="stop-orphan-resources" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-stop-orphan-actions" name="stop-orphan-actions" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-remove-after-stop" name="remove-after-stop" value="false"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-short-resource-names" name="short-resource-names" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-transition-idle-timeout" name="transition-idle-timeout" value="5min"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-default-action-timeout" name="default-action-timeout" value="20s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-is-managed-default" name="is-managed-default" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-cluster-delay" name="cluster-delay" value="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-pe-error-series-max" name="pe-error-series-max" value="-1"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-pe-warn-series-max" name="pe-warn-series-max" value="-1"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<nvpair id="cib-bootstrap-options-pe-input-series-max" name="pe-input-series-max" value="-1"/>' >> /var/lib/heartbeat/crm/cib.xml




	echo '         </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       </cluster_property_set>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     </crm_config>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     <nodes/>' >> /var/lib/heartbeat/crm/cib.xml


	echo '     <resources>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <group id="Database-servers">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <meta_attributes id="Database-servers_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <nvpair name="target_role" id="Database-servers_metaattr_target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <nvpair id="Database-servers_metaattr_ordered" name="ordered" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <nvpair id="Database-servers_metaattr_collocated" name="collocated" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <primitive class="ocf" type="IPaddr2" provider="heartbeat" id="VirtualIP-database">' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '			<op id="IPaddr2_mon" interval="5s" name="monitor" timeout="5s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <instance_attributes id="VirtualIP-database_instance_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"89b87cae-b271-4d55-8881-c89508ad8451\" name=\"ip\" value=\"$IP_DB\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"bff53b6b-a11d-4cb0-8db3-24ef1b82fbb0\" name=\"nic\" value=\"$ETH\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"d6dc4cd1-b057-48be-91c7-3b733e066269\" name=\"cidr_netMASK\" value=\"$MASK\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </instance_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <meta_attributes id="VirtualIP-database_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '               <nvpair name="target_role" id="VirtualIP-database_metaattr_target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <primitive id="DRBD-disk" class="heartbeat" type="drbddisk" provider="heartbeat">' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		   <op id="DRBD-disk_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 <instance_attributes id="DRBD-disk_inst_attr">' >> /var/lib/heartbeat/crm/cib.xml
        echo '     	   <attributes>' >> /var/lib/heartbeat/crm/cib.xml
        echo '       	     <nvpair id="DRBD-disk_attr_1" name="1" value="mysql"/>' >> /var/lib/heartbeat/crm/cib.xml
        echo '     	   </attributes>' >> /var/lib/heartbeat/crm/cib.xml
        echo '   	 </instance_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <meta_attributes id="DRBD-disk_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '               <nvpair id="DRBD-disk_metaattr_target_role" name="target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <primitive id="Filesystem" class="ocf" type="Filesystem" provider="heartbeat">' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		   <op id="Filesystem_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <instance_attributes id="Filesystem_instance_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"29b7a79c-ad8f-47ef-91dd-610292acac10\" name=\"device\" value=\"$DRBDPARTITION\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"639a3cc9-8df6-497a-b874-f04b72da5577\" name=\"directory\" value=\"$DRBDDATA\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"1e59d136-4bc7-4f6c-9eb4-a62e06ec48d1\" name=\"fstype\" value=\"$FSTYPE\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </instance_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <meta_attributes id="Filesystem_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '               <nvpair id="Filesystem_metaattr_target_role" name="target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	if [ "$BD" = "mysql" ]; then
		echo '         <primitive id="database" class="lsb" type="mysqld" provider="heartbeat">' >> /var/lib/heartbeat/crm/cib.xml
		echo '		 <operations>' >> /var/lib/heartbeat/crm/cib.xml
		echo '		   <op id="database_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
		echo '		 </operations>' >> /var/lib/heartbeat/crm/cib.xml
		echo '           <meta_attributes id="database_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
		echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '               <nvpair id="database_metaattr_target_role" name="target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
		echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '           </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	elif [ "$BD" = "postgresql" ]; then
		echo "		<primitive id=\"database\" class=\"lsb\" type=\"$BD-"$PGVERSION"ha\" provider=\"heartbeat\"" >> /var/lib/heartbeat/crm/cib.xml
		echo '		 <operations>' >> /var/lib/heartbeat/crm/cib.xml
		echo '		   <op id="database_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
		echo '		 </operations>' >> /var/lib/heartbeat/crm/cib.xml
		echo '           <meta_attributes id="database_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
		echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '               <nvpair id="database_metaattr_target_role" name="target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
		echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '           </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	else
		exit 1
	fi
	echo '       </group>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <group id="OAR-servers">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <meta_attributes id="OAR-servers_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <nvpair id="OAR-servers_metaattr_target_role" name="target_role" value="stopped"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <nvpair id="OAR-servers_metaattr_ordered" name="ordered" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <nvpair id="OAR-servers_metaattr_collocated" name="collocated" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <primitive id="VirtualIP-OAR-server" class="ocf" type="IPaddr2" provider="heartbeat">' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		    <op id="VirtualIP-OAR-server_mon" interval="5s" name="monitor" timeout="5s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '	   	 </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <instance_attributes id="VirtualIP-OAR-server_instance_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"bb615f47-387e-46cb-945f-8757d494791b\" name=\"ip\" value=\"$IP\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"6fe16a0e-c414-4a5b-8e5f-f0c48b369770\" name=\"nic\" value=\"$ETH\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"b25acc28-5186-4a22-9433-5347017cdc71\" name=\"cidr_netMASK\" value=\"$MASK\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </instance_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <meta_attributes id="VirtualIP-OAR-server_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '               <nvpair id="VirtualIP-OAR-server_metaattr_target_role" name="target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <primitive id="OAR-server" class="lsb" type="oar-server" provider="heartbeat">' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		   <op id="OAR-server_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		 </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <meta_attributes id="OAR-server_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '               <nvpair id="OAR-server_metaattr_target_role" name="target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       </group>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     </resources>' >> /var/lib/heartbeat/crm/cib.xml



	echo '     <constraints>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <rsc_order type="before" id="Order" from="Database-servers" to="OAR-servers"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <rsc_location id="location-Database" rsc="Database-servers">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <rule id="prefered_location-Database" score="0">' >> /var/lib/heartbeat/crm/cib.xml
	echo "           <expression attribute=\"#uname\" id=\"f968a0dd-59dd-4d02-b54a-36c7139afa13\" operation=\"ne\" value=\"$MASTER_OAR\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "           <expression attribute=\"#uname\" id=\"0ef6e38b-6a34-4e23-bc22-9dccfacc95b6\" operation=\"ne\" value=\"$BACKUP_OAR\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '         </rule>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       </rsc_location>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <rsc_location id="location-OAR" rsc="OAR-servers">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <rule id="prefered_location-OAR" score="0">' >> /var/lib/heartbeat/crm/cib.xml
	echo "           <expression attribute=\"#uname\" id=\"4d2c21d8-aea7-460b-bfeb-cd6d22e4a17e\" operation=\"ne\" value=\"$MASTER_DB\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "           <expression attribute=\"#uname\" id=\"3292b1b4-04cb-4650-b6e0-2e4428c837a8\" operation=\"ne\" value=\"$BACKUP_DB\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '         </rule>' >> /var/lib/heartbeat/crm/cib.xml
	echo '      </rsc_location>' >> /var/lib/heartbeat/crm/cib.xml
	echo '	    <rsc_location id="location_Master-OAR" rsc="OAR-servers">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <rule id="prefered_location_Master-OAR" score="INFINITY">' >> /var/lib/heartbeat/crm/cib.xml
	echo "           <expression attribute=\"#uname\" id=\"37a60f84-c7ed-4e4a-835a-55382961c990\" operation=\"eq\" value=\"$MASTER_OAR\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '         </rule>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       </rsc_location>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		<rsc_location id="location_Master-Database" rsc="Database-servers">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <rule id="prefered_location_Master-Database" score="INFINITY">' >> /var/lib/heartbeat/crm/cib.xml
	echo "           <expression attribute=\"#uname\" id=\"37a78f84-c7ed-4e4a-835a-54382451c990\" operation=\"eq\" value=\"$MASTER_DB\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '         </rule>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       </rsc_location>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     </constraints>' >> /var/lib/heartbeat/crm/cib.xml
	echo '   </configuration>' >> /var/lib/heartbeat/crm/cib.xml
	echo ' </cib>' >> /var/lib/heartbeat/crm/cib.xml




else #2 nodes hearbeat configuration





	echo '	<cib admin_epoch="0" have_quorum="true" ignore_dtd="false" ccm_transition="2" num_peers="2" cib_feature_revision="2.0" generated="true" dc_uuid="c108e814-aa1a-4ffe-90fa-c6713accb0ad" epoch="4" num_updates="4" cib-last-written="Fri Jul  3 16:29:09 2009">' > /var/lib/heartbeat/crm/cib.xml
	echo '   <configuration>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     <crm_config>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <cluster_property_set id="cib-bootstrap-options">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-symmetric-cluster" name="symmetric-cluster" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-no-quorum-policy" name="no-quorum-policy" value="stop"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-default-resource-stickiness" name="default-resource-stickiness" value="0"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-default-resource-failure-stickiness" name="default-resource-failure-stickiness" value="0"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-stonith-enabled" name="stonith-enabled" value="false"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-stonith-action" name="stonith-action" value="reboot"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-startup-fencing" name="startup-fencing" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-stop-orphan-resources" name="stop-orphan-resources" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-stop-orphan-actions" name="stop-orphan-actions" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-remove-after-stop" name="remove-after-stop" value="false"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-short-resource-names" name="short-resource-names" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-transition-idle-timeout" name="transition-idle-timeout" value="5min"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-default-action-timeout" name="default-action-timeout" value="20s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-is-managed-default" name="is-managed-default" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-cluster-delay" name="cluster-delay" value="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-pe-error-series-max" name="pe-error-series-max" value="-1"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-pe-warn-series-max" name="pe-warn-series-max" value="-1"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-pe-input-series-max" name="pe-input-series-max" value="-1"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <nvpair id="cib-bootstrap-options-dc-version" name="dc-version" value="2.1.3-node: 552305612591183b1628baa5bc6e903e0f1e26a3"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       </cluster_property_set>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     </crm_config>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     <nodes/>' >> /var/lib/heartbeat/crm/cib.xml




	echo '     <resources>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <group id="group_1">' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <meta_attributes id="group_1_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '		   <nvpair id="group__metaattr_target_role" name="target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
        echo '     	   <nvpair id="group__metaattr_collocated" name="collocated" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <nvpair id="group_1_metaattr_ordered" name="ordered" value="true"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <primitive class="ocf" id="VirtualIP" provider="heartbeat" type="IPaddr2">' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <op id="VirtualIP_mon" interval="5s" name="monitor" timeout="5s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <instance_attributes id="VirtualIP_inst_attr">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"VirtualIP_attr_0\" name=\"ip\" value=\"$IP\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"VirtualIP_attr_1\" name=\"nic\" value=\"$ETH\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"VirtualIP_attr_2\" name=\"cidr_netmask\" value=\"$MASK\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </instance_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <primitive class="heartbeat" id="DRBD-disk" provider="heartbeat" type="drbddisk">' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <op id="DRBD-disk_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <instance_attributes id="DRBD-diskinst_attr">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '               <nvpair id="DRBD-disk_attr_1" name="1" value="mysql"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </instance_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         <primitive class="ocf" id="Filesystem" provider="heartbeat" type="Filesystem">' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <op id="Filesystem_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <instance_attributes id="Filesystem_inst_attr">' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"Filesystem_attr_0\" name=\"device\" value=\"$DRBDPARTITION\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"Filesystem_attr_1\" name=\"directory\" value=\"$DRBDDATA\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo "               <nvpair id=\"Filesystem_attr_2\" name=\"fstype\" value=\"$FSTYPE\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </instance_attributes>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	if [ "$BD" = "mysql" ]; then
		echo '         <primitive id="database" class="lsb" type="mysqld" provider="heartbeat">' >> /var/lib/heartbeat/crm/cib.xml
		echo '           <operations>' >> /var/lib/heartbeat/crm/cib.xml
		echo '             <op id="database_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
		echo '           </operations>' >> /var/lib/heartbeat/crm/cib.xml
		echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	elif [ "$BD" = "postgresql" ]; then
		echo "		<primitive id=\"database\" class=\"lsb\" type=\"$BD-"$PGVERSION"ha\" provider=\"heartbeat\"" >> /var/lib/heartbeat/crm/cib.xml
		echo '		 <operations>' >> /var/lib/heartbeat/crm/cib.xml
		echo '		   <op id="database_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
		echo '		 </operations>' >> /var/lib/heartbeat/crm/cib.xml
		echo '           <meta_attributes id="database_meta_attrs">' >> /var/lib/heartbeat/crm/cib.xml
		echo '             <attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '               <nvpair id="database_metaattr_target_role" name="target_role" value="started"/>' >> /var/lib/heartbeat/crm/cib.xml
		echo '             </attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '           </meta_attributes>' >> /var/lib/heartbeat/crm/cib.xml
		echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	else
		exit 1
	fi
	echo '         <primitive class="lsb" id="oar-server" provider="heartbeat" type="oar-server">' >> /var/lib/heartbeat/crm/cib.xml
	echo '           <operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '             <op id="oar-server_mon" interval="120s" name="monitor" timeout="60s"/>' >> /var/lib/heartbeat/crm/cib.xml
	echo '           </operations>' >> /var/lib/heartbeat/crm/cib.xml
	echo '         </primitive>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       </group>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     </resources>' >> /var/lib/heartbeat/crm/cib.xml




	echo '     <constraints>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       <rsc_location id="rsc_location_group_1" rsc="group_1">' >> /var/lib/heartbeat/crm/cib.xml
	echo '        <rule id="prefered_location_group_1" score="100">' >> /var/lib/heartbeat/crm/cib.xml
	echo "           <expression attribute=\"#uname\" id=\"prefered_location_group_1_expr\" operation=\"eq\" value=\"$MASTER_OAR\"/>" >> /var/lib/heartbeat/crm/cib.xml
	echo '         </rule>' >> /var/lib/heartbeat/crm/cib.xml
	echo '       </rsc_location>' >> /var/lib/heartbeat/crm/cib.xml
	echo '     </constraints>' >> /var/lib/heartbeat/crm/cib.xml
	echo '   </configuration>' >> /var/lib/heartbeat/crm/cib.xml
	echo ' </cib>' >> /var/lib/heartbeat/crm/cib.xml



fi




chown hacluster:haclient /var/lib/heartbeat/crm/cib.xml
chmod 0600 /var/lib/heartbeat/crm/cib.xml


#-----------------------Modify OAR service, LSB compatible---------------------------------------------------

if [ "$ISDATABASE" = "n" ]||[ "$CONF" = "2nodes" ]; then
	
	echo '#!/bin/bash' > /etc/init.d/oar-server
	echo '#' >> /etc/init.d/oar-server
	echo '# oar-server          Start/Stop the oar server daemon.' >> /etc/init.d/oar-server
	echo '#' >> /etc/init.d/oar-server
	echo '# chkconfig: 2345 99 01' >> /etc/init.d/oar-server
	echo '# description: OAR is a resource manager (or batch scheduler) for large computing clusters.' >> /etc/init.d/oar-server
	echo '# processname: Almighty' >> /etc/init.d/oar-server
	echo '# config: /etc/oar/oar.conf' >> /etc/init.d/oar-server
	echo '# pidfile: /var/run/oar-server.pid' >> /etc/init.d/oar-server

	echo 'RETVAL=0' >> /etc/init.d/oar-server
	echo 'DAEMON=/usr/sbin/oar-server' >> /etc/init.d/oar-server
	echo 'DESC=oar-server' >> /etc/init.d/oar-server
	echo 'PIDFILE=/var/run/oar-server.pid' >> /etc/init.d/oar-server
	echo 'CONFIG=/etc/oar/oar.conf' >> /etc/init.d/oar-server

	echo 'test -x $DAEMON || exit 0' >> /etc/init.d/oar-server

	echo '# Source function library.' >> /etc/init.d/oar-server
	echo '. /etc/init.d/functions' >> /etc/init.d/oar-server

	echo '# Set sysconfig settings' >> /etc/init.d/oar-server
	echo '[ -f /etc/sysconfig/oar-server ] && . /etc/sysconfig/oar-server' >> /etc/init.d/oar-server

	echo 'check_sql() {' >> /etc/init.d/oar-server
	echo '        echo -n "Checking oar SQL base: "' >> /etc/init.d/oar-server
	echo '	if [ -f $CONFIG ] && . $CONFIG ; then' >> /etc/init.d/oar-server
	echo '           :' >> /etc/init.d/oar-server
	echo '        else' >> /etc/init.d/oar-server
	echo '          echo -n "Error loading $CONFIG"' >> /etc/init.d/oar-server
	echo '          failure' >> /etc/init.d/oar-server
	echo '          exit 1' >> /etc/init.d/oar-server
	echo '        fi' >> /etc/init.d/oar-server
	echo '        if [ "$DB_TYPE" = "mysql" -o "$DB_TYPE" = "Pg" ] ; then' >> /etc/init.d/oar-server
	echo '          export PERL5LIB="/usr/lib/oar"' >> /etc/init.d/oar-server
	echo '          export OARCONFFILE="$CONFIG"' >> /etc/init.d/oar-server
	echo '          perl <<EOS && success || failure ' >> /etc/init.d/oar-server
	echo '          use oar_iolib;' >> /etc/init.d/oar-server
	echo '	  \$Db_type="$DB_TYPE";' >> /etc/init.d/oar-server
	echo '          if (OAR::IO::connect_db("$DB_HOSTNAME","$DB_PORT","$DB_BASE_NAME","$DB_BASE_LOGIN","$DB_BASE_PASSWD",0)) { exit 0;echo ok; }' >> /etc/init.d/oar-server
	echo '          else { exit 1; }' >> /etc/init.d/oar-server
	echo 'EOS' >> /etc/init.d/oar-server
	echo '        else' >> /etc/init.d/oar-server
	echo '          echo -n "Unknown $DB_TYPE database type"' >> /etc/init.d/oar-server
	echo '          failure' >> /etc/init.d/oar-server
	echo '          exit 1' >> /etc/init.d/oar-server
	echo '        fi' >> /etc/init.d/oar-server
	echo '}' >> /etc/init.d/oar-server

	echo 'sql_init_error_msg (){' >> /etc/init.d/oar-server
	echo '  echo' >> /etc/init.d/oar-server
	echo '  echo "OAR database seems to be unreachable." ' >> /etc/init.d/oar-server
	echo '  echo "Did you forget to initialize it or to configure the oar.conf file?"' >> /etc/init.d/oar-server
	echo '  echo "See http://oar.imag.fr/docs/manual.html#configuration-of-the-cluster for more infos"' >> /etc/init.d/oar-server
	echo '  exit 1' >> /etc/init.d/oar-server
	echo '}' >> /etc/init.d/oar-server

	echo 'start() {' >> /etc/init.d/oar-server
	echo '        echo -n "Starting $DESC: "' >> /etc/init.d/oar-server
	echo '        daemon $DAEMON $DAEMON_OPTS && success || failure' >> /etc/init.d/oar-server
	echo '        RETVAL=$?' >> /etc/init.d/oar-server
	echo '	echo ' >> /etc/init.d/oar-server
	echo '}' >> /etc/init.d/oar-server

	echo 'stop() {' >> /etc/init.d/oar-server
	echo '        echo -n "Stopping $DESC: "' >> /etc/init.d/oar-server
	echo '        if [ -n "`pidfileofproc $DAEMON`" ]; then' >> /etc/init.d/oar-server
	echo '            killproc $DAEMON' >> /etc/init.d/oar-server
	echo '            sleep 1' >> /etc/init.d/oar-server
	echo '            killall Almighty 2>/dev/null' >> /etc/init.d/oar-server
	echo '            sleep 1' >> /etc/init.d/oar-server
	echo '            killall -9 Almighty 2>/dev/null' >> /etc/init.d/oar-server
	echo '            RETVAL=0' >> /etc/init.d/oar-server
	echo '        else' >> /etc/init.d/oar-server
	echo '            failure $"Stopping $DESC"' >> /etc/init.d/oar-server
	echo '            RETVAL=$?' >> /etc/init.d/oar-server
	echo '            if [ `ps -ef | grep -v "grep" | grep Almighty | wc -l` -eq 0 ]; then' >> /etc/init.d/oar-server
	echo '                RETVAL=0' >> /etc/init.d/oar-server
	echo '            fi' >> /etc/init.d/oar-server
	echo '        fi' >> /etc/init.d/oar-server
	echo '        echo ' >> /etc/init.d/oar-server
	echo '}' >> /etc/init.d/oar-server

	echo 'case "$1" in' >> /etc/init.d/oar-server
	echo '  start)' >> /etc/init.d/oar-server
	echo '        check_sql || sql_init_error_msg' >> /etc/init.d/oar-server
	echo '        start' >> /etc/init.d/oar-server
	echo '        ;;' >> /etc/init.d/oar-server
	echo '  stop)' >> /etc/init.d/oar-server
	echo '        stop' >> /etc/init.d/oar-server
	echo '        ;;' >> /etc/init.d/oar-server
	echo '  restart|force-reload|restart)' >> /etc/init.d/oar-server
	echo '        stop' >> /etc/init.d/oar-server
	echo '        sleep 1' >> /etc/init.d/oar-server
	echo '        start' >> /etc/init.d/oar-server
	echo '        ;;' >> /etc/init.d/oar-server
	echo '  status)' >> /etc/init.d/oar-server
	echo '        status $DAEMON' >> /etc/init.d/oar-server
	echo '	RETVAL=$?' >> /etc/init.d/oar-server
	echo '        ;;' >> /etc/init.d/oar-server
	echo '  *)' >> /etc/init.d/oar-server
	echo '        echo $"Usage: $0 {start|stop|status|restart}"' >> /etc/init.d/oar-server
	echo '        RETVAL=3' >> /etc/init.d/oar-server
	echo 'esac' >> /etc/init.d/oar-server
	echo 'exit $RETVAL' >> /etc/init.d/oar-server


	chmod 755 /etc/init.d/oar-server
fi


#-----------------------Modify mysql service, for return 0 if mysql is stopped and you try to stop it---------------------------------------------------

if [ "$ISDATABASE" = "y" ]; then

	sed -e "s/stop(){/stop(){\n\tstatus mysqld\n\tif [ \$? -eq 3 ]; then\n\t\taction \$\"Stopping \$prog: \" \/bin\/true\n\t\texit 0\n\tfi\n/g" /etc/init.d/mysqld > /etc/init.d/mysqld.tmp && mv -f /etc/init.d/mysqld.tmp /etc/init.d/mysqld

	chmod 755 /etc/init.d/mysqld

fi

#-----------------------OAR configuration with remote database (Virtual IP) ---------------------------------------------------

#Detach job from server
detach_job=$(cat /etc/oar/oar.conf | grep DETACH_JOB_FROM_SERVER=)
sed -e "s/$detach_job/DETACH_JOB_FROM_SERVER=\"1\"/g" /etc/oar/oar.conf > /etc/oar/oar.conf.tmp && mv -f /etc/oar/oar.conf.tmp /etc/oar/oar.conf

serveur_hostname=$(cat /etc/oar/oar.conf | grep SERVER_HOSTNAME=)
sed -e "s/$serveur_hostname/SERVER_HOSTNAME=\"$IP\"/g" /etc/oar/oar.conf > /etc/oar/oar.conf.tmp && mv -f /etc/oar/oar.conf.tmp /etc/oar/oar.conf

if [ "$CONF" = "4nodes" ]; then
	db_hostname=$(cat /etc/oar/oar.conf | grep DB_HOSTNAME=)
	sed -e "s/$db_hostname/DB_HOSTNAME=\"$IP_DB\"/g" /etc/oar/oar.conf > /etc/oar/oar.conf.tmp && mv -f /etc/oar/oar.conf.tmp /etc/oar/oar.conf

elif [ "$CONF" = "2nodes" ]; then 	#2nodes configuration, very important, because oarexec must contact oar-server after fail-over
	db_hostname=$(cat /etc/oar/oar.conf | grep DB_HOSTNAME=)
	sed -e "s/$db_hostname/DB_HOSTNAME=\"$IP\"/g" /etc/oar/oar.conf > /etc/oar/oar.conf.tmp && mv -f /etc/oar/oar.conf.tmp /etc/oar/oar.conf

fi

#-----------------------Get database data path for DRBD configuration, and change this path---------------------------------------------------
if [ "$ISDATABASE" = "y" ]; then
	if [ "$BD" = "mysql" ]; then
		datadirold=$(cat /etc/my.cnf | grep datadir)
		datadiroldn=$(echo $datadirold | sed 's/\//\\\//g')
		mysqldirold=$(echo $datadirold | cut -d "=" -f2)
		mysqldiroldn=$(echo $mysqldirold | sed 's/\//\\\//g')
		#Save mysql old configuration
		cp /etc/my.cnf /etc/my.cnf.backup
		sed -e "s/$datadiroldn/datadir=\/mnt\/drbddata\/mysql/g" /etc/my.cnf > /etc/my.cnf.tmp && mv -f /etc/my.cnf.tmp /etc/my.cnf 
		sed -e "s/bind-address/# bind-address/g" /etc/my.cnf > /etc/my.cnf.tmp && mv -f /etc/my.cnf.tmp /etc/my.cnf
	elif [ "$BD" = "postgresql" ]; then
		postgresdirold=$(cat /etc/$BD/$PGVERSION/main/postgresql.conf | grep data_directory | cut -d "'" -f2)
		postgresdiroldn=$(echo $postgresdirold | sed 's/\//\\\//g')
		#Save mysql old configuration
		cp /etc/$BD/$PGVERSION/main/postgresql.conf /etc/$BD/$PGVERSION/main/postgresql.conf.backup
		sed -e "s/$postgresdiroldn/\/mnt\/drbddata\/main/g" /etc/$BD/$PGVERSION/main/postgresql.conf > /etc/$BD/$PGVERSION/main/postgresql.conf.tmp && mv -f /etc/$BD/$PGVERSION/main/postgresql.conf.tmp /etc/$BD/$PGVERSION/main/postgresql.conf

		#to be deleted in the future
		sed -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/$BD/$PGVERSION/main/postgresql.conf > /etc/$BD/$PGVERSION/main/postgresql.conf.tmp && mv -f /etc/$BD/$PGVERSION/main/postgresql.conf.tmp /etc/$BD/$PGVERSION/main/postgresql.conf

	else
		exit 1
	fi
fi



#-----------------------DRBD Configuration---------------------------------------------------

if [ "$ISDATABASE" = "y" ]; then
	echo 'global { usage-count no; }' > /etc/drbd.conf

	echo 'resource mysql {' >> /etc/drbd.conf
	echo '	# Three protocol :' >> /etc/drbd.conf
	echo '	# A : write ACK (on master)' >> /etc/drbd.conf
	echo '	# is send when data was transmitted on master disk and sent to slave' >> /etc/drbd.conf
	echo '	# B : write ACK (on master)' >> /etc/drbd.conf
	echo '	# is send when data was transmitted on master disk and received by slave' >> /etc/drbd.conf
	echo '	# C : write ACK (on master)' >> /etc/drbd.conf
	echo '	# is send when data was transmitted on master disk and slave disk' >> /etc/drbd.conf
	echo '	protocol C;' >> /etc/drbd.conf

	echo '	startup {' >> /etc/drbd.conf
	echo '		# when the node start, wait 2 minutes others nodes' >> /etc/drbd.conf
	echo '		wfc-timeout 120;' >> /etc/drbd.conf
	echo '	}' >> /etc/drbd.conf

	echo '	# If io-error, freeze node' >> /etc/drbd.conf
	echo '	disk {' >> /etc/drbd.conf
	echo '		on-io-error detach;' >> /etc/drbd.conf
	echo '	}' >> /etc/drbd.conf

	echo '	syncer {' >> /etc/drbd.conf
	echo '		rate 700000K;' >> /etc/drbd.conf
	echo '		# Rate of synchronization. max 700000K' >> /etc/drbd.conf
	echo '		al-extents 257;' >> /etc/drbd.conf
	echo '		# al-extent is the size of the « hot-area »' >> /etc/drbd.conf
	echo '	}' >> /etc/drbd.conf

	echo "	on $MASTER_DB {" >> /etc/drbd.conf
	echo "		device $DRBDPARTITION;" >> /etc/drbd.conf
	echo "		disk $DISKPARTITION;" >> /etc/drbd.conf
	echo "		address $ipmaster_db:$DBRDPORT;" >> /etc/drbd.conf
	echo '		meta-disk internal;' >> /etc/drbd.conf
	echo '	}' >> /etc/drbd.conf


	echo "	on $BACKUP_DB {" >> /etc/drbd.conf
	echo "		device $DRBDPARTITION;" >> /etc/drbd.conf
	echo "		disk $DISKPARTITION;" >> /etc/drbd.conf
	echo "		address $ipbackup_db:$DBRDPORT;" >> /etc/drbd.conf
	echo '		meta-disk internal;' >> /etc/drbd.conf
	echo '	}' >> /etc/drbd.conf	

	echo '	net {' >> /etc/drbd.conf
	echo "              #cram-hmac-alg \"sha1\"; " >> /etc/drbd.conf
	echo "              #shared-secret \"123456\";" >> /etc/drbd.conf
	echo " 		    after-sb-0pri discard-younger-primary;" >> /etc/drbd.conf
  	echo " 		    after-sb-1pri consensus;" >> /etc/drbd.conf
  	echo " 		    after-sb-2pri call-pri-lost-after-sb;" >> /etc/drbd.conf
	echo '              #rr-conflict violently;' >> /etc/drbd.conf
	echo '  }' >> /etc/drbd.conf

	echo '	handlers {' >> /etc/drbd.conf
	echo '		split-brain "echo Splitbraindetected >> /var/log/drbd-log";' >> /etc/drbd.conf
	echo '		pri-lost-after-sb "echo pri-lost-after-sb >> /var/log/drbd-log";' >> /etc/drbd.conf
	echo '	}' >> /etc/drbd.conf


	echo '}' >> /etc/drbd.conf

fi		
	

#-----------------------Create the device for DRBD Data---------------------------------------------------


if [ "$ISDATABASE" = "y" ]; then

	modprobe drbd

	if [ "$USEFILEPARTITION" = "y" ]; then
		#Create Virtual partition
		dd if=/dev/zero of=$IMAGE bs=1M count=$SIZE
		losetup $DISKPARTITION $IMAGE
		mkfs -t $FSTYPE $DISKPARTITION
		shred -zvf -n 1 $DISKPARTITION	
	fi

	if [ ! -e $DRBDPARTITION ]; then
		mknod $DRBDPARTITION b 147 0
	fi

	#Create metadata
	drbdadm create-md all

	service drbd start

	#drbdadm up all

	if [ ! -e $DRBDDATA ]; then
		mkdir $DRBDDATA
	fi

	#On the master
	if [ "$ISMASTER" = "y" ]&&[ "$ISDATABASE" = "y" ]; then
		#The master launch syncrhonization
		drbdadm -- --overwrite-data-of-peer primary all

		mkfs -t $FSTYPE $DRBDPARTITION	
		mount $DRBDPARTITION $DRBDDATA
	
		if [ "$BD" = "mysql" ]; then
			cp -r $mysqldirold $DRBDDATA
			chown -R mysql:mysql $DRBDDATA/mysql
		elif [ "$BD" = "postgresql" ]; then
			cp -r $postgresdirold $DRBDDATA
			chown -R postgres:postgres $DRBDDATA/main
		else
			exit 1
		fi
		
		#After data copy, put the master in secondary state, heartbeat will choose the primary
		umount $DRBDDATA
		drbdadm secondary all

		#Delete auto fsck
		tune2fs -c 0 $DISKPARTITION
	
	fi

fi


#-----------------------Remove auto launch---------------------------------------------------

chkconfig --add heartbeat

if [ "$ISDATABASE" = "y" ]; then
	if [ "$BD" = "mysql" ]; then
		chkconfig $BD"d" off
	elif [ "$BD" = "postgresql" ]; then
		#update-rc.d -f $BD"-"$PGVERSION remove
		echo "not implemented"
	else
		exit 1
	fi
fi
if [ "$ISDATABASE" = "n" ]||[ "$CONF" = "2nodes" ] ; then
	chkconfig oar-server off
fi


#-----------------------Create service for auto associate $LOOPBACK with $IMAGE-----------------------------

if [ "$USEFILEPARTITION" = "y" ]; then

	echo '#!/bin/bash' > /etc/init.d/active-loop
	echo '# chkconfig: 2345 60 01' >> /etc/init.d/active-loop
	echo '# description: Auto associate loopback with the file image.img' >> /etc/init.d/active-loop
	echo 'case "$1" in' >> /etc/init.d/active-loop
	echo '  start|"") ' >> /etc/init.d/active-loop
	echo '        losetup /dev/loop0 /image.img' >> /etc/init.d/active-loop
	echo '	echo "Start OK"' >> /etc/init.d/active-loop
	echo '        ;;' >> /etc/init.d/active-loop
	echo '  stop)' >> /etc/init.d/active-loop
	echo '	losetup -d /dev/loop0' >> /etc/init.d/active-loop 
	echo '	echo "Stop OK"' >> /etc/init.d/active-loop
	echo '	;;' >> /etc/init.d/active-loop
	echo '  *)' >> /etc/init.d/active-loop
	echo '        echo "Usage: active-loop [start|stop]" >&2' >> /etc/init.d/active-loop
	echo '        exit 3' >> /etc/init.d/active-loop
	echo '        ;;' >> /etc/init.d/active-loop
	echo 'esac' >> /etc/init.d/active-loop

	#change rights
	chmod +x /etc/init.d/active-loop

	#Auto start, before DRBD --> 60
	chkconfig --add active-loop
	chkconfig --level 2345 active-loop on

fi


#-----------------------Launch heartbeat service---------------------------------------------------

#to be deleted, because can fail with DRBD
#/etc/init.d/heartbeat start

#-----------------------Add cgi script for monitor heartbeat---------------------------------------------------

if [ "$CGI" = "y" ]; then	

	yum -y install httpd

	echo '#!/bin/bash' > /var/www/cgi-bin/ha-status.cgi
	echo 'sudo /usr/sbin/crm_mon -w' >> /var/www/cgi-bin/ha-status.cgi

	chmod 755 /var/www/cgi-bin/ha-status.cgi

	echo 'apache ALL=NOPASSWD:/usr/sbin/crm_mon' >> /etc/sudoers

	#enable sudo in tty mode
	tempo=$(cat /etc/sudoers | grep requiretty)
	sed -e "s/$tempo/#$tempo/g" /etc/sudoers > /etc/sudoers.tmp && mv -f /etc/sudoers.tmp /etc/sudoers

	service httpd start

fi


#-----------------------End of script---------------------------------------------------


