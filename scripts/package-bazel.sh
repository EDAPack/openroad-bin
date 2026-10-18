#!/bin/bash -x
#********************************************************************
#* PROTOTYPE: bundle runtime libraries into the Bazel install and
#* create the release tarball.
#*
#* Runs inside quay.io/pypa/manylinux_2_28_x86_64 (AlmaLinux 8): the
#* Bazel binaries need only glibc 2.28, but the GUI build links
#* against system X11/xcb/dbus/fontconfig/xkbcommon libraries. Taking
#* those from an EL8 image keeps the bundle at the same glibc floor.
#* The binaries get RPATH $ORIGIN/../lib so they work without a
#* wrapper script.
#********************************************************************

set -e

root=$(pwd)
INSTALL_PREFIX=${root}/release/openroad
metrics=${root}/release/metrics.md
rls_plat=${image:-linux-bazel}
rls_version=$(cat ${root}/release/version.txt)

metric() {
    echo "| $1 | $2 |" >> ${metrics}
}

# glibc itself always comes from the host
is_system_lib() {
    case $1 in
        libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|libresolv.so*|\
        libutil.so*|ld-linux*|linux-vdso*) return 0 ;;
    esac
    return 1
}

#********************************************************************
#* Install the packages that provide each NEEDED library
#********************************************************************
dnf -y install epel-release
needed=$(for b in ${INSTALL_PREFIX}/bin/*; do
    objdump -p $b | awk '/NEEDED/{print $2}'
done | sort -u)
pkgs=""
for lib in ${needed}; do
    is_system_lib ${lib} && continue
    pkgs="${pkgs} ${lib}()(64bit)"
done
if test -n "${pkgs}"; then
    dnf -y install ${pkgs}
fi

#********************************************************************
#* Copy the transitive closure of non-glibc libraries into lib/
#********************************************************************
mkdir -p ${INSTALL_PREFIX}/lib
for b in ${INSTALL_PREFIX}/bin/*; do
    if ldd $b | grep -q "not found"; then
        ldd $b | grep "not found"
        echo "unresolved libraries for $b"
        exit 1
    fi
    for lib in $(ldd $b | awk '/=> \//{print $3}'); do
        is_system_lib $(basename ${lib}) && continue
        cp -L ${lib} ${INSTALL_PREFIX}/lib/
    done
done

for b in ${INSTALL_PREFIX}/bin/*; do
    patchelf --set-rpath '$ORIGIN/../lib' $b
done
for lib in ${INSTALL_PREFIX}/lib/*.so*; do
    patchelf --set-rpath '$ORIGIN' ${lib}
done

newest=$(for f in ${INSTALL_PREFIX}/bin/* ${INSTALL_PREFIX}/lib/*.so*; do
    objdump -T $f | grep -o 'GLIBC_[0-9.]*'
done | sort -uV | tail -1)
metric "Bundled libraries" "$(ls ${INSTALL_PREFIX}/lib | wc -l) ($(du -sh ${INSTALL_PREFIX}/lib | cut -f1))"
metric "Newest glibc symbol (incl. bundle)" "${newest}"

#********************************************************************
#* Create release tarball
#********************************************************************
cd ${root}/release
tar czf openroad-${rls_plat}-${rls_version}.tar.gz openroad
metric "Tarball size" "$(du -h openroad-${rls_plat}-${rls_version}.tar.gz | cut -f1)"

cat ${metrics}
echo "Package complete: openroad-${rls_plat}-${rls_version}.tar.gz"
