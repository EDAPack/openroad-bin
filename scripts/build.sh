#!/bin/bash -x

set -e

root=$(pwd)
NPROC=$(nproc)

#********************************************************************
#* Validate environment variables
#********************************************************************
if test -z "$openroad_version"; then
  echo "openroad_version not set"
  env
  exit 1
fi

#********************************************************************
#* Calculate version information
#********************************************************************
rls_version=${openroad_version}
if test "x${BUILD_NUM}" != "x"; then
    rls_version="${rls_version}.${BUILD_NUM}"
fi

if test -z "$image"; then
    image=linux
fi
rls_plat=${image}

#********************************************************************
#* Set install prefix
#********************************************************************
INSTALL_PREFIX=${root}/release/openroad
mkdir -p ${INSTALL_PREFIX}

#********************************************************************
#* Build and install Tcl from source FIRST
#********************************************************************
echo "=== Building Tcl from source ==="
cd ${root}
TCL_VERSION=8.6.16
curl -L -o tcl${TCL_VERSION}-src.tar.gz "https://prdownloads.sourceforge.net/tcl/tcl${TCL_VERSION}-src.tar.gz"
tar xzf tcl${TCL_VERSION}-src.tar.gz
cd tcl${TCL_VERSION}/unix
./configure --prefix=${INSTALL_PREFIX} --enable-shared
make -j${NPROC}
make install

#********************************************************************
#* Clone OpenROAD
#********************************************************************
cd ${root}
echo "=== Cloning OpenROAD ${openroad_version} ==="
git clone --recursive --depth=1 -b ${openroad_version} https://github.com/The-OpenROAD-Project/OpenROAD.git
cd OpenROAD

#********************************************************************
#* Install dependencies using OpenROAD's installer
#********************************************************************
echo "=== Installing base dependencies ==="
./etc/DependencyInstaller.sh -base

echo "=== Installing common dependencies ==="
./etc/DependencyInstaller.sh -common -prefix=${INSTALL_PREFIX}

#********************************************************************
#* Build OpenROAD
#********************************************************************
echo "=== Building OpenROAD ==="
./etc/Build.sh -cmake="-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX} -DTCL_LIBRARY=${INSTALL_PREFIX}/lib/libtcl8.6.so -DTCL_INCLUDE_PATH=${INSTALL_PREFIX}/include"

echo "=== Installing OpenROAD ==="
cd build
make install

#********************************************************************
#* Copy runtime dependencies
#********************************************************************
echo "=== Copying runtime dependencies ==="
cd ${INSTALL_PREFIX}

# Copy required shared libraries
mkdir -p lib
for lib in $(ldd bin/openroad | grep "=> /" | awk '{print $3}'); do
    # Skip system libraries that are commonly available
    case $(basename $lib) in
        libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|ld-linux*|linux-vdso*)
            continue
            ;;
        *)
            cp -L $lib lib/ 2>/dev/null || true
            ;;
    esac
done

# Create wrapper script
cat > bin/openroad.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${SCRIPT_DIR}/../lib:${LD_LIBRARY_PATH}"
export TCL_LIBRARY="${SCRIPT_DIR}/../lib/tcl8.6"
exec "${SCRIPT_DIR}/openroad" "$@"
EOF
chmod +x bin/openroad.sh

#********************************************************************
#* Create release tarball
#********************************************************************
cd ${root}/release

tar czf openroad-${rls_plat}-${rls_version}.tar.gz openroad
if test $? -ne 0; then exit 1; fi

echo "Build complete: openroad-${rls_plat}-${rls_version}.tar.gz"
ls -la
