#!/bin/bash
# OpenJDK tar.gz 二进制安装实现(Eclipse Temurin / Adoptium)
# 项目: dmp_ops/openjdk
#
# 提供函数:
#   Get_Adoptium_URL     解析下载地址与文件名(设置 src_url / src_file / download_urls)
#   Install_JDK_Binary   下载解压到 ${jdk_base_dir}/jdk-{ver}
#   Uninstall_JDK_Binary 目录重命名备份 / 删除

# 解析 Adoptium 下载信息
# 注意: Adoptium API 的架构名为 x64/aarch64，与发行版包的 amd64/arm64 不同
Get_Adoptium_URL() {
  local ver=$1
  local patch=$2      # 可选，形如 21.0.7+6 / 8u462-b08
  src_url=""
  src_file=""
  download_urls=()

  local api_json api_link api_name
  if [ -n "${patch}" ]; then
    # 锁定补丁版本
    local release_name="jdk-${patch}"
    [[ "${patch}" =~ ^8u ]] && release_name="jdk${patch}"
    api_json=$(curl -s --connect-timeout 15 --max-time 30 \
      "${adoptium_api}/assets/version/${release_name}?architecture=${API_ARCH}&image_type=jdk&os=linux&vendor=eclipse&jvm_impl=hotspot&heap_size=normal&page_size=1" 2>/dev/null)
    src_url="${adoptium_api}/binary/version/${release_name}/linux/${API_ARCH}/jdk/hotspot/normal/eclipse"
  else
    api_json=$(curl -s --connect-timeout 15 --max-time 30 \
      "${adoptium_api}/assets/latest/${ver}/hotspot?architecture=${API_ARCH}&image_type=jdk&os=linux&vendor=eclipse" 2>/dev/null)
    src_url="${adoptium_api}/binary/latest/${ver}/ga/linux/${API_ARCH}/jdk/hotspot/normal/eclipse"
  fi

  # 从 API 响应中解析真实下载链接与文件名(GitHub Release 直链)
  api_link=$(echo "${api_json}" | grep -o '"link":"[^"]*jdk_[^"]*\.tar\.gz"' | head -1 | awk -F'"' '{print $4}')
  api_name=$(echo "${api_json}" | grep -o '"name":"OpenJDK[^"]*jdk_[^"]*\.tar\.gz"' | head -1 | awk -F'"' '{print $4}')

  if [ -n "${api_name}" ]; then
    src_file="${api_name}"
  else
    # API 不可用时的通用命名(仅用于本地保存)
    src_file="OpenJDK${ver}U-jdk_${API_ARCH}_linux_hotspot.tar.gz"
  fi

  # 备用源: API 解析出的直链 → 清华 Adoptium 文件镜像
  [ -n "${api_link}" ] && download_urls+=("${api_link}")
  [ -n "${api_name}" ] && download_urls+=("${adoptium_file_mirror}/${ver}/jdk/${API_ARCH}/linux/${api_name}")

  echo "${CMSG}Adoptium package: ${src_file}${CEND}"
}

Install_JDK_Binary() {
  local ver=$1
  local patch_var="jdk${ver}_patch_ver"
  local patch="${jdk_patch_ver:-${!patch_var}}"

  Check_Net > /dev/null 2>&1
  Get_Adoptium_URL ${ver} "${patch}"

  pushd "${openjdk_dir}/src" > /dev/null 2>&1 || {
    mkdir -p "${openjdk_dir}/src"
    pushd "${openjdk_dir}/src" > /dev/null
  }

  Download_src || { popd > /dev/null; return 1; }

  echo "${CMSG}Extracting ${src_file} ...${CEND}"
  local unpack_dir=$(tar tzf "${src_file}" 2>/dev/null | head -1 | cut -d/ -f1)
  [ -z "${unpack_dir}" ] && {
    echo "${CFAILURE}Invalid tarball: ${src_file}${CEND}"
    popd > /dev/null; return 1
  }
  rm -rf "${unpack_dir}"
  tar xzf "${src_file}" || { popd > /dev/null; return 1; }

  local target="${jdk_base_dir}/jdk-${ver}"
  mkdir -p "${jdk_base_dir}"
  # 已存在同版本目录: 先重命名备份，绝不直接删除
  [ -d "${target}" ] && /bin/mv "${target}"{,_$(date +%Y%m%d%H)}
  /bin/mv "${unpack_dir}" "${target}"
  rm -rf "${unpack_dir}"
  popd > /dev/null

  java_home="${target}"
  [ -x "${java_home}/bin/java" ] && return 0
  return 1
}

Uninstall_JDK_Binary() {
  local ver=$1
  local target="${jdk_base_dir}/jdk-${ver}"
  [ ! -d "${target}" ] && return 0

  # 数据保护: 重命名备份而非直接 rm
  local bak="${target}_uninstall_$(date +%Y%m%d%H)"
  /bin/mv "${target}" "${bak}"
  if [ "${keep_backup}" == 'y' ]; then
    echo "${CMSG}Backup kept at: ${bak}${CEND}"
  else
    rm -rf "${bak}"
  fi
  return 0
}
