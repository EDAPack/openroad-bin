#!/bin/bash -x

set -e

root=$(pwd)
NPROC=$(nproc)

#********************************************************************
#* Install required packages
#********************************************************************
if test $(uname -s) = "Linux"; then
    # Detect if we're on RHEL 7 (manylinux2014) or RHEL 8+ (manylinux_2_28+)
    if test -f /etc/centos-release && grep -q "CentOS Linux release 7" /etc/centos-release; then
        # manylinux2014 / CentOS 7
        yum update -y
        yum install -y epel-release
        yum install -y glibc-static wget flex bison jq \
            cmake3 autoconf automake libtool make gcc gcc-c++ git \
            zlib-devel tcl tcl-devel tk tk-devel \
            libffi-devel readline-devel \
            python3 python3-devel python3-pip \
            pcre-devel pcre2-devel \
            openssl-devel

        # Create cmake symlink if cmake3 exists
        if test -f /usr/bin/cmake3 && test ! -f /usr/bin/cmake; then
            ln -s /usr/bin/cmake3 /usr/bin/cmake
        fi
    else
        # manylinux_2_28+ / AlmaLinux 8+
        dnf update -y
        dnf install -y epel-release
        dnf install -y glibc-static wget flex bison jq \
            cmake autoconf automake libtool make gcc gcc-c++ git \
            zlib-devel tcl tcl-devel tk tk-devel \
            libffi-devel readline-devel \
            python3 python3-devel python3-pip \
            pcre-devel pcre2-devel \
            openssl-devel qt5-qtbase-devel
    fi

    if test -z $image; then
        image=linux
    fi
    
    export PATH=/opt/python/cp312-cp312/bin:$PATH
    
    rls_plat=${image}
fi

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

#********************************************************************
#* Set install prefix
#********************************************************************
INSTALL_PREFIX=${root}/release/openroad
mkdir -p ${INSTALL_PREFIX}
export PATH=${INSTALL_PREFIX}/bin:$PATH
export LD_LIBRARY_PATH=${INSTALL_PREFIX}/lib:${INSTALL_PREFIX}/lib64:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=${INSTALL_PREFIX}/lib/pkgconfig:${INSTALL_PREFIX}/lib64/pkgconfig:$PKG_CONFIG_PATH
export CMAKE_PREFIX_PATH=${INSTALL_PREFIX}:$CMAKE_PREFIX_PATH

#********************************************************************
#* Build dependencies
#********************************************************************
BUILD_DIR=${root}/build_deps
mkdir -p ${BUILD_DIR}
cd ${BUILD_DIR}

# Build newer CMake (use pre-built binary to avoid bootstrap issues)
CMAKE_VERSION="3.28.3"
if ! test -f ${INSTALL_PREFIX}/bin/cmake; then
    echo "=== Installing CMake ${CMAKE_VERSION} ==="
    arch=$(uname -m)
    wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${arch}.sh
    chmod +x cmake-${CMAKE_VERSION}-linux-${arch}.sh
    ./cmake-${CMAKE_VERSION}-linux-${arch}.sh --skip-license --prefix=${INSTALL_PREFIX}
    cd ${BUILD_DIR}
fi
export PATH=${INSTALL_PREFIX}/bin:$PATH

# Build newer Bison (required by SWIG 4.2+)
BISON_VERSION="3.8.2"
if ! test -f ${INSTALL_PREFIX}/bin/bison; then
    echo "=== Building Bison ${BISON_VERSION} ==="
    wget https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.gz
    tar xzf bison-${BISON_VERSION}.tar.gz
    cd bison-${BISON_VERSION}
    ./configure --prefix=${INSTALL_PREFIX}
    make -j${NPROC}
    make install
    cd ${BUILD_DIR}
fi
export PATH=${INSTALL_PREFIX}/bin:$PATH

# Build Boost
BOOST_VERSION="1.85.0"
BOOST_VERSION_UNDERSCORE=${BOOST_VERSION//./_}
if ! test -f ${INSTALL_PREFIX}/lib/libboost_system.so; then
    echo "=== Building Boost ${BOOST_VERSION} ==="
    wget https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_UNDERSCORE}.tar.gz
    tar xzf boost_${BOOST_VERSION_UNDERSCORE}.tar.gz
    cd boost_${BOOST_VERSION_UNDERSCORE}
    ./bootstrap.sh --prefix=${INSTALL_PREFIX}
    ./b2 install --with-iostreams --with-test --with-serialization --with-system --with-thread --with-filesystem --with-program_options -j${NPROC}
    cd ${BUILD_DIR}
fi

# Build spdlog
SPDLOG_VERSION="1.13.0"
if ! test -f ${INSTALL_PREFIX}/lib64/libspdlog.a; then
    echo "=== Building spdlog ${SPDLOG_VERSION} ==="
    git clone --depth=1 -b v${SPDLOG_VERSION} https://github.com/gabime/spdlog.git
    cd spdlog
    cmake -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DSPDLOG_BUILD_EXAMPLE=OFF -B build .
    cmake --build build -j${NPROC} --target install
    cd ${BUILD_DIR}
fi

# Build Eigen
EIGEN_VERSION="3.4.0"
if ! test -d ${INSTALL_PREFIX}/include/eigen3; then
    echo "=== Building Eigen ${EIGEN_VERSION} ==="
    git clone --depth=1 -b ${EIGEN_VERSION} https://gitlab.com/libeigen/eigen.git
    cd eigen
    cmake -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -B build .
    cmake --build build -j${NPROC} --target install
    cd ${BUILD_DIR}
fi

# Build SWIG
SWIG_VERSION="4.2.1"
if ! test -f ${INSTALL_PREFIX}/bin/swig; then
    echo "=== Building SWIG ${SWIG_VERSION} ==="
    wget https://github.com/swig/swig/archive/refs/tags/v${SWIG_VERSION}.tar.gz -O swig-${SWIG_VERSION}.tar.gz
    tar xzf swig-${SWIG_VERSION}.tar.gz
    cd swig-${SWIG_VERSION}
    ./autogen.sh
    ./configure --prefix=${INSTALL_PREFIX}
    make -j${NPROC}
    make install
    cd ${BUILD_DIR}
fi

# Build CUDD
if ! test -f ${INSTALL_PREFIX}/include/cudd.h; then
    echo "=== Building CUDD ==="
    git clone --depth=1 -b 3.0.0 https://github.com/The-OpenROAD-Project/cudd.git
    cd cudd
    autoreconf -fi
    ./configure --prefix=${INSTALL_PREFIX}
    make -j${NPROC}
    make install
    cd ${BUILD_DIR}
fi

# Build lemon
LEMON_VERSION="1.3.1"
if ! test -f ${INSTALL_PREFIX}/include/lemon/config.h; then
    echo "=== Building Lemon ${LEMON_VERSION} ==="
    git clone --depth=1 -b ${LEMON_VERSION} https://github.com/The-OpenROAD-Project/lemon-graph.git
    cd lemon-graph
    cmake -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -B build .
    cmake --build build -j${NPROC} --target install
    cd ${BUILD_DIR}
fi

# Build or-tools (required by OpenROAD)
OR_TOOLS_VERSION="9.10"
if ! test -d ${INSTALL_PREFIX}/include/ortools; then
    echo "=== Building or-tools ${OR_TOOLS_VERSION} ==="
    git clone --depth=1 -b v${OR_TOOLS_VERSION} https://github.com/google/or-tools.git
    cd or-tools
    cmake -S. -Bbuild \
        -DBUILD_DEPS=ON \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_SAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} \
        -DCMAKE_CXX_FLAGS="-w" \
        -DCMAKE_C_FLAGS="-w"
    cmake --build build --config Release --target install -j${NPROC}
    cd ${BUILD_DIR}
fi

#********************************************************************
#* Clone and Build OpenROAD
#********************************************************************
cd ${root}
echo "=== Cloning OpenROAD ${openroad_version} ==="
git clone --recursive --depth=1 -b ${openroad_version} https://github.com/The-OpenROAD-Project/OpenROAD.git
cd OpenROAD

echo "=== Building OpenROAD ==="
mkdir -p build
cd build

cmake .. \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} \
    -DCMAKE_BUILD_TYPE=Release \
    -DTCL_LIBRARY=/usr/lib64/libtcl.so \
    -DCMAKE_PREFIX_PATH="${INSTALL_PREFIX}" \
    -DPython3_ROOT_DIR=/opt/python/cp312-cp312 \
    -DPython3_EXECUTABLE=/opt/python/cp312-cp312/bin/python3

make -j${NPROC}
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
