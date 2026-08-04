#!/bin/bash
# 文件下载函数
# Author: DMP OPS
#
# 说明: 提供可靠的文件下载能力，支持多源容错、断点续传、完整性校验

Download_src() {
  local filename="${src_url##*/}"
  
  # 检测是否为伪文件（之前下载失败的 HTML 错误页）
  if [ -e "${filename}" ]; then
    local sz=$(wc -c < "${filename}" 2>/dev/null | tr -d ' ')
    if [ -n "$sz" ] && [ "$sz" -lt 1000 ]; then
      if grep -qi "<html>\|404 Not Found\|301 Moved" "${filename}" 2>/dev/null; then
        rm -f "${filename}"
      fi
    fi
  fi

  # 如果文件已存在且有效，直接返回
  if [ -s "${filename}" ]; then
    echo "[${CMSG}${filename}${CEND}] found"
    return 0
  fi

  # 构建 URL 回退数组
  local urls=()
  
  # 1. 主镜像源
  local oneinstack_url="https://mirrors.oneinstack.com/oneinstack/src/${filename}"
  urls+=("${oneinstack_url}")
  
  # 2. 原始请求 URL（如果不同）
  if [ "${src_url}" != "${oneinstack_url}" ]; then
    urls+=("${src_url}")
  fi

  # 3. 备用镜像
  urls+=("https://mirrors.linuxeye.com/oneinstack/src/${filename}")

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
    echo "${CFAILURE}Auto download failed! You can manually download ${src_url} into the src directory.${CEND}"
    if [ "$1" != "no_kill" ]; then
      kill -9 $$; exit 1;
    fi
  fi
}

# MD5 校验函数
Verify_MD5() {
  local filename=$1
  local expected_md5=$2
  
  if [ -z "${expected_md5}" ]; then
    return 0
  fi
  
  local actual_md5=$(md5sum "${filename}" 2>/dev/null | awk '{print $1}')
  if [ "${actual_md5}" == "${expected_md5}" ]; then
    echo "[${CSUCCESS}${filename}${CEND}] MD5 verified"
    return 0
  else
    echo "${CFAILURE}MD5 mismatch for ${filename}!${CEND}"
    echo "Expected: ${expected_md5}"
    echo "Actual:   ${actual_md5}"
    return 1
  fi
}
