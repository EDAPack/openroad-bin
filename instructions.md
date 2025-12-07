
# OpenROAD binary release

This project is intended to create multi-platform binary 
releases of openroad and associated tools that are standalone and
not Docker (or nix) based.

Instructions for building OpenRoad are here:
https://github.com/The-OpenROAD-Project/OpenROAD/blob/master/docs/user/Build.md

You can see the structure of another package that builds a 
set of multi-platform binaries here:
https://github.com/edapack/verilator-bin

The goal is to have a build of openroad that is standalone in that
it will run on target systems without the user needing to compile
software or be admin on the system to install system libraries.

This means that tools and shared libraries that openroad depends on
must be build and included in the binary package. 

The result is a directory (the install directory) containing openroad and all runtime dependencies.

# Process
- Read the installation instructions and look at the reference project.
- Setup an initial github CI that only runs the manylinux2014 image
- Implement a build
  - Installs core development tools and dependencies
  - Fetches openroad
  - Fetches any openroad build dependencies, builds and installs them 
  - Install openroad and any runtime dependences in the install directory
  - Archives the install directory and publishes as an artifact
- Ensure that the CI will gather all install directories and publish them 
  as a unique release