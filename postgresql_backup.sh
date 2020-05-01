#!/bin/bash

export PATH=/usr/local/pgsql/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/pgsql/lib
umask 077

# some global valies
retval=0
count=0

# get today's date
date=`date '+%Y%m%d%H%M%S'`
dir_date=`date '+%Y-%m-%d'`
username="postgres"
pg_bin_dir="/usr/local/pgsql/bin/"
pg_dump="$pg_bin_dir/pg_dump"
pg_dumpall="$pg_bin_dir/pg_dumpall"
psql="$pg_bin_dir/psql"

backup_dir="/tmp/${dir_date}"
server_name=${HOSTNAME:='dbserver'}
backup_base="${server_name}_backup"

# Log everything to a file
(

# Dump database schema for all databases
printf "====================================================\n"
printf "Backup starting at: %s\n" "`date '+%c'`"

mkdir "$backup_dir" || (printf 'Failed to create backup directory: %s\n' "$backup_dir"; exit 1)

backup_path="$backup_dir/${backup_base}_schema_${date}"
printf "Dumping database schema for all databases to file: %s\n" "$backup_path"
$pg_dumpall -U $username -s -f "$backup_path"
count=$((count++))

# Can't handle spaces in the database name also template0 is ignored since we can't access it
databases=`$psql -U postgres -d "select datname from pg_database where datname != 'template0'" | tail -n +3 | grep -v '^(' | xargs`
printf "Databases listed from psql: %s\n" "$databases"

for db in $databases; do
	backup_path="$backup_dir/${backup_base}_${db}_${date}"

	printf "Dumping databases: %s\n" $db
	start=`date '+%s'`
	$pg_dump -U $username -Fc -b -v -f "$backup_path" $db
	rc=$?
	stop=`date '+%s'`
	diff=$((stop - start))

	printf "Completed database backup in: %d seconds   status: %d\n" $diff $rc
	retval=$((retval + rc))

	if [ ! -f "$backup_path" ]; then
		printf "No backup file created for %s\n" "$backup_path"
	fi
done


printf "Backup completed at: %s with status: %d\n" "`date '+%c'`" $retval
printf "====================================================\n"
exit $retval

) >> /var/log/database_backup.log 2>&1


