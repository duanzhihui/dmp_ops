#!/bin/bash
# Adoptium(Eclipse Temurin) 仓库配置
# 项目: dmp_ops/openjdk
#
# 用于发行版仓库缺少对应 OpenJDK 版本时的兜底安装
# 参考: oneinstack/include/openjdk-8.sh / openjdk-17.sh

Add_Adoptium_Repo() {
  if [ "${Family}" == 'rhel' ]; then
    if [ -e "/etc/yum.repos.d/adoptium.repo" ]; then
      echo "${CMSG}Adoptium yum repo already configured${CEND}"
    else
      echo "${CMSG}Configuring Adoptium yum repo...${CEND}"
      cat > /etc/yum.repos.d/adoptium.repo << EOF
[Adoptium]
name=Adoptium
baseurl=${adoptium_rpm_mirror}/rhel\$releasever-\$basearch/
enabled=1
gpgcheck=0
EOF
    fi
    ${PM} clean all > /dev/null 2>&1
    ${PM} makecache > /dev/null 2>&1
  else
    if [ -n "$(grep -rl 'Adoptium\|adoptium' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null)" ]; then
      echo "${CMSG}Adoptium apt repo already configured${CEND}"
      apt-get -y update > /dev/null 2>&1
      return 0
    fi
    echo "${CMSG}Configuring Adoptium apt repo...${CEND}"
    # GPG 公钥优先使用随包提供的本地文件，避免网络受限
    if [ -s "${openjdk_dir}/src/adoptium.key" ]; then
      cat "${openjdk_dir}/src/adoptium.key" | apt-key add - > /dev/null 2>&1
    else
      wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | apt-key add - > /dev/null 2>&1
    fi
    if [ $? -ne 0 ]; then
      echo "${CWARNING}Failed to import Adoptium GPG key, repo may be untrusted${CEND}"
    fi
    apt-add-repository --yes "${adoptium_deb_mirror}" > /dev/null 2>&1
    apt-get -y update > /dev/null 2>&1
  fi
  return 0
}

Del_Adoptium_Repo() {
  if [ "${Family}" == 'rhel' ]; then
    [ -e "/etc/yum.repos.d/adoptium.repo" ] && {
      rm -f /etc/yum.repos.d/adoptium.repo
      echo "${CMSG}Adoptium yum repo removed${CEND}"
    }
  else
    local f
    for f in $(grep -rl 'Adoptium/deb\|adoptium' /etc/apt/sources.list.d/ 2>/dev/null); do
      rm -f "${f}"
      echo "${CMSG}Removed ${f}${CEND}"
    done
    sed -i '/[Aa]doptium/d' /etc/apt/sources.list 2>/dev/null
    apt-get -y update > /dev/null 2>&1
  fi
  return 0
}
