#!/bin/bash
# Check if any tracked components have changed since the last release
# Outputs: has_changes=true/false

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Checking for component changes"
echo "========================================="

# Temporary directory for manifest download
TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

#********************************************************************
#* Fetch current component versions
#********************************************************************
echo -e "\n${YELLOW}Fetching current component versions...${NC}"

# OpenROAD master branch commit
echo "  Fetching OpenROAD master commit..."
OPENROAD_SHA=$(git ls-remote --heads https://github.com/The-OpenROAD-Project/OpenROAD.git master | cut -f1)
if [ -z "$OPENROAD_SHA" ]; then
    echo -e "${RED}ERROR: Failed to fetch OpenROAD master commit${NC}"
    exit 1
fi
echo "    OpenROAD: $OPENROAD_SHA"

# OpenROAD-flow-scripts 26Q1 tag commit
echo "  Fetching OpenROAD-flow-scripts 26Q1 commit..."
FLOW_SCRIPTS_SHA=$(git ls-remote --tags https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git refs/tags/26Q1 | cut -f1)
if [ -z "$FLOW_SCRIPTS_SHA" ]; then
    echo -e "${RED}ERROR: Failed to fetch OpenROAD-flow-scripts 26Q1 commit${NC}"
    exit 1
fi
echo "    OpenROAD-flow-scripts: $FLOW_SCRIPTS_SHA"

# Build script checksum
echo "  Calculating build script checksum..."
SCRIPT_CHECKSUM=$(cat scripts/build.sh ivpm.yaml .github/workflows/ci.yml | sha256sum | cut -d' ' -f1)
echo "    Build scripts: $SCRIPT_CHECKSUM"

TCL_VERSION="8.6.16"
echo "    Tcl: $TCL_VERSION"

#********************************************************************
#* Try to fetch last release manifest
#********************************************************************
echo -e "\n${YELLOW}Fetching last release manifest...${NC}"

MANIFEST_FOUND=false
LAST_MANIFEST="${TMPDIR}/openroad-manifest.json"

# Try to download manifest from latest release
if command -v gh &> /dev/null; then
    if gh release download --repo "$GITHUB_REPOSITORY" \
        --pattern "openroad-manifest.json" \
        --dir "${TMPDIR}" 2>/dev/null; then
        MANIFEST_FOUND=true
        echo -e "${GREEN}✓ Found last release manifest${NC}"
        cat "${LAST_MANIFEST}" | jq '.' 2>/dev/null || cat "${LAST_MANIFEST}"
    else
        echo -e "${YELLOW}ℹ No previous release found (first build)${NC}"
    fi
else
    echo -e "${YELLOW}ℹ 'gh' CLI not available, will assume changes exist${NC}"
fi

#********************************************************************
#* Compare versions
#********************************************************************
echo -e "\n${YELLOW}Comparing versions...${NC}"

HAS_CHANGES=false

if [ "$MANIFEST_FOUND" = false ]; then
    echo -e "${GREEN}✓ No previous manifest found - changes detected (proceeding with build)${NC}"
    HAS_CHANGES=true
else
    # Extract last versions from manifest
    LAST_OPENROAD=$(jq -r '.components.openroad' "${LAST_MANIFEST}" 2>/dev/null || echo "")
    LAST_FLOW_SCRIPTS=$(jq -r '.components."openroad-flow-scripts"' "${LAST_MANIFEST}" 2>/dev/null || echo "")
    LAST_TCL=$(jq -r '.components.tcl' "${LAST_MANIFEST}" 2>/dev/null || echo "")
    LAST_SCRIPT_CHECKSUM=$(jq -r '.components."build-script-checksum"' "${LAST_MANIFEST}" 2>/dev/null || echo "")

    if [ -z "$LAST_OPENROAD" ]; then
        echo -e "${YELLOW}ℹ Could not parse previous manifest - assuming changes exist${NC}"
        HAS_CHANGES=true
    else
        # Check each component
        CHANGES=()
        
        if [ "$OPENROAD_SHA" != "$LAST_OPENROAD" ]; then
            CHANGES+=("OpenROAD: $LAST_OPENROAD → $OPENROAD_SHA")
        fi
        
        if [ "$FLOW_SCRIPTS_SHA" != "$LAST_FLOW_SCRIPTS" ]; then
            CHANGES+=("OpenROAD-flow-scripts: $LAST_FLOW_SCRIPTS → $FLOW_SCRIPTS_SHA")
        fi
        
        if [ "$TCL_VERSION" != "$LAST_TCL" ]; then
            CHANGES+=("Tcl: $LAST_TCL → $TCL_VERSION")
        fi
        
        if [ "$SCRIPT_CHECKSUM" != "$LAST_SCRIPT_CHECKSUM" ]; then
            CHANGES+=("Build scripts: $LAST_SCRIPT_CHECKSUM → $SCRIPT_CHECKSUM")
        fi
        
        if [ ${#CHANGES[@]} -gt 0 ]; then
            HAS_CHANGES=true
            echo -e "${GREEN}✓ Changes detected:${NC}"
            for change in "${CHANGES[@]}"; do
                echo "    • $change"
            done
        else
            echo -e "${YELLOW}ℹ No changes detected in tracked components${NC}"
            HAS_CHANGES=false
        fi
    fi
fi

#********************************************************************
#* Output result
#********************************************************************
echo -e "\n========================================="
if [ "$HAS_CHANGES" = true ]; then
    echo -e "${GREEN}Result: CHANGES DETECTED - proceeding with build${NC}"
    echo "has_changes=true" >> "${GITHUB_OUTPUT}"
else
    echo -e "${YELLOW}Result: NO CHANGES - skipping build${NC}"
    echo "has_changes=false" >> "${GITHUB_OUTPUT}"
fi
echo "========================================="

exit 0
