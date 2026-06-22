#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Download helper functions
#
# All Doris versions (2.x, 3.x, 4.x) use a UNIFIED package:
#   apache-doris-<ver>-bin-<arch>.tar.gz
# The package contains: fe/, be/, ms/ (ms only in 3.x+), tools/ etc.

Download_src() {
  local filename="${src_url##*/}"

  # Remove pseudo-files from previous failed attempts
  if [ -e "${filename}" ]; then
    local sz=$(wc -c < "${filename}" 2>/dev/null | tr -d ' ')
    if [ -n "$sz" ] && [ "$sz" -lt 1000 ]; then
      if grep -qi "<html>\|404 Not Found\|301 Moved" "${filename}" 2>/dev/null; then
        rm -f "${filename}"
      fi
    fi
  fi

  if [ -s "${filename}" ]; then
    echo "[${CMSG}${filename}${CEND}] found"
    return 0
  fi

  # Build URL fallback array
  local urls=()
  urls+=("${src_url}")

  # Add archive mirror as fallback
  if [[ "${src_url}" == *"downloads.apache.org"* ]]; then
    urls+=("${src_url/downloads.apache.org\/doris/archive.apache.org\/dist\/doris}")
  fi

  # Add VeloDB mirror as fallback
  urls+=("${velodb_mirror_link}/${filename}")

  local success=0
  for url in "${urls[@]}"; do
    echo "Downloading from: ${url}"
    wget --limit-rate=100M --tries=3 -c --no-check-certificate "${url}"

    if [ -e "${filename}" ]; then
      local sz=$(wc -c < "${filename}" 2>/dev/null | tr -d ' ')
      if [ -n "$sz" ] && [ "$sz" -lt 1000 ]; then
        if grep -qi "<html>\|404 Not Found\|301 Moved" "${filename}" 2>/dev/null; then
          rm -f "${filename}"
          continue
        fi
      fi
      success=1
      break
    fi
  done

  if [ ${success} -eq 0 ]; then
    echo "${CFAILURE}Auto download failed! You can manually download ${filename} into the src directory.${CEND}"
    echo "${CFAILURE}Primary URL: ${src_url}${CEND}"
    if [ "$1" != "no_kill" ]; then
      kill -9 $$; exit 1;
    fi
  fi
}

# Download Doris unified package
# All versions (2.x/3.x/4.x) use: apache-doris-<ver>-bin-<arch>.tar.gz
Download_doris() {
  local doris_ver=$1
  local minor_ver=$(echo ${doris_ver} | awk -F. '{print $1"."$2}')
  local doris_pkg="apache-doris-${doris_ver}-bin-${DORIS_ARCH}.tar.gz"

  pushd ${doris_dir}/src > /dev/null

  src_url="${mirror_link}/${minor_ver}/${doris_ver}/${doris_pkg}"
  Download_src

  popd > /dev/null
}

# Get the unified package filename for a given version
Get_Doris_Pkg() {
  local doris_ver=$1
  echo "apache-doris-${doris_ver}-bin-${DORIS_ARCH}.tar.gz"
}

# Extract a component (fe/be/ms) from the unified package
# Usage: Extract_Component <doris_ver> <component> <target_dir>
#   component: fe, be, ms
Extract_Component() {
  local doris_ver=$1
  local component=$2
  local target_dir=$3
  local doris_pkg=$(Get_Doris_Pkg "${doris_ver}")

  if [ ! -f "${doris_dir}/src/${doris_pkg}" ]; then
    echo "${CFAILURE}Package ${doris_pkg} not found in ${doris_dir}/src/!${CEND}"
    echo "${CFAILURE}Please download first or place it manually.${CEND}"
    return 1
  fi

  mkdir -p ${target_dir}

  echo "${CMSG}Extracting ${component} from ${doris_pkg}...${CEND}"
  local tmp_dir=$(mktemp -d)
  tar xzf ${doris_dir}/src/${doris_pkg} -C ${tmp_dir} --strip-components=1

  if [ -d "${tmp_dir}/${component}" ]; then
    cp -rf ${tmp_dir}/${component}/* ${target_dir}/
    echo "${CSUCCESS}Extracted ${component} to ${target_dir}${CEND}"
  else
    echo "${CFAILURE}Component '${component}' not found in package ${doris_pkg}!${CEND}"
    rm -rf ${tmp_dir}
    return 1
  fi

  rm -rf ${tmp_dir}
  return 0
}
