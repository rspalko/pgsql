#!/bin/bash

# Preferred installation settings
INSTALLROOT=/opt
PGBASE="${INSTALLROOT}/pgsql"
PGDATA=${PGBASE}/pgdata

if [ ! -d "${INSTALLROOT}" ]; then
	mkdir "${INSTALLROOT}"
	chmod 755 "${INSTALLROOT}"
fi

# Files to edit
POSTGRESQL_CONF=${PGDATA}/postgresql.conf
RECOVERY_CONF=${PGDATA}/recovery.conf

PRIMARY=""

# Source /etc/profile to set PGSQL Environment in case the user does not relogin after RPM install
source /etc/profile

# Need to restrict permissions on the synced data
umask 0077

service postgresql status >& /dev/null
if [ $? -eq 0 ]; then
	echo "Postgresql status script returned running status, this script is for initial configuration only"
	exit 100
fi

read -p "List hostname or IP address for primary server that is configured: " PRIMARY

if [ $PRIMARY ]; then
	pg_basebackup -D "${PGDATA}" -R -x -P -v -h ${PRIMARY} -p 5432 -U postgres
	# ADD THE REPLICATION SLOT (MUST MATCH PRIMARY SCRIPT)
	echo "primary_slot_name = 'postgres'" >> "${RECOVERY_CONF}"
	HOT_STANDBY_INSERT="hot_standby ="
	HOT_STANDBY=on
	sed -i "/${HOT_STANDBY_INSERT}/i ${HOT_STANDBY_INSERT}${HOT_STANDBY}" "${POSTGRESQL_CONF}"
	chown -R postgres "${PGBASE}"
	service postgresql start
else
	echo "YOU MUST SPECIFY A HOSTNAME OR IP ADDRESS FOR PRIMARY SERVER, EXITING SCRIPT"
	exit 100
fi
