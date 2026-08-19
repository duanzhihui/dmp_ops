#!/bin/bash
# 下载函数（仅 install_method=source 时使用）
# 项目: dmp_ops/chrony
# 用法: src_url="https://..." && Download_src

Download_src() {
  local src_file="${src_url##*/}"
  local retry=2
  local success=0

  mkdir -p "${src_dir}"

  # 已存在且大小正常则跳过
  if [ -f "${src_dir}/${src_file}" ]; then
    local exist_size=$(stat -c%s "${src_dir}/${src_file}" 2>/dev/null || echo 0)
    if [ "${exist_size}" -gt 102400 ]; then
      echo "${CWARNING}${src_file} already exists, skipping download${CEND}"
      return 0
    fi
    rm -f "${src_dir}/${src_file}"
  fi

  echo "${CMSG}Downloading ${src_file} ...${CEND}"

  # 多源容错
  local urls=(
    "${src_url}"
    "https://chrony-project.org/releases/${src_file}"
    "https://download.tuxfamily.org/chrony/${src_file}"
    "https://mirrors.ustc.edu.cn/chrony/${src_file}"
  )

  for url in "${urls[@]}"; do
    [ -z "${url}" ] && continue
    echo "Trying: ${url}"
    for ((i=1; i<=retry; i++)); do
      wget -c --timeout=30 --tries=1 -O "${src_dir}/${src_file}" "${url}" 2>&1
      if [ $? -eq 0 ]; then
        # 检测是否为 HTML 错误页
        local file_size=$(stat -c%s "${src_dir}/${src_file}" 2>/dev/null || echo 0)
        if [ "${file_size}" -lt 1024 ] && grep -qiE 'html|error|not found' "${src_dir}/${src_file}" 2>/dev/null; then
          echo "${CWARNING}Downloaded file appears to be an error page, retrying ...${CEND}"
          rm -f "${src_dir}/${src_file}"
          continue
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
