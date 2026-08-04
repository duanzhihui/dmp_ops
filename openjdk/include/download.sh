#!/bin/bash
# 下载函数(多源容错)
# 项目: dmp_ops/openjdk
#
# 用法:
#   src_url="https://..."            # 主地址(必填)
#   src_file="xxx.tar.gz"            # 保存文件名(可选，默认取 URL 末段)
#   download_urls=(url1 url2 ...)    # 备用地址列表(可选)
#   Download_src

Download_src() {
  [ -z "${src_url}" ] && { echo "${CFAILURE}src_url is empty${CEND}"; return 1; }
  [ -z "${src_file}" ] && src_file="${src_url##*/}"
  [ -z "${src_dir}" ] && src_dir="${openjdk_dir}/src"
  mkdir -p "${src_dir}"

  # 本地已有完整包则直接复用(离线安装场景)
  if [ -f "${src_dir}/${src_file}" ]; then
    local exist_size=$(stat -c%s "${src_dir}/${src_file}" 2>/dev/null || echo 0)
    if [ "${exist_size}" -gt 1048576 ]; then
      echo "${CWARNING}${src_file} already exists in ${src_dir}, skipping download${CEND}"
      return 0
    fi
    rm -f "${src_dir}/${src_file}"
  fi

  echo "${CMSG}Downloading ${src_file}...${CEND}"

  local urls=("${src_url}")
  local u
  for u in "${download_urls[@]}"; do
    [ -n "${u}" ] && [ "${u}" != "${src_url}" ] && urls+=("${u}")
  done

  for u in "${urls[@]}"; do
    [ -z "${u}" ] && continue
    echo "Trying: ${u}"
    wget -c -L --timeout=30 --tries=2 -O "${src_dir}/${src_file}" "${u}" 2>&1
    if [ $? -eq 0 ]; then
      local file_size=$(stat -c%s "${src_dir}/${src_file}" 2>/dev/null || echo 0)
      # 小于 1KB 且含 HTML 标签，视为错误页
      if [ "${file_size}" -lt 1024 ] && grep -qiE '<html|<!doctype|404 not found' "${src_dir}/${src_file}" 2>/dev/null; then
        echo "${CWARNING}Got an error page from ${u}, try next source${CEND}"
        rm -f "${src_dir}/${src_file}"
        continue
      fi
      # JDK 包不可能小于 1MB
      if [ "${file_size}" -lt 1048576 ]; then
        echo "${CWARNING}File too small (${file_size} bytes), try next source${CEND}"
        rm -f "${src_dir}/${src_file}"
        continue
      fi
      echo "${CSUCCESS}Download successful: ${src_file}${CEND}"
      return 0
    fi
    rm -f "${src_dir}/${src_file}"
  done

  echo "${CFAILURE}Download failed: ${src_file}${CEND}"
  echo "Please download it manually and place it in: ${src_dir}/${src_file}"
  echo "URL: ${src_url}"
  return 1
}

# 下载并校验 sha256(Adoptium 提供 .sha256.txt)
Download_src_with_checksum() {
  Download_src || return 1

  local sum_url="${1}"
  [ -z "${sum_url}" ] && return 0

  if curl -s --connect-timeout 15 -o "${src_dir}/${src_file}.sha256" "${sum_url}" 2>/dev/null; then
    local expect=$(awk '{print $1}' "${src_dir}/${src_file}.sha256" 2>/dev/null)
    local actual=$(sha256sum "${src_dir}/${src_file}" 2>/dev/null | awk '{print $1}')
    rm -f "${src_dir}/${src_file}.sha256"
    if [ -n "${expect}" ] && [ "${expect}" == "${actual}" ]; then
      echo "${CSUCCESS}Checksum verification passed${CEND}"
      return 0
    fi
    if [ -n "${expect}" ]; then
      echo "${CFAILURE}Checksum mismatch! expect=${expect} actual=${actual}${CEND}"
      return 1
    fi
  fi
  echo "${CWARNING}Checksum file unavailable, skip verification${CEND}"
  return 0
}
