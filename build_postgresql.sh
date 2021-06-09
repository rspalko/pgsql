#!/bin/bash
# RP
#
# Change these to upgrade dependency and postgres version for build
# Supplying only the filename, assumes that you run the script from the directory containing these files

# Exit on error
set -e

PGVERSION=13.3

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
CMAKE_FILE=`basename $CMAKE`
GEOS_FILE=`basename $GEOS`
GDAL_FILE=`basename $GDAL`
PROJ_FILE=`basename $PROJ`
POSTGIS_FILE=`basename $POSTGIS`
PROTOBUF_FILE=protobuf-3.17.2.tar.gz
PROTOBUF_C_FILE=protobuf-c-1.4.0.tar.gz
POSTGRES_FILE=`basename $POSTGRES`
SQLITE3_FILE=`basename $SQLITE3`
PGAUDIT_FILE=pgaudit-`basename $PGAUDIT`

if [ ! -e $CMAKE_FILE ]; then
        wget $CMAKE
fi
if [ ! -e $GEOS_FILE ]; then
	wget $GEOS
fi
if [ ! -e $GDAL_FILE ]; then
        wget $GDAL
fi
if [ ! -e $PROJ_FILE ]; then
        wget $PROJ
fi
if [ ! -e $PROTOBUF_FILE ]; then
        wget -O $PROTOBUF_FILE $PROTOBUF
fi
if [ ! -e $PROTOBUF_C_FILE ]; then
        wget -O $PROTOBUF_C_FILE $PROTOBUF_C
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
if [ ! -e $PGAUDIT_FILE ]; then
        wget -O $PGAUDIT_FILE $PGAUDIT
fi


CMAKE_DIR=$(extractBase $CMAKE_FILE)
GEOS_DIR=$(extractBase $GEOS_FILE)
GDAL_DIR=$(extractBase $GDAL_FILE)
PROJ_DIR=$(extractBase $PROJ_FILE)
POSTGIS_DIR=$(extractBase $POSTGIS_FILE)
PROTOBUF_DIR=$(extractBase $PROTOBUF_FILE)
PROTOBUF_C_DIR=$(extractBase $PROTOBUF_C_FILE)
POSTGRES_DIR=$(extractBase $POSTGRES_FILE)
SQLITE3_DIR=$(extractBase $SQLITE3_FILE)
PGAUDIT_DIR=$(extractBase $PGAUDIT_FILE)

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
mkdir -p "${BUILD_DIR}"
set -e
touch "${BUILD_DIR}/${MARKER}"

export DEV_INSTALL_LOCATION=$PWD/build/devinstall
export LD_LIBRARY_PATH=$DEV_INSTALL_LOCATION/lib64:$DEV_INSTALL_LOCATION/lib:${BUILD_DIR}/install/lib64:${BUILD_DIR}/install/lib:$LD_LIBRARY_PATH
export PATH=$DEV_INSTALL_LOCATION/bin:${BUILD_DIR}/install/bin:$PATH


dependencies=($GEOS_FILE $GDAL_FILE $SQLITE3_FILE $PROJ_FILE $PROTOBUF_C_FILE $PROTOBUF_FILE $POSTGIS_FILE $POSTGRES_FILE $PG_PRIMARY $PG_STANDBY $DB_SETTINGS $POSTGIS_PDF $SCHEMA $INDICES $PGBACKUP)
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
	echo "IN" $PWD
	EXTRACTCOMMAND=$(getExtractCommand ../$1)
	$EXTRACTCOMMAND ../$1
	cd $2
	echo $PWD
	case $2 in
                ($CMAKE_DIR)
			./configure --prefix="${DEV_INSTALL_LOCATION}"
			make -j $(nproc)
                        make install
                        ;;
		($GDAL_DIR)
			echo "GDAL BUILD"
			./configure --prefix="${BUILD_DIR}/install" --with-proj="${BUILD_DIR}/install" --with-geos="${BUILD_DIR}/install/bin/geos-config"
			make -j $(nproc)
			make install
			;;
                ($PGAUDIT_DIR)
                        echo "PGAUDIT BUILD"
                        export PGCONFIG=${BUILD_DIR}/install/bin/pg_config
			make install USE_PGXS=1 PG_CONFIG=$PGCONFIG
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
		($POSTGRES_DIR)
			echo "POSTGRES BUILD"
			./configure --prefix="${BUILD_DIR}/install" --with-openssl
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
                ($PROTOBUF_DIR)
                        echo "PROTOBUF BUILD"
                        ./autogen.sh
                        ./configure --prefix="${BUILD_DIR}/install"
                        make -j $(nproc)
                        make install
                        ;;
		($PROTOBUF_C_DIR)
			echo "PROTOBUF C BUILD"
			export PKG_CONFIG_PATH="${BUILD_DIR}/install/lib/pkgconfig"
			export PROTOC="${BUILD_DIR}/install/bin/protoc"
			./autogen.sh
		       	./configure --prefix="${BUILD_DIR}/install" 
			make -j $(nproc)
			make install
			;;
		($SQLITE3_DIR)
			echo "BUILD SQLITE3, which is now a PROJ4 dependency"
                        CFLAGS="-DSQLITE_ENABLE_COLUMN_METADATA=1" ./configure --prefix="${BUILD_DIR}/install" --disable-tcl
                        make -j $(nproc)
                        make install
                        ;;
		($PROJ_DIR)
			echo PROJ $PWD
			echo "BUILDING PROJ4"
			cmake -DSQLITE3_INCLUDE_DIR="${BUILD_DIR}/install/include" -DSQLITE3_LIBRARY="${BUILD_DIR}/install/lib/libsqlite3.so" -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/install" .
                        make -j $(nproc)
                        make install
			# Workaround for GDAL not finding in lib64 on some platforms
			#cp -P ${BUILD_DIR}/install/lib64/libproj.so* ${BUILD_DIR}/install/lib
                        ;;
		(*)
			./configure --prefix="${BUILD_DIR}/install"
			make -j $(nproc)
                        make install
			;;
	esac
	cd ..
}

buildTarget $CMAKE_FILE $CMAKE_DIR
buildTarget $SQLITE3_FILE $SQLITE3_DIR
buildTarget $PROJ_FILE $PROJ_DIR
buildTarget $GEOS_FILE $GEOS_DIR
buildTarget $GDAL_FILE $GDAL_DIR
buildTarget $POSTGRES_FILE $POSTGRES_DIR
buildTarget $PROTOBUF_FILE $PROTOBUF_DIR
buildTarget $PROTOBUF_C_FILE $PROTOBUF_C_DIR
buildTarget $POSTGIS_FILE $POSTGIS_DIR
buildTarget $PGAUDIT_FILE $PGAUDIT_DIR

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







