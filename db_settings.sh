#!/bin/bash

PGBASE=/opt/pgsql
PGDATA=/${PGBASE}/pgdata

# Files to edit
POSTGRESQL_CONF=${PGDATA}/postgresql.conf
PGHBA_CONF=${PGDATA}/pg_hba.conf

#########################################################################
# BEGIN FUNCTION DEFINITIONS
#########################################################################
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
	sed -i "/^${1} = ${2}/ !s/^${1} =/${1} = ${2}      #PREVIOUS VALUE# /" "${3}"
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
# BEGIN CUSTOMIZE postgresql.conf CONFIGURATION
###################################################################################
# Change listen addresses
replaceConfSetting "listen_addresses" "'*'" "${POSTGRESQL_CONF}"

# Max connections
replaceConfSetting "max_connections" "1000" "${POSTGRESQL_CONF}"

# Logging
replaceConfSetting "log_destination" "'syslog'" "${POSTGRESQL_CONF}"
replaceConfSetting "syslog_facility" "'LOCAL6'" "${POSTGRESQL_CONF}"
replaceConfSetting "client_min_messages" "info" "${POSTGRESQL_CONF}"
replaceConfSetting "log_min_messages" "info" "${POSTGRESQL_CONF}"
replaceConfSetting "log_min_error_statement" "info" "${POSTGRESQL_CONF}"
replaceConfSetting "log_connections" "on" "${POSTGRESQL_CONF}"
replaceConfSetting "log_disconnections" "on" "${POSTGRESQL_CONF}"
replaceConfSetting "log_hostname" "on" "${POSTGRESQL_CONF}"
replaceConfSetting "log_line_prefix" "'%r '" "${POSTGRESQL_CONF}"
replaceConfSetting "log_min_duration_statement" "60000" "${POSTGRESQL_CONF}"
replaceConfSetting "log_duration" "on" "${POSTGRESQL_CONF}"

# Memory settings
HALFMEMORYGB=$(expr $(cat /proc/meminfo | head -1 | awk '{print $2}') / 2097152)GB
QUARTERMEMORYMB=$(expr $(cat /proc/meminfo | head -1 | awk '{print $2}') / 4096)MB
replaceConfSetting "effective_cache_size" "${HALFMEMORYGB}" "${POSTGRESQL_CONF}"
replaceConfSetting "shared_buffers" "${QUARTERMEMORYMB}" "${POSTGRESQL_CONF}"
replaceConfSetting "work_mem" "16MB" "${POSTGRESQL_CONF}"
replaceConfSetting "maintenance_work_mem" "4096MB" "${POSTGRESQL_CONF}"
###################################################################################
# END CUSTOMIZE postgresql.conf CONFIGURATION
###################################################################################

###################################################################################
# BEGIN LOCKDOWN pg_hba.conf
###################################################################################
# Remore connections in pg_hba.conf
# ADD pg_hba.conf entry for MD5 password access from any IP
MD5_ALLOW="host    all             all             0.0.0.0/0             md5"
MD5_INSERT_BEFORE="IPv6 local connections"
# Insert only if we don't already have an entry
! grep -q '0.0.0.0/0' "${PGHBA_CONF}" && insertLine "${MD5_INSERT_BEFORE}" "${MD5_ALLOW}" "${PGHBA_CONF}"

# require password for local connections
replaceLine "host.*all.*all::1\/128.*trust" "host    all             all             ::1\/128             md5" "${PGHBA_CONF}"
replaceLine "local.*all.*all.*trust" "local    all             all             md5" "${PGHBA_CONF}"
replaceLine "host.*all.*all.*127.0.0.1\/32.*trust" "host    all             all             127.0.0.1\/32             md5" "${PGHBA_CONF}"
###################################################################################
# END LOCKDOWN pg_hba.conf
###################################################################################

###################################################################################
# BEGIN RESTART SERVER
###################################################################################
service postgresql restart
###################################################################################
# END RESTART SERVER
###################################################################################














