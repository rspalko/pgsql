#!/bin/bash

#########################################################################
# BEGIN SET GLOBAL VARIABLES
#########################################################################
# Passwords
PGPASSWORD=postgres

# Preferred installation settings
INSTALLROOT=/opt
PGBASE="${INSTALLROOT}/pgsql"
PGDBS_DEFAULT="omardb-2.0-prod"
PGDATA=${PGBASE}/pgdata

# Files to edit
POSTGRESQL_CONF=${PGDATA}/postgresql.conf
PGHBA_CONF=${PGDATA}/pg_hba.conf

# REPLICATION VARIABLES
STANDBY_IPS=""

# MISCELLANEOUS
RESTART_SLEEP=3
SCHEMA=/usr/local/pgsql/share/schema.sql
INDICES=/usr/local/pgsql/share/indices.sql
DB_SETTINGS=/usr/local/pgsql/bin/db_settings.sh
#########################################################################
# END SET GLOBAL VARIABLES
#########################################################################

#########################################################################
# BEGIN FUNCTION DEFINITIONS
#########################################################################
mkPgdataDir()
{
	mkdir -p "${PGBASE}"
	chown postgres "${PGBASE}"
	chmod 700 "${PGBASE}"

	mkdir "${PGDATA}"
	chown postgres "${PGDATA}"
	chmod 700 "${PGDATA}"
}

getDBPass()
{
	case $1 in
		omardb-2.0-prod)
			echo $PGPASSWORD
			;;
		omardb-elevation)
			echo $PGPASSWORD
			;;
		omardb-opir)
			echo $PGPASSWORD
			;;
		*)
			echo $PGPASSWORD
			;;
	esac
}

appendLine()
{
	sed -i "/${1}/a ${2}" "${3}"
}

deleteLine()
{
	sed -i "/${1}/d" "${2}"

}

insertLine()
{
	sed -i "/${1}/i ${2}" "${3}"
}

replace()
{
	sed -i "s/${1}/${2}/" "${3}"
}

replaceAll()
{
	sed -i "s/${1}/${2}/g" "${3}"
}

replaceConfSetting()
{
	sed -i "/^${1} = ${2}/ !s/^${1} =/${1} = ${2} #PREVIOUS VALUE# /" "${3}"
	sed -i "/^#${1} = / s/^#${1} =/${1} = ${2} #PREVIOUS VALUE# /" "${3}"
}

replaceLine()
{
	sed -i "s/.*${1}.*/${2}/" "${3}"
}

###################################################################################
# END FUNCTION DEFINITIONS
###################################################################################

###################################################################################
# BEGIN SETUP ENVIRONMENT
###################################################################################
# Source /etc/profile to set PGSQL Environment in case the user does not relogin after RPM install
source /etc/profile

# Postgres perms must be locked down to allow startup
umask 0077
###################################################################################
# END SETUP ENVIRONMENT
###################################################################################

###################################################################################
# BEGIN GET USER INPUT
###################################################################################
service postgresql status >& /dev/null
if [ $? -eq 0 ]; then 
	echo "Postgresql status script returned running status, this script is for initial configuration only"
	exit 100
fi

# This must be done after the previous status check as we are expecting an error code for that since postgres is not running
# Exit on error
set -e

read -p "Select database base directory location: (Default is $PGBASE): " $PG_DIR
PG_DIR=${PG_DIR:-$PGBASE}
PGBASE=${PG_DIR}

if [ -e "$PGBASE" ] ; then
	echo "DESTINATION DATABASE LOCATION ALREADY EXISTS AT ${PGBASE}"
	echo "THIS SCRIPT IN ONLY INTENDED FOR ONE TIME USE DURING INSTALLATION, PLEASE BACKUP AND SAVE DATA AT ${PGBASE} BEFORE REMOVING"
	echo "EXITING SCRIPT, TRY AGAIN AFTER YOU CLEAN UP OLD PGDATA"
	exit 1
fi

read -p "List databases to build: (Default is ${PGDBS_DEFAULT}): " DATABASES
DATABASES=${DATABASES:-$PGDBS_DEFAULT}
DBARRAY=(${DATABASES})
NUMDBS=${#DBARRAY[@]}

read -p "List IP address for standby intefaces separated by spaces (return to skip failover configuration): " STANDBY_IPS

read -p "Specify full path of schema file to load (Default is ${SCEHEMA}): " USER_SCHEMA
SCHEMA=${USER_SCHEMA:-$SCHEMA}
###################################################################################
# END GET USER INPUT
###################################################################################

###################################################################################
# BEGIN INITIALIZE DATABASE
###################################################################################
if [ ! -d "${INSTALLROOT}" ]; then
	mkdir "${INSTALLROOT}"
	chmod 755 "${INSTALLROOT}"
fi

# Create PGDATA main dir
mkPgdataDir

# INITDB
su postgres -c "initdb -D ${PGDATA}"
###################################################################################
# END INITIALIZE DATABASE
###################################################################################

###################################################################################
# BEGIN CONFIGURE USER DATABASES
###################################################################################
# START POSTGRESQL
service postgresql start
# Wait for DB startup before continuing
sleep ${RESTART_SLEEP}

psql -U postgres -d postgres -c "ALTER USER postgres PASSWORD '$PGPASSWORD'"

# CREATE TABLESPACES, ROLES, and LOGICAL DATABASES
i=0
for ((i;i<$NUMDBS;i++)); do
	# Make tablespace dir
	DB=${DBARRAY[$i]}
	TMPPATH="${PGBASE}/${DBARRAY[$i]}"
	mkdir $TMPPATH
	chown postgres $TMPPATH
	chmod 700 $TMPPATH
	DBPASS=$(getDBpass $DB)
	psql -U postgres -d postgres -c "CREATE USER\"$DB\" with password '${DBPASS}'"
	psql -U postgres -d postgres -c "CREATE TABLESPACE \"$DB\" OWNER \"$DB\" LOCATION '$TMPPATH'"
	psql -U postgres -d postgres -c "CREATE DATABASE \"$DB\" WITH OWNER \"$DB\" TABLESPACE \"$DB\""
	psql -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB\" to \"$DB\""
	psql -U postgres -d $DB -c "CREATE EXTENSION postgis"
	psql -U postgres -d $DB -c "CREATE EXTENSION postgis_topology"
	psql -U postgres -d $DB -c "CREATE EXTENSION pg_trgm"
done
###################################################################################
# END CONFIGURE USER DATABASES
###################################################################################

###################################################################################
# BEGIN CONFIGURE REPLICATION SETTINGS
###################################################################################
# Configuration as primary if needed
if [ "${STANDBY_IPS}" ]; then
	STANDBYS=(${STANDBY_IPS})
	NUMIPS=${#STANDBYS[@]}
	i=0
	for ((i;i<$NUMIPS;i++)); do
		IP=${STANDBYS[$i]}
		echo "host    replication     postgres       $IP/32           trust" >> "${PGHBA_CONF}"
	done

	replaceConfSetting "wal_level" "hot_standby" "${POSTGRESQL_CONF}"
	replaceConfSetting "max_wal_senders" "5" "${POSTGRESQL_CONF}"
	replaceConfSetting "wal_keep_segments" "32" "${POSTGRESQL_CONF}"
	replaceConfSetting "max_replication_slots" "4" "${POSTGRESQL_CONF}"
	# This causes an error during standby pg_basebackup if not readable
	chown postgres "${PGDATA}/serverlog"
	# Must restart before adding a replication slot
	service postgresql restart
	sleep ${RESTART_SLEEP}
	psql -U postgres -d postgres -c "select * from pg_create_physical_replication_slot('postgres')"
else
	service postgresql reload
fi
###################################################################################
# END CONFIGURE REPLICATION SETTINGS
###################################################################################

###################################################################################
# BEGIN CONFIGURE SCHEMA
###################################################################################
# LOAD SCHEMA FOR EACH DB
if [ ${SCHEMA} ]; then
	i=0
	if [ -e ${SCHEMA} ]; then
		for ((i;i<$NUMDBS;i++)); do
			DB=${DBARRAY[$i]}
			psql -U $DB -d $DB -f "${SCHEMA}"
			echo "Loaded schema for $DB"
			echo "Run -> psql -U $DB -d $DB -f ${INDICES}  <- To create default indices after importing any baseline data"
		done
	fi
fi
###################################################################################
# END CONFIGURE SCHEMA
###################################################################################

###################################################################################
# BEGIN DB CONFIGURATION AND SECURITY SETTINGS
###################################################################################
${DB_SETTINGS}
###################################################################################
# END DB CONFIGURATION AND SECURITY SETTINGS
###################################################################################

###################################################################################
# BEGIN CONFIGURE BACKUP
###################################################################################
# Add cron entry
(crontab -l; echo "0 0 * * * /usr/local/pgsql/bin/postgresql_backup.sh") | sort | uniq | crontab -
###################################################################################
# END CONFIGURE BACKUP
###################################################################################


