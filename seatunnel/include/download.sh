#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Download Functions
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

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
  
  # 1. Add mirrors.oneinstack.com as primary
  local oneinstack_url="https://mirrors.oneinstack.com/oneinstack/src/${filename}"
  urls+=("${oneinstack_url}")
  
  # 2. Add the requested src_url if it's different
  if [ "${src_url}" != "${oneinstack_url}" ]; then
    urls+=("${src_url}")
  fi

  # 3. Add Apache archive as backup for SeaTunnel
  if [[ "${filename}" == *"seatunnel"* ]]; then
    local version=$(echo "${filename}" | grep -oP '\d+\.\d+\.\d+')
    if [ -n "${version}" ]; then
      urls+=("https://archive.apache.org/dist/seatunnel/${version}/${filename}")
      urls+=("https://dlcdn.apache.org/seatunnel/${version}/${filename}")
    fi
  fi

  local success=0
  for url in "${urls[@]}"; do
    echo "${CMSG}Downloading from: ${url}${CEND}"
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
    echo "${CFAILURE}Auto download failed! You can manually download ${src_url} into the src directory.${CEND}"
    if [ "$1" != "no_kill" ]; then
      kill -9 $$; exit 1;
    fi
  fi
}

Download_SeaTunnel() {
  local version=${1:-${seatunnel_ver}}
  local filename="apache-seatunnel-${version}-bin.tar.gz"
  
  src_url="https://archive.apache.org/dist/seatunnel/${version}/${filename}"
  Download_src
}
