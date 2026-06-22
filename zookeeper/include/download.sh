#!/bin/bash
# 下载函数
# 项目: oneinstack/zookeeper

# 下载源文件
# 使用方式: src_url="http://..." && Download_src
Download_src() {
  local src_file="${src_url##*/}"
  local retry=3
  local success=0
  
  # 如果文件已存在且大小正常，跳过下载
  if [ -f "${src_dir}/${src_file}" ]; then
    local file_size=$(stat -c%s "${src_dir}/${src_file}" 2>/dev/null || echo 0)
    if [ "${file_size}" -gt 1024 ]; then
      echo "${CWARNING}${src_file} already exists, skipping download${CEND}"
      return 0
    fi
  fi
  
  echo "${CMSG}Downloading ${src_file}...${CEND}"
  
  # 构建下载 URL 列表
  local urls=(
    "${src_url}"
    "${mirror_link}/zookeeper/zookeeper-${zk_ver}/${src_file}"
    "https://archive.apache.org/dist/zookeeper/zookeeper-${zk_ver}/${src_file}"
    "https://dlcdn.apache.org/zookeeper/zookeeper-${zk_ver}/${src_file}"
  )
  
  for url in "${urls[@]}"; do
    [ -z "${url}" ] && continue
    
    echo "Trying: ${url}"
    
    for ((i=1; i<=retry; i++)); do
      wget -c --timeout=30 --tries=1 -O "${src_dir}/${src_file}" "${url}" 2>&1
      
      if [ $? -eq 0 ]; then
        # 检查是否为 HTML 错误页
        local file_size=$(stat -c%s "${src_dir}/${src_file}" 2>/dev/null || echo 0)
        if [ "${file_size}" -lt 1024 ]; then
          if grep -qi "html\|error\|not found" "${src_dir}/${src_file}" 2>/dev/null; then
            echo "${CWARNING}Downloaded file appears to be an error page, retrying...${CEND}"
            rm -f "${src_dir}/${src_file}"
            continue
          fi
        fi
        
        echo "${CSUCCESS}Download successful: ${src_file}${CEND}"
        success=1
        break 2
      fi
    done
  done
  
  if [ "${success}" -ne 1 ]; then
    echo "${CFAILURE}Download failed: ${src_file}${CEND}"
    echo "Please download manually and place in: ${src_dir}/"
    echo "URL: ${src_url}"
    return 1
  fi
  
  return 0
}

# 下载并校验
Download_src_with_checksum() {
  Download_src || return 1
  
  local src_file="${src_url##*/}"
  local checksum_url="${src_url}.sha512"
  
  # 下载校验文件
  if wget -q -O "${src_dir}/${src_file}.sha512" "${checksum_url}" 2>/dev/null; then
    echo "Verifying checksum..."
    pushd "${src_dir}" > /dev/null
    if sha512sum -c "${src_file}.sha512" 2>/dev/null | grep -q "OK"; then
      echo "${CSUCCESS}Checksum verification passed${CEND}"
      rm -f "${src_file}.sha512"
      popd > /dev/null
      return 0
    else
      echo "${CWARNING}Checksum verification failed, but continuing...${CEND}"
      rm -f "${src_file}.sha512"
      popd > /dev/null
    fi
  fi
  
  return 0
}
