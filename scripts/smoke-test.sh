#!/bin/bash -x
#********************************************************************
#* Smoke-test a release tarball inside an arbitrary Linux container.
#* Usage: smoke-test.sh <tarball>
#* Intended to run on older/minimal distros to check portability.
#********************************************************************

set -e

tarball=$1
work=$(mktemp -d)
tar xzf ${tarball} -C ${work}
cd ${work}/openroad

cat /etc/os-release | grep PRETTY_NAME
ldd --version | head -1

# Report unresolved libraries before trying to run anything
ldd bin/openroad | grep "not found" && echo "openroad: missing shared libraries" || true
ldd bin/sta | grep "not found" && echo "sta: missing shared libraries" || true

bin/openroad -version

cat > ${work}/smoke.tcl << 'EOF'
puts "tcl: [info patchlevel]"
exit 0
EOF
bin/openroad -no_init -no_splash -exit ${work}/smoke.tcl

echo 'puts "sta tcl: [info patchlevel]"; exit 0' > ${work}/sta.tcl
bin/sta -no_init -exit ${work}/sta.tcl

echo "smoke test passed"
