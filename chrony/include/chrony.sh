#!/bin/bash
# chrony 安装/卸载模块
# 项目: dmp_ops/chrony
# 核心函数: Install_Chrony / Print_Chrony / Uninstall_Chrony

# 包管理器安装
Install_Chrony_Package() {
  echo "${CMSG}使用包管理器安装 chrony ...${CEND}"
  case "${PM}" in
    yum|dnf)
      ${PM} -y install chrony
      ;;
    apt-get)
      DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive apt-get -y install chrony
      ;;
    *)
      echo "${CFAILURE}未知包管理器: ${PM}${CEND}"
      return 1
      ;;
  esac
  return $?
}

# 源码编译安装
Install_Chrony_Source() {
  echo "${CMSG}源码编译安装 chrony-${chrony_ver} ...${CEND}"

  # 编译依赖
  case "${PM}" in
    yum|dnf)
      ${PM} -y install gcc make bison pkgconfig nss-devel libcap-devel > /dev/null 2>&1
      ;;
    apt-get)
      DEBIAN_FRONTEND=noninteractive apt-get -y install gcc make bison pkg-config libcap-dev libnss3-dev > /dev/null 2>&1
      ;;
  esac

  src_url="https://chrony-project.org/releases/chrony-${chrony_ver}.tar.gz"
  Download_src || return 1

  pushd "${src_dir}" > /dev/null
  rm -rf "chrony-${chrony_ver}"
  tar xzf "chrony-${chrony_ver}.tar.gz" || { popd > /dev/null; return 1; }
  pushd "chrony-${chrony_ver}" > /dev/null
  ./configure --prefix=/usr/local/chrony --sysconfdir=/etc --localstatedir=/var || {
    popd > /dev/null; popd > /dev/null; return 1
  }
  make -j "${THREAD}" && make install
  local rc=$?
  popd > /dev/null
  rm -rf "chrony-${chrony_ver}"
  popd > /dev/null
  [ ${rc} -ne 0 ] && return 1

  # 源码安装不会创建运行用户与 systemd unit
  id -u chrony > /dev/null 2>&1 || useradd -M -s /sbin/nologin chrony
  mkdir -p /var/lib/chrony /var/log/chrony /run/chrony
  chown -R chrony:chrony /var/lib/chrony /var/log/chrony /run/chrony

  /bin/cp -f "${script_dir}/init.d/chronyd.service" /lib/systemd/system/chronyd.service
  systemctl daemon-reload
  chrony_service=chronyd
  Set_Option chrony_service chronyd

  # 软链到标准路径，方便 chronyc/chronyd 直接调用
  ln -sf /usr/local/chrony/sbin/chronyd /usr/sbin/chronyd
  ln -sf /usr/local/chrony/bin/chronyc /usr/bin/chronyc
  return 0
}

# 主安装流程
Install_Chrony() {
  echo ""
  echo "${CMSG}========== 开始安装 Chrony (role=${chrony_role}, mode=${deploy_mode}) ==========${CEND}"

  # 1. 容器环境拦截
  Check_Container || { kill -9 $$; exit 1; }

  # 2. 路径适配
  Detect_Chrony_Path

  # 3. 停用冲突服务 + 统一时区
  Check_Conflict_Service
  Check_Timezone
  Check_SELinux

  # 4. 幂等检测：已安装则只更新配置
  local installed=0
  command -v chronyd > /dev/null 2>&1 && installed=1

  if [ ${installed} -eq 1 ] && [ "${force_reinstall}" != 'y' ]; then
    echo "${CWARNING}Chrony 已安装: $(chronyd -v 2>/dev/null | head -1)${CEND}"
    echo "${CMSG}跳过软件包安装，仅更新配置（如需重装请加 --force）${CEND}"
  else
    case "${install_method}" in
      package)
        Install_Chrony_Package || {
          echo "${CFAILURE}Chrony 安装失败！${CEND}"
          grep -Ew 'NAME|ID|VERSION_ID|PRETTY_NAME' /etc/os-release
          kill -9 $$; exit 1
        }
        ;;
      source)
        Install_Chrony_Source || {
          echo "${CFAILURE}Chrony 源码编译安装失败！${CEND}"
          kill -9 $$; exit 1
        }
        ;;
      *)
        echo "${CFAILURE}未知的 install_method: ${install_method}（可选 package/source）${CEND}"
        kill -9 $$; exit 1
        ;;
    esac
    # 安装后路径可能变化，重新探测
    Detect_Chrony_Path
  fi

  # 5. 探测上游源连通性（仅提示）
  if [ "${chrony_role}" == 'server' ]; then
    Check_Network "${upstream_ntp_servers}"
  else
    [ "${deploy_mode}" == 'cluster' ] && Check_Network "${ntp_server_hosts}" \
                                      || Check_Network "${upstream_ntp_servers}"
  fi

  # 6. 生成并应用配置
  mkdir -p /var/log/chrony
  [ -n "${chrony_user}" ] && chown -R "${chrony_user}":"${chrony_user}" /var/log/chrony 2>/dev/null
  Apply_Role_Conf || {
    echo "${CFAILURE}配置应用失败，安装中止${CEND}"
    kill -9 $$; exit 1
  }

  # 7. 防火墙放行（Server 角色）
  Check_Firewall

  # 8. 开机自启 + 启动
  systemctl enable "${chrony_service}" > /dev/null 2>&1
  systemctl restart "${chrony_service}" > /dev/null 2>&1
  sleep 3

  # 9. 强制立即校时
  if [ "${force_makestep}" == 'y' ]; then
    echo "${CWARNING}执行 chronyc makestep 强制校时（时间跳变，运行中的数据库/中间件请注意）${CEND}"
    chronyc makestep > /dev/null 2>&1
    sleep 2
  fi

  # 10. 安装后验证
  Verify_Chrony
}

# 安装后验证
Verify_Chrony() {
  if ! systemctl is-active --quiet "${chrony_service}"; then
    echo "${CFAILURE}Chrony 服务未运行！${CEND}"
    journalctl -u "${chrony_service}" -n 30 --no-pager 2>/dev/null
    kill -9 $$; exit 1
  fi

  if ! chronyc tracking > /dev/null 2>&1; then
    echo "${CFAILURE}chronyc tracking 无响应，安装可能存在问题${CEND}"
    journalctl -u "${chrony_service}" -n 30 --no-pager 2>/dev/null
    kill -9 $$; exit 1
  fi

  local leap stratum refid
  leap=$(chronyc tracking 2>/dev/null | awk -F': *' '/Leap status/{print $2}')
  stratum=$(chronyc tracking 2>/dev/null | awk -F': *' '/Stratum/{print $2}')
  refid=$(chronyc tracking 2>/dev/null | awk -F': *' '/Reference ID/{print $2}')

  echo ""
  echo "${CSUCCESS}========== Chrony 安装完成 ==========${CEND}"
  echo "  版本      : $(chronyd -v 2>/dev/null | head -1)"
  echo "  角色      : ${chrony_role}"
  echo "  部署模式  : ${deploy_mode}"
  echo "  配置文件  : ${chrony_conf}"
  echo "  服务名    : ${chrony_service}"
  echo "  时区      : $(timedatectl show -p Timezone --value 2>/dev/null)"
  echo "  系统时间  : $(date '+%F %T %Z')"
  if [ "${chrony_role}" == 'server' ]; then
    echo "  上游源    : ${upstream_ntp_servers}"
    echo "  允许网段  : ${allow_networks}"
    [ -n "${peer_servers}" ] && echo "  对等 Server: ${peer_servers}"
    echo "  孤岛层级  : stratum ${local_stratum}"
  else
    [ "${deploy_mode}" == 'cluster' ] && echo "  内网 Server: ${ntp_server_hosts}" \
                                      || echo "  上游源    : ${upstream_ntp_servers}"
  fi
  echo "  同步状态  : Leap=${leap} Stratum=${stratum} RefID=${refid}"
  echo ""
  echo "${CMSG}---- chronyc sources -v ----${CEND}"
  chronyc sources -v 2>/dev/null
  echo ""

  if [ "${leap}" != "Normal" ]; then
    echo "${CWARNING}当前 Leap status=${leap}，时钟尚未完成首次同步，可稍后执行:${CEND}"
    echo "${CWARNING}  chronyc sources -v && chronyc tracking${CEND}"
  fi
  return 0
}

# 卸载预览
Print_Chrony() {
  echo "${CMSG}以下内容将被停止/备份/删除:${CEND}"
  echo "  systemd 服务  : ${chrony_service}（stop + disable）"
  [ -f "${chrony_conf}" ]      && echo "  配置文件      : ${chrony_conf}（备份后恢复为 .orig）"
  [ -f "${chrony_keys}" ]      && echo "  密钥文件      : ${chrony_keys}（保留）"
  [ -f "${drift_file}" ]       && echo "  漂移文件      : ${drift_file}（保留）"
  [ -d /var/log/chrony ]       && echo "  日志目录      : /var/log/chrony（重命名备份）"
  if [ "${keep_package}" == 'y' ]; then
    echo "  软件包        : 保留（--keep_package）"
  else
    echo "  软件包        : 卸载 chrony"
  fi
  [ "${chrony_role}" == 'server' ] && echo "  防火墙        : 收回 123/udp 放行"
  echo ""
  echo "${CWARNING}注意: 卸载后系统将没有时间同步服务，时钟会逐渐漂移${CEND}"
}

# 执行卸载
Uninstall_Chrony() {
  echo "${CMSG}正在卸载 Chrony ...${CEND}"

  systemctl stop "${chrony_service}" > /dev/null 2>&1
  systemctl disable "${chrony_service}" > /dev/null 2>&1

  # 配置文件：重命名备份而非直接删除
  if [ "${keep_conf}" != 'y' ] && [ -f "${chrony_conf}" ]; then
    /bin/mv "${chrony_conf}"{,."$(date +%Y%m%d%H%M%S)"}
    echo "${CMSG}配置已备份为 ${chrony_conf}.$(date +%Y%m%d)*${CEND}"
    # 恢复发行版原始配置
    if [ -f "${chrony_conf}.orig" ]; then
      /bin/cp -p "${chrony_conf}.orig" "${chrony_conf}"
      echo "${CMSG}已恢复发行版原始配置${CEND}"
    fi
  fi

  # 日志目录备份
  [ -d /var/log/chrony ] && /bin/mv /var/log/chrony{,."$(date +%Y%m%d%H)"} 2>/dev/null

  # 卸载软件包
  if [ "${keep_package}" != 'y' ]; then
    case "${PM}" in
      yum|dnf)   ${PM} -y remove chrony > /dev/null 2>&1 ;;
      apt-get)   DEBIAN_FRONTEND=noninteractive apt-get -y purge chrony > /dev/null 2>&1 ;;
    esac
    # 源码安装的残留
    [ -d /usr/local/chrony ] && /bin/mv /usr/local/chrony{,."$(date +%Y%m%d%H)"}
    [ -f /lib/systemd/system/chronyd.service ] && [ "${install_method}" == 'source' ] && {
      rm -f /lib/systemd/system/chronyd.service
      systemctl daemon-reload
    }
  fi

  # 收回防火墙放行
  Close_Firewall

  echo ""
  echo "${CSUCCESS}Chrony 卸载完成！${CEND}"
  echo "${CWARNING}系统当前无时间同步服务，如需回退到 systemd-timesyncd 请执行:${CEND}"
  echo "${CWARNING}  timedatectl set-ntp true${CEND}"
}
