#!/bin/bash

export PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin:/usr/local/pgsql/bin
export LD_LIBRARY_PATH=/usr/local/pgsql/lib
umask 077

# Log everything to a file
(

# some global valies
retval=0
count=0

# get today's date
date=`date '+%Y%m%d%H%M%S'`
dir_date=`date '+%Y-%m-%d'`
username="postgres"
pg_bin_dir="/usr/local/pgsql/bin/"
pg_basebackup="$pg_bin_dir/pg_basebackup"
psql="$pg_bin_dir/psql"

backup_dir="/tmp"
server_name=${HOSTNAME:='dbserver'}
backup_base="${server_name}_backup"

# Dump database schema for all databases
printf "====================================================\n"
printf "Backup starting at: %s\n" "`date '+%c'`"

mkdir "$backup_dir" || (printf 'Failed to create backup directory: %s\n' "$backup_dir"; exit 1)

backup_path="$backup_dir/${backup_base}_${date}"
printf "Performing PG basebackup to %s\n" "$backup_path"
$pg_basebackup -v -U postgres -X fetch -P -Ft -D "$backup_path"
retval=$?
printf "Backup completed at: %s with status: %d\n" "`date '+%c'`" $retval
printf "Compressing backup...."
gzip "$backup_path/base.tar"
printf "Completed\n"
printf "====================================================\n"
exit $retval

) >> /var/log/database_backup.log 2>&1


