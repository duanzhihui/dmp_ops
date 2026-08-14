#!/bin/bash
# options.conf 模板化引导逻辑
# 功能: 运行时根据 options.conf.template 与版本号自动创建/备份/升级 options.conf
# 用法: Ensure_Options_Conf <module_dir>
#
# 规则:
#   1. 模板不存在 -> 直接返回（兼容无模板场景）
#   2. options.conf 不存在 -> 从模板复制创建
#   3. 版本一致 -> 沿用现有 options.conf（保留用户修改）
#   4. 版本不一致 -> 备份 options.conf.<旧版本>（旧版无版本则 options.conf.bak），再从模板重建

Ensure_Options_Conf() {
  local module_dir="$1"
  local tmpl="${module_dir}/options.conf.template"
  local conf="${module_dir}/options.conf"

  # 模板不存在，兼容无模板场景
  [ -f "${tmpl}" ] || return 0

  # 读取模板版本号
  local tmpl_ver
  tmpl_ver=$(grep -E '^conf_version=' "${tmpl}" 2>/dev/null | head -1 | cut -d= -f2-)
  # 去除两端空白与引号
  tmpl_ver="${tmpl_ver#\"}"; tmpl_ver="${tmpl_ver%\"}"
  tmpl_ver="${tmpl_ver#\'}"; tmpl_ver="${tmpl_ver%\'}"
  tmpl_ver=$(echo "${tmpl_ver}" | tr -d '[:space:]')

  # options.conf 不存在 -> 从模板创建
  if [ ! -f "${conf}" ]; then
    cp -p "${tmpl}" "${conf}"
    echo "${CMSG}[options.conf] 已从模板创建 (version=${tmpl_ver})${CEND}"
    return 0
  fi

  # 读取现有 options.conf 版本号
  local cur_ver
  cur_ver=$(grep -E '^conf_version=' "${conf}" 2>/dev/null | head -1 | cut -d= -f2-)
  cur_ver="${cur_ver#\"}"; cur_ver="${cur_ver%\"}"
  cur_ver="${cur_ver#\'}"; cur_ver="${cur_ver%\'}"
  cur_ver=$(echo "${cur_ver}" | tr -d '[:space:]')

  # 版本一致 -> 沿用
  if [ -n "${cur_ver}" ] && [ "${cur_ver}" = "${tmpl_ver}" ]; then
    return 0
  fi

  # 版本不一致 -> 备份后重建
  local bak
  if [ -z "${cur_ver}" ]; then
    # 旧版无版本字段
    bak="${conf}.bak"
    local i=1
    while [ -e "${bak}" ]; do
      bak="${conf}.bak.${i}"
      i=$((i + 1))
    done
  else
    bak="${conf}.${cur_ver}"
    local i=1
    while [ -e "${bak}" ]; do
      bak="${conf}.${cur_ver}.${i}"
      i=$((i + 1))
    done
  fi

  cp -p "${conf}" "${bak}"
  cp -p "${tmpl}" "${conf}"
  echo "${CMSG}[options.conf] 版本变更 (旧=${cur_ver:-unknown} 新=${tmpl_ver})，旧配置已备份为 ${bak}${CEND}"
}
