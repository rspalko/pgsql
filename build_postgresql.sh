#!/bin/bash
# RP
#
# Change these to upgrade dependency and postgres version for build
# Supplying only the filename, assumes that you run the script from the directory containing these files

# Exit on error
set -e

PGVERSION=12.3

source locations.sh

#PGDADMIN=pgadmin3-1.20.0.tar.gz
#WIDGETS=wxWidgets-2.8.12.tar.gz

PG_PRIMARY=pg_primary.sh
PG_STANDBY=pg_standby.sh
DB_SETTINGS=db_settings.sh
POSTGIS_PDF=$(basename $POSTGIS_PDF_URL) 
if [ ! -e $POSTGIS_PDF ]; then
	wget $POSTGIS_PDF_URL
fi
SCHEMA=schema.sql
INDICES=indices.sql
PGBACKUP=postgresql_backup.sh

extractBase()
{
	if [[ "$1" =~ (.*[0-9])\..* ]]; then
		echo ${BASH_REMATCH[1]}
	else
		echo $1
	fi
}

getExtractCommand()
{
	FILEOUT=$(file $1)
	if [[ "$FILEOUT" =~ "gzip" ]]; then
		echo "tar xzf "
	elif [[ "$FILEOUT" =~ "bzip" ]]; then
		echo "tar xjf "
	elif [[ "$FILEOUT" =~ "zip" ]]; then
		echo "unzip -o "
	fi
}

retrieveDependency()
{
	if [[ $1 =~ http* || $1 =~ ftp* ]]; then
		cd $2
		wget $1
	else
		cp $1 $2
	fi
}

testFile()
{
	if [ ! -e "$1" ]; then
		echo "Could not locate $1, exiting script"
		exit 1
	fi
}

# Need to get basename in case we have URL or absolute path
GEOS_FILE=`basename $GEOS`
GDAL_FILE=`basename $GDAL`
PROJ_FILE=`basename $PROJ`
POSTGIS_FILE=`basename $POSTGIS`
POSTGRES_FILE=`basename $POSTGRES`
SQLITE3_FILE=`basename $SQLITE3`

if [ ! -e $GEOS_FILE ]; then
	wget $GEOS
fi
if [ ! -e $GDAL_FILE ]; then
        wget $GDAL
fi
if [ ! -e $PROJ_FILE ]; then
        wget $PROJ
fi
if [ ! -e $POSTGIS_FILE ]; then
        wget $POSTGIS
fi
if [ ! -e $POSTGRES_FILE ]; then
        wget $POSTGRES
fi
if [ ! -e $SQLITE3_FILE ]; then
        wget $SQLITE3
fi


#PGDADMIN_FILE=`basename $PGADMIN`
#WIDGETS_FILE=`basename $WIDGETS`

GEOS_DIR=$(extractBase $GEOS_FILE)
GDAL_DIR=$(extractBase $GDAL_FILE)
PROJ_DIR=$(extractBase $PROJ_FILE)
POSTGIS_DIR=$(extractBase $POSTGIS_FILE)
POSTGRES_DIR=$(extractBase $POSTGRES_FILE)
SQLITE3_DIR=$(extractBase $SQLITE3_FILE)
#PGADMIN_DIR=$(extractBase $PGADMIN_FILE)
#WIDGETS_DIR=$(extractBase $WIDGETS_FILE)

pushd `dirname "$0"` >& /dev/null
export SWD=$PWD
popd >& /dev/null
export DEFAULT_SOURCE_DIR=$PWD
export DEFAULT_BUILD_DIR=$PWD/build

umask 0022

read -p "Select build location: (Default is $DEFAULT_BUILD_DIR)" BUILD_DIR
BUILD_DIR=${BUILD_DIR:-$DEFAULT_BUILD_DIR}
MARKER=.postgresbuildmarker

if [ -d "${BUILD_DIR}" ]; then
	if [ -e "${BUILD_DIR}" -a ! -e "${BUILD_DIR}/$MARKER" ]; then
		echo "Build location at ${BUILD_DIR} already exists, but is not a Postgres build directory"
		exit 1
	fi
fi
set +e
mkdir "${BUILD_DIR}"
set -e
touch "${BUILD_DIR}/${MARKER}"

#dependencies=($GEOS $GDAL $PROJ $POSTGIS $POSTGRES $PGADMIN $WIDGETS $PG_PRIMARY $PG_STANDBY $DB_SETTINGS $POSTGIS_PDF $SCHEMA $INDICES $PGBACKUP)
dependencies=($GEOS_FILE $GDAL_FILE $SQLITE3_FILE $PROJ_FILE $POSTGIS_FILE $POSTGRES_FILE $PG_PRIMARY $PG_STANDBY $DB_SETTINGS $POSTGIS_PDF $SCHEMA $INDICES $PGBACKUP)
numdeps=${#dependencies[@]}
i=0
for ((i;i<$numdeps;i++)); do
	testFile ${dependencies[$i]}
done

i=0
for ((i;i<$numdeps;i++)); do
	retrieveDependency ${dependencies[$i]} "${BUILD_DIR}"
done

cd "${BUILD_DIR}"

buildTarget()
{
	echo "Building $1 at $2"
	EXTRACTCOMMAND=$(getExtractCommand $1)
	$EXTRACTCOMMAND $1
	cd $2
	case $2 in
		($GDAL_DIR)
			echo "GDAL BUILD"
			./configure --prefix="${BUILD_DIR}/install" --with-proj="${BUILD_DIR}/install" --with-geos="${BUILD_DIR}/install/bin/geos-config"
			make -j $(nproc)
			make install
			;;
		($POSTGIS_DIR)
			echo "POSTGIS BUILD"
			export LD_LIBRARY_PATH="${BUILD_DIR}/install/lib:${LD_LIBRARY_PATH}"
			export PGCONFIG=${BUILD_DIR}/install/pg_config
			./configure --prefix="${BUILD_DIR}/install" --without-json --with-geosconfig="${BUILD_DIR}/install/bin/geos-config" --with-projdir="${BUILD_DIR}/install" --with-gdalconfig="${BUILD_DIR}/install/bin/gdal-config" --with-pgconfig="${BUILD_DIR}/install/bin/pg_config"
			# there is a parallel make bug, disable -j option for now
			make #-j $(nproc)
			make install
			;;
		#($WIDGETS_DIR)
		#	echo "wxWidgets BUILD"
		#	./configure --prefix="${BUILD_DIR}/install" --enable-unicode
		#	make -j $(nproc)
		#	make install
		#	cd contrib
		#	# Saw an issue with parallel make here, so using a single CPU for now
		#	make
		#	make install
		#	cd ..
		#	;;
		#($PGADMIN_DIR)
		#	echo "PGADMIN BUILD"
		#	./configure --prefix="${BUILD_DIR}/install" --with-wx="${BUILD_DIR}/install"
		#	# Need to be able to find wxWidgets bins and libs
		#	export PATH="${BUILD_DIR}/install/bin:$PATH"
		#	export LD_LIBRARY_PATH="${BUILD_DIR}/install/lib"
		#	make -j $(nproc)
		#	make install
		#	;;
		($POSTGRES_DIR)
			echo "POSTGRES BUILD"
			./configure --prefix="${BUILD_DIR}/install"
			make -j $(nproc)
			make install
			cd contrib
			make -j $(nproc)
			make install
			cd ..
			cd doc
			make 
			make install
			cd ..
			;;
		($SQLITE3_DIR)
			echo "BUILD SQLITE3, which is now a PROJ4 dependency"
                        ./configure --prefix="${BUILD_DIR}/install" --disable-tcl
                        make -j $(nproc)
                        make install
                        ;;
		($PROJ_DIR)
			echo "BUILDING PROJ4"
			mkdir build
			cd build
			cmake -DSQLITE3_INCLUDE_DIR="${BUILD_DIR}/install/include" -DSQLITE3_LIBRARY="${BUILD_DIR}/install/lib/libsqlite3.so" -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/install" ..
                        make -j $(nproc)
                        make install
			cd ..
                        ;;
		(*)
			./configure --prefix="${BUILD_DIR}/install"
			make -j $(nproc)
                        make install
			;;
	esac
	cd ..
}

buildTarget $SQLITE3_FILE $SQLITE3_DIR
buildTarget $PROJ_FILE $PROJ_DIR
buildTarget $GEOS_FILE $GEOS_DIR
buildTarget $GDAL_FILE $GDAL_DIR
buildTarget $POSTGRES_FILE $POSTGRES_DIR
buildTarget $POSTGIS_FILE $POSTGIS_DIR
#buildTarget $WIDGETS_FILE $WIDGETS_DIR
#buildTarget $PGADMIN_FILE $PGADMIN_DIR

# Copy site specific scripts
cp "${BUILD_DIR}/${PG_PRIMARY}" "${BUILD_DIR}/install/bin"
cp "${BUILD_DIR}/${PG_STANDBY}" "${BUILD_DIR}/install/bin"
cp "${BUILD_DIR}/${DB_SETTINGS}" "${BUILD_DIR}/install/bin"
cp "${BUILD_DIR}/${PGBACKUP}" "${BUILD_DIR}/install/bin"
cp "${BUILD_DIR}/${SCHEMA}" "${BUILD_DIR}/install/bin"
cp "${BUILD_DIR}/${INDICES}" "${BUILD_DIR}/install/bin"

cp "${BUILD_DIR}/${POSTGIS_PDF}" "${BUILD_DIR}/install/share/doc"
chmod 644 "${BUILD_DIR}/install/share/doc/${POSTGIS_PDF}"
cp "${BUILD_DIR}/${POSTGRES_DIR}/contrib/start-scripts/linux" "${BUILD_DIR}/install/bin"
sed -i "s/^PGDATA=.*$/PGDATA=\/opt\/pgsql\/pgdata/" "${BUILD_DIR}/install/bin/linux"
sed -i "s/su -/su/g" "${BUILD_DIR}/install/bin/linux"
sed -i "/^PGDATA=/a export LD_LIBRARY_PATH=/usr/local/pgsql/lib" "${BUILD_DIR}/install/bin/linux"
#cp linux install/bin
cp ${POSTGIS_DIR}/liblwgeom/.libs/liblwgeom* "${BUILD_DIR}/install/lib"
cp $SWD/postgresql.spec.template-${PGVERSION} postgresql.spec
pushd .
mkdir -p rpmbuild/usr/local
tar cf - install | (cd rpmbuild/usr/local; tar xf -)
cd rpmbuild/usr/local
mv install pgsql
cd ../..
find usr \( -type f -o -type l \) -exec echo "/{}" \; >> ../postgresql.spec
popd
rpmbuild -bb --buildroot=$PWD/rpmbuild postgresql.spec







