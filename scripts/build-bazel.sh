#!/bin/bash -x
#********************************************************************
#* PROTOTYPE: build OpenROAD with Bazel instead of CMake.
#*
#* Upstream removes CMake support on Nov. 1, 2026. This script runs
#* directly on an Ubuntu runner (no manylinux container): Bazel brings
#* its own hermetic clang/libc++ toolchain and links against glibc
#* stubs, so portability comes from the toolchain rather than the
#* build image. Besides producing a tarball, it records measurements
#* (time, disk, cache hits, glibc floor) in release/metrics.md.
#********************************************************************

set -e

root=$(pwd)
NPROC=$(nproc)
metrics=${root}/release/metrics.md

if test -z "$openroad_version"; then
  echo "openroad_version not set"
  exit 1
fi
if test -z "$image"; then
    image=linux-bazel
fi
rls_plat=${image}

INSTALL_PREFIX=${root}/release/openroad
mkdir -p ${INSTALL_PREFIX}
: > ${metrics}

metric() {
    echo "| $1 | $2 |" >> ${metrics}
}
echo "| Metric | Value |" >> ${metrics}
echo "|---|---|" >> ${metrics}
metric "Disk free at start" "$(df -h --output=avail ${root} | tail -1)"

#********************************************************************
#* Clone OpenROAD
#********************************************************************
cd ${root}
echo "=== Cloning OpenROAD ${openroad_version} ==="
git clone --recursive -b ${openroad_version} https://github.com/The-OpenROAD-Project/OpenROAD.git
cd OpenROAD

OPENROAD_GIT_VERSION=$(git describe --tags --always 2>/dev/null || git rev-parse --short HEAD)
rls_version=${OPENROAD_GIT_VERSION}
if test "x${BUILD_NUM}" != "x"; then
    rls_version="${rls_version}.${BUILD_NUM}"
fi
echo "Release version: ${rls_version}"
echo "${rls_version}" > ${root}/release/version.txt
metric "OpenROAD version" "${OPENROAD_GIT_VERSION}"

#********************************************************************
#* Install dependencies: system libraries (sudo) and bazelisk
#********************************************************************
echo "=== Installing Bazel dependencies ==="
sudo ./etc/DependencyInstaller.sh -bazel -base
./etc/DependencyInstaller.sh -bazel -common -prefix=${HOME}/.local
export PATH=${HOME}/.local/bin:${PATH}
bazelisk version

#********************************************************************
#* Build OpenROAD and OpenSTA
#*
#* --config=release --//:platform=gui matches upstream's Build.sh, so
#* compile actions share keys with upstream CI and can be served from
#* its read-only remote cache (bazel.precisioninno.com, set in .bazelrc).
#********************************************************************
echo "=== Building OpenROAD ==="
bazel_args=(
    "--jobs=${NPROC}"
    "--config=release"
    "--//:platform=gui"
    "--disk_cache=${HOME}/.cache/bazel-disk-cache"
    "--repository_cache=${HOME}/.cache/bazel-repo-cache"
)
start=${SECONDS}
bazelisk build "${bazel_args[@]}" //:openroad //src/sta:opensta 2>&1 | tee ${root}/release/bazel-build.log
build_rc=${PIPESTATUS[0]}
metric "Bazel build time" "$(( (SECONDS - start) / 60 ))m $(( (SECONDS - start) % 60 ))s"
# e.g. "INFO: 12345 processes: 11000 remote cache hit, 1300 linux-sandbox, ..."
metric "Bazel processes" "$(grep -E '^INFO: [0-9]+ processes' ${root}/release/bazel-build.log | tail -1 | sed 's/^INFO: //')"
metric "Disk free after build" "$(df -h --output=avail ${root} | tail -1)"
metric "Disk cache size" "$(du -sh ${HOME}/.cache/bazel-disk-cache 2>/dev/null | cut -f1)"
metric "Repository cache size" "$(du -sh ${HOME}/.cache/bazel-repo-cache 2>/dev/null | cut -f1)"
metric "Output base size" "$(du -sh $(bazelisk info output_base 2>/dev/null) 2>/dev/null | cut -f1)"
if test ${build_rc} -ne 0; then
    echo "=== Bazel build failed (rc=${build_rc}) ==="
    exit ${build_rc}
fi

#********************************************************************
#* Install
#********************************************************************
echo "=== Installing OpenROAD ==="
bazelisk run "${bazel_args[@]}" //:install -- ${INSTALL_PREFIX}
cp -L bazel-bin/src/sta/opensta ${INSTALL_PREFIX}/bin/sta
chmod u+w ${INSTALL_PREFIX}/bin/*

#********************************************************************
#* Inspect the binaries: dynamic deps and the newest glibc symbol
#* they require (this is the effective portability floor).
#********************************************************************
cd ${INSTALL_PREFIX}
for b in openroad sta; do
    glibc=$(objdump -T bin/$b | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)
    metric "${b}: newest glibc symbol" "${glibc}"
    metric "${b}: size" "$(du -h bin/$b | cut -f1)"
    metric "${b}: NEEDED" "$(objdump -p bin/$b | awk '/NEEDED/{print $2}' | tr '\n' ' ')"
done
bin/openroad -version
bin/sta -version || true

#********************************************************************
#* Manifest and tarball (same layout as the CMake build)
#********************************************************************
cat > ${INSTALL_PREFIX}/openroad-manifest.json << EOF
{
  "components": {
    "openroad": "$(cd ${root}/OpenROAD && git rev-parse HEAD)",
    "build-system": "bazel",
    "build-script-checksum": "$(cat ${root}/scripts/build-bazel.sh | sha256sum | cut -d' ' -f1)"
  },
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "release_tag": "${rls_version}"
}
EOF
cp ${INSTALL_PREFIX}/openroad-manifest.json ${root}/release/openroad-manifest.json
cp ${root}/export.envrc ${INSTALL_PREFIX}/export.envrc

cd ${root}/release
tar czf openroad-${rls_plat}-${rls_version}.tar.gz openroad
metric "Tarball size" "$(du -h openroad-${rls_plat}-${rls_version}.tar.gz | cut -f1)"

cat ${metrics}
echo "Build complete: openroad-${rls_plat}-${rls_version}.tar.gz"
