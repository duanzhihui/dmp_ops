#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Download helper functions
#
# Package format: apache-dolphinscheduler-<ver>-bin.tar.gz

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
    urls+=("${src_url/downloads.apache.org\/dolphinscheduler/archive.apache.org\/dist\/dolphinscheduler}")
  fi

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

# Download DolphinScheduler package
# Package: apache-dolphinscheduler-<ver>-bin.tar.gz
Download_DolphinScheduler() {
  local ds_ver=$1
  local ds_pkg="apache-dolphinscheduler-${ds_ver}-bin.tar.gz"

  pushd ${ds_dir}/src > /dev/null

  src_url="${mirror_link}/${ds_ver}/${ds_pkg}"
  Download_src

  popd > /dev/null
}

# Get the package filename for a given version
Get_DolphinScheduler_Pkg() {
  local ds_ver=$1
  echo "apache-dolphinscheduler-${ds_ver}-bin.tar.gz"
}

# Download MySQL JDBC Driver
Download_MySQL_JDBC() {
  local jdbc_ver=${mysql_jdbc_ver:-8.0.33}
  local jdbc_pkg="mysql-connector-j-${jdbc_ver}.tar.gz"

  pushd ${ds_dir}/src > /dev/null

  if [ -s "${jdbc_pkg}" ]; then
    echo "[${CMSG}${jdbc_pkg}${CEND}] found"
    popd > /dev/null
    return 0
  fi

  src_url="https://dev.mysql.com/get/Downloads/Connector-J/${jdbc_pkg}"
  Download_src "no_kill"

  # Fallback to Maven repository
  if [ ! -s "${jdbc_pkg}" ]; then
    local jar_file="mysql-connector-j-${jdbc_ver}.jar"
    src_url="https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${jdbc_ver}/${jar_file}"
    echo "Trying Maven repository..."
    wget --limit-rate=100M --tries=3 -c --no-check-certificate "${src_url}"
  fi

  popd > /dev/null
}

# Extract MySQL JDBC Driver jar
Extract_MySQL_JDBC() {
  local jdbc_ver=${mysql_jdbc_ver:-8.0.33}
  local jdbc_pkg="mysql-connector-j-${jdbc_ver}.tar.gz"
  local jdbc_jar="mysql-connector-j-${jdbc_ver}.jar"
  local target_dir=$1

  pushd ${ds_dir}/src > /dev/null

  if [ -f "${jdbc_jar}" ]; then
    cp -f "${jdbc_jar}" "${target_dir}/"
    echo "${CSUCCESS}Copied ${jdbc_jar} to ${target_dir}${CEND}"
  elif [ -f "${jdbc_pkg}" ]; then
    tar xzf "${jdbc_pkg}"
    if [ -f "mysql-connector-j-${jdbc_ver}/${jdbc_jar}" ]; then
      cp -f "mysql-connector-j-${jdbc_ver}/${jdbc_jar}" "${target_dir}/"
      echo "${CSUCCESS}Extracted ${jdbc_jar} to ${target_dir}${CEND}"
    fi
    rm -rf "mysql-connector-j-${jdbc_ver}"
  else
    echo "${CFAILURE}MySQL JDBC Driver not found!${CEND}"
    return 1
  fi

  popd > /dev/null
  return 0
}
