#!/bin/bash
# 环境检测模块
# 项目: dmp_ops/chrony
# 功能: 冲突服务停用、时区统一、防火墙放行、SELinux 提示、上游源连通性、容器环境检测

# 检测并停用冲突的时间同步服务
# chrony 与 ntpd / systemd-timesyncd / openntpd 互斥，多个校时进程会互相抢占系统时钟
Check_Conflict_Service() {
  local found=0
  for svc in ntpd ntp systemd-timesyncd openntpd ntpsec; do
    systemctl list-unit-files 2>/dev/null | grep -qE "^${svc}\.service" || continue
    # chrony 自身在 Debian 系名为 chrony，不能误停
    [ "${svc}" == "${chrony_service}" ] && continue
    if systemctl is-active --quiet ${svc} 2>/dev/null || systemctl is-enabled --quiet ${svc} 2>/dev/null; then
      echo "${CWARNING}检测到冲突的时间同步服务 ${svc}，正在停止并禁用${CEND}"
      systemctl stop ${svc} > /dev/null 2>&1
      systemctl disable ${svc} > /dev/null 2>&1
      found=1
    fi
  done

  # 关闭 systemd-timesyncd 的 NTP 托管（存在 timedatectl 时）
  if command -v timedatectl > /dev/null 2>&1; then
    timedatectl set-ntp false > /dev/null 2>&1
  fi

  [ ${found} -eq 0 ] && echo "${CSUCCESS}[OK] 无冲突的时间同步服务${CEND}"
  return 0
}

# 统一时区
Check_Timezone() {
  [ -z "${timezone}" ] && return 0
  if ! command -v timedatectl > /dev/null 2>&1; then
    echo "${CWARNING}未找到 timedatectl，跳过时区设置${CEND}"
    return 0
  fi

  local cur_tz
  cur_tz=$(timedatectl show -p Timezone --value 2>/dev/null)
  [ -z "${cur_tz}" ] && cur_tz=$(timedatectl status 2>/dev/null | awk -F': *' '/Time zone/{print $2}' | awk '{print $1}')

  if [ "${cur_tz}" != "${timezone}" ]; then
    if timedatectl list-timezones 2>/dev/null | grep -qx "${timezone}"; then
      echo "${CMSG}调整时区: ${cur_tz} -> ${timezone}${CEND}"
      timedatectl set-timezone "${timezone}"
    else
      echo "${CWARNING}无效时区 ${timezone}，保持当前时区 ${cur_tz}${CEND}"
    fi
  else
    echo "${CSUCCESS}[OK] 时区已是 ${timezone}${CEND}"
  fi
  return 0
}

# 防火墙放行 123/udp（仅 Server 角色需要）
Check_Firewall() {
  [ "${chrony_role}" != 'server' ] && return 0
  [ "${open_firewall}" != 'y' ] && {
    echo "${CWARNING}open_firewall=n，跳过防火墙放行，请自行确保 123/udp 可达${CEND}"
    return 0
  }

  if command -v firewall-cmd > /dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --add-service=ntp > /dev/null 2>&1
    firewall-cmd --reload > /dev/null 2>&1
    echo "${CSUCCESS}[OK] firewalld 已放行 ntp (123/udp)${CEND}"
  elif command -v ufw > /dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow 123/udp > /dev/null 2>&1
    echo "${CSUCCESS}[OK] ufw 已放行 123/udp${CEND}"
  elif command -v iptables > /dev/null 2>&1; then
    if ! iptables -C INPUT -p udp --dport 123 -j ACCEPT > /dev/null 2>&1; then
      iptables -I INPUT -p udp --dport 123 -j ACCEPT > /dev/null 2>&1
      echo "${CWARNING}已通过 iptables 临时放行 123/udp，重启后失效，请自行持久化${CEND}"
    else
      echo "${CSUCCESS}[OK] iptables 已放行 123/udp${CEND}"
    fi
  else
    echo "${CWARNING}未检测到活动防火墙，跳过放行${CEND}"
  fi
  return 0
}

# 回收防火墙放行（卸载时调用）
Close_Firewall() {
  if command -v firewall-cmd > /dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --remove-service=ntp > /dev/null 2>&1
    firewall-cmd --reload > /dev/null 2>&1
  fi
  if command -v ufw > /dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw delete allow 123/udp > /dev/null 2>&1
  fi
  if command -v iptables > /dev/null 2>&1; then
    iptables -D INPUT -p udp --dport 123 -j ACCEPT > /dev/null 2>&1
  fi
  return 0
}

# SELinux 提示（chrony 默认策略已允许，无需关闭 SELinux）
Check_SELinux() {
  command -v getenforce > /dev/null 2>&1 || return 0
  local mode
  mode=$(getenforce 2>/dev/null)
  if [ "${mode}" == "Enforcing" ]; then
    echo "${CMSG}[INFO] SELinux=Enforcing，chrony 默认策略已允许其运行，无需关闭${CEND}"
    echo "${CMSG}       如自定义了非标准路径，请执行: restorecon -Rv /etc/chrony.conf /var/lib/chrony${CEND}"
  fi
  return 0
}

# 容器环境检测：容器内通常缺少 CAP_SYS_TIME，无法修改系统时钟
Check_Container() {
  local in_container=0
  [ -f /.dockerenv ] && in_container=1
  grep -qE '(docker|containerd|kubepods|lxc)' /proc/1/cgroup 2>/dev/null && in_container=1
  [ "$(systemd-detect-virt -c 2>/dev/null)" != "none" ] && [ -n "$(systemd-detect-virt -c 2>/dev/null)" ] && in_container=1

  if [ ${in_container} -eq 1 ]; then
    echo "${CFAILURE}[ERROR] 检测到容器环境！容器共享宿主机时钟且通常缺少 CAP_SYS_TIME，${CEND}"
    echo "${CFAILURE}        无法在容器内进行时间同步。请在宿主机上部署 chrony。${CEND}"
    return 1
  fi
  return 0
}

# 上游时间源连通性探测（失败仅告警，不中断安装）
Check_Network() {
  local servers="$1"
  [ -z "${servers}" ] && return 0
  local ok=0
  for s in $(echo "${servers}" | tr ',' ' '); do
    [ -z "${s}" ] && continue
    if command -v chronyd > /dev/null 2>&1; then
      # -Q 只查询不改时钟，超时 3 秒
      if timeout 8 chronyd -Q -t 3 "server ${s} iburst" > /dev/null 2>&1; then
        echo "${CSUCCESS}[OK] 上游源可达: ${s}${CEND}"
        ok=1
        continue
      fi
    fi
    if ping -c 1 -W 2 "${s}" > /dev/null 2>&1; then
      echo "${CWARNING}[WARN] ${s} ICMP 可达但 NTP 未响应${CEND}"
    else
      echo "${CWARNING}[WARN] 上游源不可达: ${s}${CEND}"
    fi
  done
  [ ${ok} -eq 0 ] && echo "${CWARNING}所有上游源均未通过 NTP 探测，安装继续，请稍后用 chronyc sources -v 复查${CEND}"
  return 0
}
