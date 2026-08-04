# OpenJDK 运维代码生成提示词

> 本文档为 **OpenJDK** 定制的运维自动化脚本生成提示词。
> 基于 oneinstack 项目架构规范（代码提取自 `oneinstack/include/openjdk-8.sh`、`openjdk-11.sh`、`openjdk-17.sh`、`openjdk-18.sh`、`check_os.sh`、`uninstall.sh`），
> 可直接交给 AI 编程工具生成完整的 OpenJDK 运维代码。

---

# Part A: OpenJDK 技术规格

## 1. 软件概述

**OpenJDK** 是 Java SE 平台的开源参考实现，是所有 Java 应用（ZooKeeper、Doris、DolphinScheduler、SeaTunnel、Tomcat 等）的运行基座。

与本仓库其他组件的**本质区别**：

| 特征 | 一般服务型软件（ZooKeeper/Doris） | OpenJDK |
|------|--------------------------------|---------|
| 是否常驻进程 | 是 | **否**（运行时/工具链，无守护进程） |
| 是否需要 systemd service | 是 | **否**（不生成 `.service` 文件） |
| 是否监听端口 | 是 | **否**（仅可选 JMX 端口） |
| 是否有数据目录 | 是 | **否**（仅有 `cacerts` 证书库等配置态数据） |
| 核心交付物 | 服务进程 | `JAVA_HOME` + `PATH` + `alternatives` 链接 |
| 监控对象 | 自身进程/端口 | **依赖 JDK 的 JVM 进程**（堆、GC、线程） |

因此 OpenJDK 运维代码的重心是：**多版本共存 → 环境变量管理 → 默认版本切换 → JVM 侧监控与诊断**。

### 1.1 支持版本

| 版本 | 类型 | 状态 | 典型使用场景 |
|------|------|------|-------------|
| **OpenJDK 8** | LTS | 长期维护 | ZooKeeper 3.7/3.8、Hadoop 2.x、老旧业务系统 |
| **OpenJDK 11** | LTS | 长期维护 | ZooKeeper 3.9、Doris FE、Flink 1.x、Spark 3.x |
| **OpenJDK 17** | LTS | 长期维护 | Doris 2.1+、DolphinScheduler 3.x、Spring Boot 3.x |
| **OpenJDK 18** | 非 LTS | 已 EOL | 仅为兼容 oneinstack 既有选项保留，**生产不推荐** |
| **OpenJDK 21** | LTS | 长期维护 | 新建集群首选（虚拟线程、分代 ZGC） |

> **补丁版本策略**：本方案 **不硬编码补丁号**。`versions.txt` 只固定 feature 版本（8/11/17/18/21），
> 精确补丁版本（如 `21.0.x+y`）在 tar.gz 模式下通过 Adoptium API 动态获取最新 GA；
> 若需锁版本，可在 `versions.txt` 的 `jdkNN_patch_ver` 字段显式填写。

### 1.2 官方文档

- OpenJDK 官网：https://openjdk.org/
- Eclipse Temurin（Adoptium）下载与 API：https://adoptium.net/ ，API: https://api.adoptium.net/q/swagger-ui/
- Adoptium Linux 包仓库：https://adoptium.net/installation/linux/
- Red Hat OpenJDK 包说明：https://access.redhat.com/documentation/en-us/openjdk
- Debian/Ubuntu openjdk 包：https://packages.debian.org/openjdk-21-jdk
- JVM 参数与工具手册：https://docs.oracle.com/en/java/javase/21/docs/specs/man/

### 1.3 发行版（Distribution）说明

| 发行版 | 提供方 | 说明 |
|--------|--------|------|
| **发行版自带 openjdk** | RHEL / Debian / Ubuntu | 首选，随系统安全更新，包名 `java-*-openjdk-devel` / `openjdk-*-jdk` |
| **Eclipse Temurin** | Adoptium | 老系统（CentOS 7、Ubuntu 16、Debian 9/10）缺包时的官方兼容选择，包名 `temurin-*-jdk` |
| **Amazon Corretto / Azul Zulu** | AWS / Azul | 可选备用 tar.gz 源 |

> oneinstack 已验证的策略：**发行版仓库有包就用发行版包；没有则挂 Adoptium 仓库装 Temurin**（见 `openjdk-8.sh` 的 Debian 10-13 分支、`openjdk-17.sh` 的 RHEL 7 分支）。

## 2. 安装方式（双模式）

### 2.1 模式一：包管理器（默认，install_method=package）

```
OS 检测 → 选择包名 → (老系统) 配置 Adoptium 仓库 → yum/apt 安装 → 推导 JAVA_HOME → 写 profile.d → alternatives 注册 → 验证
```

**优点**：随系统安全更新、依赖自动处理；**缺点**：补丁版本不可控，多版本共存受仓库限制。

### 2.2 模式二：tar.gz 二进制（install_method=binary）

```
选择 feature 版本 → Adoptium API 解析下载地址 → 多源容错下载 → 解压到 /usr/local/jdk-{N} → 软链 → 写 profile.d → alternatives 注册 → 验证
```

**优点**：版本精确可控、可离线部署、天然支持多版本共存；**缺点**：需自行跟进安全补丁。

### 2.3 两种模式的路径对照

| 模式 | 安装根目录 | 版本目录示例 | 统一软链 |
|------|-----------|-------------|---------|
| package (rhel) | `/usr/lib/jvm` | `/usr/lib/jvm/java-17-openjdk` | `/usr/local/java` → 当前默认 |
| package (debian/ubuntu) | `/usr/lib/jvm` | `/usr/lib/jvm/java-17-openjdk-amd64` | 同上 |
| package (temurin) | `/usr/lib/jvm` | `/usr/lib/jvm/temurin-17-jdk-amd64` | 同上 |
| binary | `${jdk_base_dir}`（默认 `/usr/local`） | `/usr/local/jdk-17` | 同上 |

## 3. 环境变量与多版本管理规范

### 3.1 环境变量（统一由 `/etc/profile.d/openjdk.sh` 承载）

oneinstack 有两种写法，**本方案统一采用 `openjdk-8/11/17.sh` 的 `profile.d` 写法**（幂等、易清理），
**不采用** `openjdk-18.sh` 直接追加 `/etc/profile` 的写法（难以卸载、易重复）。

```bash
# /etc/profile.d/openjdk.sh（由脚本生成）
export JAVA_HOME=/usr/local/java
export CLASSPATH=.:$JAVA_HOME/lib/tools.jar:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib
export PATH=$JAVA_HOME/bin:$PATH
```

> 注意：`tools.jar`/`dt.jar` 仅 JDK 8 存在，JDK 9+ 已模块化移除。生成 `CLASSPATH` 时应按主版本区分，
> JDK 9+ 只写 `export CLASSPATH=.`。

### 3.2 多版本共存与默认版本切换

| 机制 | 说明 |
|------|------|
| 版本目录 | 每个 feature 版本独立目录，互不覆盖 |
| `/usr/local/java` 软链 | 指向"当前默认 JDK"，`JAVA_HOME` 始终指向此软链，切换版本只换软链，无需改 profile |
| `alternatives` | 注册 `java`/`javac`/`jar`/`keytool` 等命令，priority = feature 版本号 ×100 |
| `switch.sh` | 交互/静默切换默认版本，切换后校验 `java -version` |

## 4. 目录结构规范

```
openjdk/
├── install.sh              # 主安装入口（交互/静默双模式，双安装方式）
├── uninstall.sh            # 主卸载入口（按版本卸载 / --all）
├── upgrade.sh              # 主升级入口（同 feature 版本内补丁升级）
├── switch.sh               # 默认 JDK 版本切换（OpenJDK 专属）
├── backup.sh               # 备份执行脚本（cacerts/profile/JDK 目录，由 cron 调用）
├── backup_setup.sh         # 备份策略配置向导
├── monitor.sh              # JVM 进程健康检查与状态监控
├── options.conf            # 中央配置文件（路径、安装方式、JVM 监控阈值）
├── versions.txt            # 版本号清单（feature 版本 + 可选补丁版本）
├── include/                # 功能模块库
│   ├── color.sh            #   终端颜色定义
│   ├── check_os.sh         #   OS/架构检测（输出 Family/PM/SYS_ARCH/RHEL_ver...）
│   ├── check_env.sh        #   前置环境检测（是否已装 JDK、仓库可用性、依赖工具）
│   ├── download.sh         #   下载函数（多源容错）
│   ├── adoptium_repo.sh    #   Adoptium yum/apt 仓库配置（老系统兜底）
│   ├── openjdk.sh          #   核心安装/卸载模块（Install_OpenJDK/Uninstall_OpenJDK）
│   ├── openjdk_package.sh  #   包管理器安装实现（按 OS 分支选包名）
│   ├── openjdk_binary.sh   #   tar.gz 二进制安装实现（Adoptium API）
│   ├── jdk_env.sh          #   环境变量与 alternatives 管理
│   ├── upgrade_jdk.sh      #   升级模块
│   └── monitor_jdk.sh      #   JVM 监控模块
├── config/                 # 配置模板
│   ├── openjdk.sh.tpl      #   /etc/profile.d/openjdk.sh 模板
│   └── jvm_opts.conf       #   推荐 JVM 参数模板（按 JDK 版本给出 GC 建议）
├── tools/                  # 辅助工具脚本
│   ├── jvm_diag.sh         #   JVM 诊断采集（jstack/jmap/jcmd/jstat 一键打包）
│   ├── cacerts_import.sh   #   导入企业 CA 证书到 cacerts
│   └── jdk_list.sh         #   列出本机所有已安装 JDK 及当前默认版本
├── src/                    # 安装包存放目录（含 adoptium.key GPG 公钥）
└── init.d/                 # 【本组件不需要】OpenJDK 无常驻服务，不生成 systemd unit
```

## 5. 文件职责说明

### 5.1 主入口脚本

| 文件 | 职责 | 关键设计 |
|------|------|---------|
| `install.sh` | 安装主入口 | `--jdk_option [1-5]` 选版本 + `--install_method [package\|binary]`；无参数进交互菜单 |
| `uninstall.sh` | 卸载主入口 | `Print_OpenJDK()` 预览 → 确认 → 按版本卸载；清理 profile.d 与 alternatives |
| `upgrade.sh` | 升级主入口 | 仅允许同 feature 版本补丁升级；跨大版本引导用户走 install + switch |
| `switch.sh` | 默认版本切换 | 列出已装版本 → 切软链 + alternatives → 校验 |
| `backup.sh` | 备份执行器 | 备份 cacerts、profile.d 配置、可选整个 JDK 目录 |
| `backup_setup.sh` | 备份配置向导 | 写入 options.conf + 配置 cron |
| `monitor.sh` | 监控主入口 | `--status` 报告 / `--check` 健康检查；检查 JVM 进程堆与 GC |

### 5.2 功能模块 (include/)

| 文件 | 职责 | 核心函数 |
|------|------|---------|
| `color.sh` | 颜色定义 | `CSUCCESS`/`CFAILURE`/`CWARNING`/`CMSG`/`CEND` |
| `check_os.sh` | OS 检测 | 输出 `Platform`、`Family`、`PM`、`ARCH`、`SYS_ARCH`、`RHEL_ver`、`Debian_ver`、`Ubuntu_ver`、`THREAD` |
| `check_env.sh` | 环境检测 | `Check_Installed_JDK()`、`Check_Deps()`（wget/curl/tar/gpg）、`Check_Net()` |
| `download.sh` | 下载 | `Download_src()` — 多源容错 + HTML 错误页识别 |
| `adoptium_repo.sh` | 第三方仓库 | `Add_Adoptium_Repo()` — RHEL 写 `/etc/yum.repos.d/adoptium.repo`，Debian 系导入 key + `apt-add-repository` |
| `openjdk_package.sh` | 包安装 | `Install_JDK_Package()`、`Get_Pkg_Name()`、`Detect_JAVA_HOME()` |
| `openjdk_binary.sh` | 二进制安装 | `Install_JDK_Binary()`、`Get_Adoptium_URL()` |
| `jdk_env.sh` | 环境管理 | `Set_JDK_Env()`、`Unset_JDK_Env()`、`Register_Alternatives()`、`Unregister_Alternatives()`、`Switch_JDK()`、`List_JDK()` |
| `openjdk.sh` | 安装/卸载编排 | `Install_OpenJDK()`、`Uninstall_OpenJDK()`、`Print_OpenJDK()` |
| `upgrade_jdk.sh` | 升级 | `Upgrade_OpenJDK()` |
| `monitor_jdk.sh` | 监控 | `Check_JDK_Health()`、`Check_JVM_Process()`、`Check_JVM_Heap()`、`Check_JVM_GC()`、`Check_JVM_Thread()`、`Send_Alert()` |

## 6. 运维生命周期 — OpenJDK 专属流程

### 6.1 安装 (Install)

**流程模式：**
```
root 检查 → OS/架构检测 → 已装检测(幂等) → 选择安装方式 →
  ├─ package: 选包名 → (老系统)配置 Adoptium 仓库 → yum/apt 安装 → 推导 JAVA_HOME
  └─ binary : Adoptium API 取 URL → 下载 → 解压到 /usr/local/jdk-{N}
→ 建立 /usr/local/java 软链 → 写 /etc/profile.d/openjdk.sh → alternatives 注册
→ java -version / javac -version 验证 → 输出安装摘要
```

**关键代码模式（提取并改造自 oneinstack）：**

```bash
# 1. 已安装检测 — 幂等性保证（按 feature 版本判断，允许多版本共存）
Check_Installed_JDK() {
  local ver=$1
  local exist_home=$(Detect_JAVA_HOME ${ver})
  [ -x "${exist_home}/bin/java" ] && {
    echo "${CWARNING}OpenJDK ${ver} already installed: ${exist_home}${CEND}"
    return 0
  }
  return 1
}

# 2. 包名映射（来源：oneinstack openjdk-8/11/17/18.sh 的 OS 分支）
Get_Pkg_Name() {
  local ver=$1        # 8 | 11 | 17 | 18 | 21
  local use_temurin=0 # 老系统缺包时置 1
  if [ "${Family}" == 'rhel' ]; then
    # CentOS/RHEL 7 仓库缺 17/18/21，走 Adoptium
    [[ "${RHEL_ver}" == '7' ]] && [[ "${ver}" =~ ^17$|^18$|^21$ ]] && use_temurin=1
    if [ ${use_temurin} -eq 1 ]; then
      pkg_name="temurin-${ver}-jdk"
      java_home="/usr/lib/jvm/temurin-${ver}-jdk"
    elif [ "${ver}" == '8' ]; then
      pkg_name="java-1.8.0-openjdk-devel"
      java_home="/usr/lib/jvm/java-1.8.0-openjdk"
    else
      pkg_name="java-${ver}-openjdk-devel"
      java_home="/usr/lib/jvm/java-${ver}-openjdk"
    fi
  elif [ "${Family}" == 'debian' ]; then
    # Debian 10~13 无 openjdk-8-jdk，走 Adoptium temurin-8-jdk
    [ "${ver}" == '8' ] && [[ "${Debian_ver}" =~ ^1[0-9]$ ]] && use_temurin=1
    [[ "${ver}" =~ ^17$|^21$ ]] && [[ "${Debian_ver}" =~ ^9$|^10$ ]] && use_temurin=1
    if [ ${use_temurin} -eq 1 ]; then
      pkg_name="temurin-${ver}-jdk"
      java_home="/usr/lib/jvm/temurin-${ver}-jdk-${SYS_ARCH}"
    else
      pkg_name="openjdk-${ver}-jdk"
      java_home="/usr/lib/jvm/java-${ver}-openjdk-${SYS_ARCH}"
    fi
  elif [ "${Family}" == 'ubuntu' ]; then
    # Ubuntu 16 仓库缺 11/17/21，走 Adoptium
    [[ "${Ubuntu_ver}" =~ ^16$ ]] && [[ "${ver}" =~ ^11$|^17$|^18$|^21$ ]] && use_temurin=1
    if [ ${use_temurin} -eq 1 ]; then
      pkg_name="temurin-${ver}-jdk"
      java_home="/usr/lib/jvm/temurin-${ver}-jdk-${SYS_ARCH}"
    else
      pkg_name="openjdk-${ver}-jdk"
      java_home="/usr/lib/jvm/java-${ver}-openjdk-${SYS_ARCH}"
    fi
  fi
  # JDK 8 在 Debian 系目录名为 java-8-openjdk-${SYS_ARCH}
  [ "${ver}" == '8' ] && [ "${Family}" != 'rhel' ] && [ ${use_temurin} -eq 0 ] && \
    java_home="/usr/lib/jvm/java-8-openjdk-${SYS_ARCH}"
}

# 3. Adoptium 仓库配置（来源：oneinstack openjdk-17.sh / openjdk-8.sh）
Add_Adoptium_Repo() {
  if [ "${Family}" == 'rhel' ]; then
    cat > /etc/yum.repos.d/adoptium.repo << EOF
[Adoptium]
name=Adoptium
baseurl=${adoptium_rpm_mirror}/rhel\$releasever-\$basearch/
enabled=1
gpgcheck=0
EOF
  else
    # 优先使用本地随包提供的 GPG 公钥，避免网络受限
    if [ -s "${openjdk_dir}/src/adoptium.key" ]; then
      cat ${openjdk_dir}/src/adoptium.key | apt-key add -
    else
      wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | apt-key add -
    fi
    apt-add-repository --yes ${adoptium_deb_mirror}
    apt-get -y update
  fi
}

# 4. 包管理器安装
Install_JDK_Package() {
  local ver=$1
  Get_Pkg_Name ${ver}
  [ ${use_temurin} -eq 1 ] && Add_Adoptium_Repo
  if [ "${PM}" == 'yum' ]; then
    ${PM} -y install ${pkg_name}
  else
    apt-get --no-install-recommends -y install ${pkg_name}
  fi
  # 包名与目录名可能不完全匹配，二次探测
  [ ! -x "${java_home}/bin/java" ] && java_home=$(Detect_JAVA_HOME ${ver})
}

# 5. JAVA_HOME 探测（兼容 amd64/arm64 与不同发行版命名）
Detect_JAVA_HOME() {
  local ver=$1
  local candidates=(
    "${jdk_base_dir}/jdk-${ver}"
    "/usr/lib/jvm/java-${ver}-openjdk"
    "/usr/lib/jvm/java-${ver}-openjdk-${SYS_ARCH}"
    "/usr/lib/jvm/temurin-${ver}-jdk"
    "/usr/lib/jvm/temurin-${ver}-jdk-${SYS_ARCH}"
  )
  [ "${ver}" == '8' ] && candidates+=(
    "/usr/lib/jvm/java-1.8.0-openjdk"
    "/usr/lib/jvm/java-8-openjdk-${SYS_ARCH}"
  )
  for d in "${candidates[@]}"; do
    [ -x "${d}/bin/java" ] && { echo "${d}"; return 0; }
  done
  # 兜底：模糊匹配
  local fuzzy=$(ls -d /usr/lib/jvm/*${ver}* 2>/dev/null | grep -v jre | head -1)
  [ -x "${fuzzy}/bin/java" ] && echo "${fuzzy}"
}

# 6. tar.gz 二进制安装（Adoptium API，arch 取 x64/aarch64）
Get_Adoptium_URL() {
  local ver=$1
  local api_arch=x64
  [[ "${ARCH}" =~ arm|aarch64 ]] && api_arch=aarch64
  if [ -n "${jdk_patch_ver}" ]; then
    # 锁定补丁版本：走 release_name 精确下载
    src_url="https://api.adoptium.net/v3/binary/version/jdk-${jdk_patch_ver}/linux/${api_arch}/jdk/hotspot/normal/eclipse"
  else
    src_url="https://api.adoptium.net/v3/binary/latest/${ver}/ga/linux/${api_arch}/jdk/hotspot/normal/eclipse"
  fi
}

Install_JDK_Binary() {
  local ver=$1
  pushd ${openjdk_dir}/src > /dev/null
  Get_Adoptium_URL ${ver}
  Download_src   # 多源容错：Adoptium API → 镜像站 → 本地 src 已有包
  tar xzf ${jdk_tarball}
  local unpack_dir=$(tar tzf ${jdk_tarball} | head -1 | cut -d/ -f1)
  [ -d "${jdk_base_dir}/jdk-${ver}" ] && \
    /bin/mv ${jdk_base_dir}/jdk-${ver}{,_$(date +%Y%m%d%H)}
  /bin/mv ${unpack_dir} ${jdk_base_dir}/jdk-${ver}
  java_home=${jdk_base_dir}/jdk-${ver}
  rm -rf ${unpack_dir}
  popd > /dev/null
}

# 7. 环境变量写入（幂等，profile.d 方式；来源：oneinstack openjdk-*.sh 改造）
Set_JDK_Env() {
  local jh=$1
  local ver=$2
  ln -snf ${jh} ${jdk_link}          # /usr/local/java -> 实际 JDK 目录
  if [ "${ver}" == '8' ]; then
    cat > /etc/profile.d/openjdk.sh << EOF
export JAVA_HOME=${jdk_link}
export CLASSPATH=.:\$JAVA_HOME/lib/tools.jar:\$JAVA_HOME/lib/dt.jar:\$JAVA_HOME/lib
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
  else
    cat > /etc/profile.d/openjdk.sh << EOF
export JAVA_HOME=${jdk_link}
export CLASSPATH=.
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
  fi
  chmod 644 /etc/profile.d/openjdk.sh
  . /etc/profile.d/openjdk.sh
}

# 8. alternatives 注册（priority 按 feature 版本递增）
Register_Alternatives() {
  local jh=$1
  local ver=$2
  local prio=$((ver * 100))
  local cmd
  for cmd in java javac jar javadoc keytool jshell jcmd jstack jmap jstat; do
    [ -x "${jh}/bin/${cmd}" ] && {
      if [ "${Family}" == 'rhel' ]; then
        alternatives --install /usr/bin/${cmd} ${cmd} ${jh}/bin/${cmd} ${prio} > /dev/null 2>&1
      else
        update-alternatives --install /usr/bin/${cmd} ${cmd} ${jh}/bin/${cmd} ${prio} > /dev/null 2>&1
      fi
    }
  done
}

# 9. 安装验证（来源：oneinstack 的成功/失败判定模式）
if [ -x "${java_home}/bin/java" ] && ${java_home}/bin/java -version > /dev/null 2>&1; then
  jdk_full_ver=$(${java_home}/bin/java -version 2>&1 | head -1 | awk -F'"' '{print $2}')
  echo "${CSUCCESS}OpenJDK ${jdk_full_ver} installed successfully! JAVA_HOME=${java_home}${CEND}"
else
  echo "${CFAILURE}OpenJDK ${jdk_ver} install failed, Please contact the author! ${CEND}" && \
    grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
  kill -9 $$; exit 1;
fi
```

### 6.2 卸载 (Uninstall)

**流程模式：**
```
预览待删除内容 → 用户确认(--quiet 跳过) → 检测是否有 JVM 进程正在使用该 JDK →
注销 alternatives → 删除/卸载该版本 → 清理 profile.d → 若删除的是当前默认版本则重新指向其他已装版本 → 清理 options.conf
```

**关键代码模式：**

```bash
# 1. 预览（来源：oneinstack uninstall.sh 的 Print_XXX 模式）
Print_OpenJDK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  [ -n "${jh}" ] && echo ${jh}
  [ -L "${jdk_link}" ] && [ "$(readlink ${jdk_link})" == "${jh}" ] && echo ${jdk_link}
  [ -e "/etc/profile.d/openjdk.sh" ] && echo /etc/profile.d/openjdk.sh
  echo "alternatives entries: java/javac/jar/keytool -> ${jh}/bin/*"
}

# 2. 占用检测 — JDK 被在跑的 JVM 使用时禁止卸载
Check_JDK_InUse() {
  local jh=$1
  local pids=$(ps -eo pid,args | grep -F "${jh}/bin/java" | grep -v grep | awk '{print $1}')
  [ -n "${pids}" ] && {
    echo "${CWARNING}These JVM processes are still using ${jh}:${CEND}"
    ps -fp ${pids} | sed 1d
    echo "${CFAILURE}Stop them first, or re-run with --force${CEND}"
    [ "${force_flag}" != 'y' ] && return 1
  }
  return 0
}

# 3. 执行卸载
Uninstall_OpenJDK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  [ -z "${jh}" ] && { echo "${CWARNING}OpenJDK ${ver} is not installed${CEND}"; return 0; }
  Check_JDK_InUse ${jh} || return 1

  Unregister_Alternatives ${jh}

  if [[ "${jh}" == ${jdk_base_dir}/jdk-* ]]; then
    # binary 模式：目录先重命名保留，再按 keep_backup 决定是否删除
    /bin/mv ${jh}{,_uninstall_$(date +%Y%m%d%H)}
    [ "${keep_backup}" != 'y' ] && rm -rf ${jh}_uninstall_*
  else
    # package 模式：交回包管理器
    Get_Pkg_Name ${ver}
    if [ "${PM}" == 'yum' ]; then
      yum -y remove ${pkg_name}
    else
      apt-get -y purge ${pkg_name}
      apt-get -y autoremove
    fi
  fi

  # 当前默认版本被卸载 → 重新指向其他已装版本，否则彻底清理环境变量
  if [ "$(readlink -f ${jdk_link} 2>/dev/null)" == "$(readlink -f ${jh} 2>/dev/null)" ]; then
    local next_ver=$(List_JDK | awk 'NR==1{print $1}')
    if [ -n "${next_ver}" ]; then
      Set_JDK_Env "$(Detect_JAVA_HOME ${next_ver})" ${next_ver}
      echo "${CMSG}Default JDK switched to ${next_ver}${CEND}"
    else
      Unset_JDK_Env
    fi
  fi
  sed -i "s@^jdk_current_ver=.*@jdk_current_ver=@" ${openjdk_dir}/options.conf
  echo "${CMSG}OpenJDK ${ver} uninstall completed! ${CEND}"
}

# 4. 环境变量清理（对应 oneinstack uninstall.sh 中的 sed 清理逻辑）
Unset_JDK_Env() {
  rm -f /etc/profile.d/openjdk.sh
  rm -f ${jdk_link}
  # 兼容历史版本（oneinstack openjdk-18.sh）直接写入 /etc/profile 的情况
  sed -i '/export JAVA_HOME=/d' /etc/profile
  sed -i '/export CLASSPATH=/d' /etc/profile
  sed -i 's@\$JAVA_HOME/bin:@@' /etc/profile
  sed -i 's@\${JAVA_HOME}/bin:@@' /etc/profile
}
```

### 6.3 升级 (Upgrade)

**原则**：OpenJDK 只做 **同 feature 版本内的补丁升级**（如 17.0.x → 17.0.y）；
跨大版本（11 → 17）属于运行时更换，必须走 `install.sh` 安装新版本 + `switch.sh` 切换，避免直接覆盖导致依赖 JDK 的业务无法回退。

**流程模式：**
```
检测当前版本 → 获取最新可用补丁版本 → 用户确认目标版本 → feature 版本一致性校验 →
升级前备份(旧目录重命名 + cacerts 备份) → 停止依赖该 JDK 的服务(可选/提示) →
安装新补丁 → 更新软链与 alternatives → java -version 验证 → 失败自动回滚 → 重启相关服务
```

**关键代码模式：**

```bash
Upgrade_OpenJDK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  [ -z "${jh}" ] && { echo "${CWARNING}OpenJDK ${ver} is not installed!${CEND}"; exit 1; }

  # 1. 当前版本
  OLD_ver=$(${jh}/bin/java -version 2>&1 | head -1 | awk -F'"' '{print $2}')

  # 2. 最新可用补丁版本（Adoptium API）
  Latest_ver=$(curl -s "https://api.adoptium.net/v3/info/release_names?release_type=ga&version=%5B${ver}%2C${ver}.999%5D&page_size=1&sort_order=DESC" \
    | grep -o 'jdk-\?[0-9][^"]*' | head -1)

  echo "Current Version: ${CMSG}${OLD_ver}${CEND}"
  read -e -p "Please input upgrade version(default: ${Latest_ver}): " NEW_ver
  NEW_ver=${NEW_ver:-${Latest_ver}}

  # 3. 校验：不可相同，feature 版本必须一致
  [ "${NEW_ver}" == "${OLD_ver}" ] && {
    echo "${CWARNING}Same version, skip upgrade${CEND}"; exit 0
  }
  [ "$(echo ${NEW_ver} | grep -o '^[0-9]*')" != "$(echo ${OLD_ver} | grep -o '^[0-9]*')" ] && {
    echo "${CFAILURE}Cross feature-version upgrade is not allowed. Use install.sh + switch.sh${CEND}"
    exit 1
  }

  # 4. 升级前备份（cacerts 与安全策略是唯一"有状态"内容）
  mkdir -p ${backup_dir}
  tar czf ${backup_dir}/JDK_${ver}_conf_$(date +%Y%m%d_%H%M%S).tgz \
    -C ${jh} lib/security conf 2>/dev/null
  [ -d "${jh}" ] && /bin/cp -a ${jh} ${jh}_bak_$(date +%m%d)

  # 5. 升级
  if [ "${install_method}" == 'binary' ]; then
    jdk_patch_ver=${NEW_ver#jdk-}
    Install_JDK_Binary ${ver}
  else
    [ "${PM}" == 'yum' ] && yum -y update ${pkg_name} || apt-get -y install --only-upgrade ${pkg_name}
    java_home=$(Detect_JAVA_HOME ${ver})
  fi

  # 6. 验证 + 回滚
  if ${java_home}/bin/java -version > /dev/null 2>&1; then
    Set_JDK_Env ${java_home} ${ver}
    Register_Alternatives ${java_home} ${ver}
    rm -rf ${jh}_bak_*
    echo "${CSUCCESS}Successfully upgrade OpenJDK from ${OLD_ver} to ${NEW_ver}${CEND}"
  else
    echo "${CFAILURE}Upgrade failed, rolling back...${CEND}"
    rm -rf ${java_home}
    /bin/mv ${jh}_bak_$(date +%m%d) ${jh}
    Set_JDK_Env ${jh} ${ver}
    exit 1
  fi
}
```

### 6.4 版本切换 (Switch) — OpenJDK 专属

```bash
# 列出所有已装 JDK：输出 "feature_ver  full_ver  java_home  [current]"
List_JDK() {
  local v jh cur=$(readlink -f ${jdk_link} 2>/dev/null)
  for v in ${jdk_support_vers}; do
    jh=$(Detect_JAVA_HOME ${v})
    [ -z "${jh}" ] && continue
    local full=$(${jh}/bin/java -version 2>&1 | head -1 | awk -F'"' '{print $2}')
    local mark=""
    [ "$(readlink -f ${jh})" == "${cur}" ] && mark="*"
    echo "${v} ${full} ${jh} ${mark}"
  done
}

Switch_JDK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  [ -z "${jh}" ] && {
    echo "${CFAILURE}OpenJDK ${ver} is not installed. Run: ./install.sh --jdk_option N${CEND}"
    exit 1
  }
  Set_JDK_Env ${jh} ${ver}
  Register_Alternatives ${jh} ${ver}
  if [ "${Family}" == 'rhel' ]; then
    alternatives --set java ${jh}/bin/java > /dev/null 2>&1
    alternatives --set javac ${jh}/bin/javac > /dev/null 2>&1
  else
    update-alternatives --set java ${jh}/bin/java > /dev/null 2>&1
    update-alternatives --set javac ${jh}/bin/javac > /dev/null 2>&1
  fi
  sed -i "s@^jdk_current_ver=.*@jdk_current_ver=${ver}@" ${openjdk_dir}/options.conf
  echo "${CSUCCESS}Default JDK switched to: $(${jdk_link}/bin/java -version 2>&1 | head -1)${CEND}"
  echo "${CWARNING}Note: existing JVM processes must be restarted to take effect${CEND}"
}
```

### 6.5 备份 (Backup)

OpenJDK 无业务数据，备份对象为**配置态资产**：

| 备份内容 | 路径 | 说明 |
|---------|------|------|
| 证书库 | `${JAVA_HOME}/lib/security/cacerts` | 企业自签 CA、内部 HTTPS 依赖它，重装必丢 |
| 安全与运行配置 | `${JAVA_HOME}/conf/`（JDK 9+）、`${JAVA_HOME}/jre/lib/security/`（JDK 8） | `java.security`、`java.policy`、`net.properties` |
| 环境变量配置 | `/etc/profile.d/openjdk.sh` | 便于快速重建环境 |
| 完整 JDK 目录 | `${JAVA_HOME}` | `backup_content` 含 `jdk` 时打包，用于离线复原 |
| 已装版本清单 | 由 `List_JDK` 生成 | 便于灾备时按清单重装 |

```bash
# === backup.sh 核心（策略模式，来源：oneinstack backup.sh） ===
JDK_Local_BK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  local NewFile=${backup_dir}/JDK_${ver}_$(date +%Y%m%d_%H%M%S).tgz
  local OldFile=${backup_dir}/JDK_${ver}_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz
  [ -n "$(ls ${OldFile} 2>/dev/null)" ] && rm -f ${OldFile}
  mkdir -p ${backup_dir}
  # 证书库 + 安全配置 + profile
  tar czf ${NewFile} \
    -C ${jh} lib/security conf 2>/dev/null
  tar rf /dev/null 2>/dev/null  # 占位：如需整包备份则改为打包 ${jh} 全目录
  List_JDK > ${backup_dir}/JDK_installed_$(date +%Y%m%d).list
  [ -f "${NewFile}" ] && echo "${CSUCCESS}Backup OK: ${NewFile}${CEND}" \
    || { echo "${CFAILURE}Backup failed${CEND}"; return 1; }
}

# 云存储分发（oss/s3/cos）与过期清理沿用 oneinstack 模式
for DEST in $(echo ${backup_destination} | tr ',' ' '); do
  case "${DEST}" in
    local) JDK_Local_BK ${jdk_current_ver} ;;
    oss)   JDK_OSS_BK   ${jdk_current_ver} ;;
    s3)    JDK_S3_BK    ${jdk_current_ver} ;;
    remote) JDK_Remote_BK ${jdk_current_ver} ;;
  esac
done
```

### 6.6 监控 (Monitor)

OpenJDK 自身无进程可监控，`monitor.sh` 的对象是**运行在该 JDK 上的 JVM 进程**。

```bash
# 1. JDK 可用性自检
Check_JDK_Health() {
  [ ! -x "${jdk_link}/bin/java" ] && {
    echo "${CFAILURE}[CRITICAL] JAVA_HOME broken: ${jdk_link}${CEND}"
    Send_Alert "JAVA_HOME ${jdk_link} is broken"
    return 1
  }
  ${jdk_link}/bin/java -version > /dev/null 2>&1 || {
    echo "${CFAILURE}[CRITICAL] java -version failed${CEND}"
    Send_Alert "java -version failed on $(hostname)"
    return 1
  }
  # alternatives 与软链是否一致
  local which_java=$(readlink -f $(command -v java) 2>/dev/null)
  [ "${which_java}" != "$(readlink -f ${jdk_link}/bin/java)" ] && \
    echo "${CWARNING}[WARNING] 'java' in PATH (${which_java}) differs from JAVA_HOME${CEND}"
  return 0
}

# 2. JVM 进程清单
Check_JVM_Process() {
  local jvms=$(${jdk_link}/bin/jps -l 2>/dev/null | grep -v sun.tools.jps)
  [ -z "${jvms}" ] && { echo "${CMSG}No JVM process running${CEND}"; return 0; }
  echo "${CMSG}Running JVM processes:${CEND}"
  echo "${jvms}"
}

# 3. 堆使用率检查（阈值 jvm_heap_threshold）
Check_JVM_Heap() {
  local pid mainclass used max pct
  ${jdk_link}/bin/jps -l 2>/dev/null | grep -v sun.tools.jps | while read pid mainclass; do
    # 优先用 jcmd GC.heap_info（JDK 8+ 均支持）
    used=$(${jdk_link}/bin/jcmd ${pid} GC.heap_info 2>/dev/null | grep -o 'used [0-9]*K' | head -1 | tr -dc 0-9)
    max=$(${jdk_link}/bin/jcmd ${pid} VM.flags 2>/dev/null | grep -o 'MaxHeapSize=[0-9]*' | cut -d= -f2)
    [ -z "${used}" -o -z "${max}" ] && continue
    pct=$(( used * 1024 * 100 / max ))
    if [ ${pct} -ge ${jvm_heap_threshold} ]; then
      echo "${CWARNING}[WARNING] PID ${pid} (${mainclass}) heap usage ${pct}%${CEND}"
      Send_Alert "JVM ${pid} ${mainclass} heap usage ${pct}% >= ${jvm_heap_threshold}%"
    fi
  done
}

# 4. GC 检查（Full GC 次数与耗时占比）
Check_JVM_GC() {
  local pid
  ${jdk_link}/bin/jps -q 2>/dev/null | while read pid; do
    local line=$(${jdk_link}/bin/jstat -gcutil ${pid} 2>/dev/null | tail -1)
    [ -z "${line}" ] && continue
    local fgc=$(echo ${line} | awk '{print $(NF-2)}')
    local fgct=$(echo ${line} | awk '{print $(NF-1)}')
    echo "PID ${pid}: FullGC=${fgc} FullGCTime=${fgct}s"
    [ "$(echo "${fgc} > ${jvm_fullgc_threshold}" | bc 2>/dev/null)" == "1" ] && \
      Send_Alert "JVM ${pid} Full GC count ${fgc} exceeds ${jvm_fullgc_threshold}"
  done
}

# 5. 线程数检查
Check_JVM_Thread() {
  local pid
  ${jdk_link}/bin/jps -q 2>/dev/null | while read pid; do
    local threads=$(ls /proc/${pid}/task 2>/dev/null | wc -l)
    [ ${threads} -ge ${jvm_thread_threshold} ] && {
      echo "${CWARNING}[WARNING] PID ${pid} thread count ${threads}${CEND}"
      Send_Alert "JVM ${pid} thread count ${threads} >= ${jvm_thread_threshold}"
    }
  done
}

# 6. 告警（邮件 + Webhook，沿用通用模板）
Send_Alert() {
  local message=$1
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${timestamp}] ALERT: ${message}" >> ${log_dir}/monitor.log
  [ -n "${alert_email}" ] && echo "${message}" | mail -s "[OpenJDK Alert] $(hostname)" ${alert_email}
  [ -n "${webhook_url}" ] && curl -s -X POST "${webhook_url}" \
    -H 'Content-Type: application/json' \
    -d "{\"text\":\"[$(hostname)] ${message}\"}" > /dev/null
}

# 7. 状态报告
Monitor_Status() {
  echo "========== OpenJDK Status: $(date) =========="
  echo "Default JAVA_HOME : $(readlink -f ${jdk_link})"
  echo "Default Version   : $(${jdk_link}/bin/java -version 2>&1 | head -1)"
  echo "Installed JDKs    :"
  List_JDK | awk '{printf "  %-4s %-14s %-50s %s\n", $1, $2, $3, $4}'
  Check_JVM_Process
  Check_JVM_GC
}
```

## 7. 配置文件规范

### 7.1 options.conf 结构

```bash
# ===== 镜像源 =====
mirror_link=https://mirrors.tuna.tsinghua.edu.cn
adoptium_deb_mirror=https://mirrors.tuna.tsinghua.edu.cn/Adoptium/deb
adoptium_rpm_mirror=https://mirrors.tuna.tsinghua.edu.cn/Adoptium/rpm
adoptium_api=https://api.adoptium.net/v3

# ===== 安装方式：package(包管理器) | binary(tar.gz) =====
install_method=package

# ===== 安装路径（binary 模式生效） =====
jdk_base_dir=/usr/local
# 统一软链，JAVA_HOME 始终指向它
jdk_link=/usr/local/java

# ===== 支持与当前版本 =====
jdk_support_vers="8 11 17 18 21"
jdk_current_ver=            # 由 install.sh / switch.sh 自动写入
jdk_patch_ver=              # 留空=安装最新 GA；填写则锁定补丁版本(如 21.0.7+6)

# ===== 日志 =====
log_dir=/var/log/openjdk

# ===== 备份配置 =====
backup_dir=/data/backup/openjdk
expired_days=7
backup_destination=local    # local,remote,oss,cos,s3
backup_content=cacerts,conf # cacerts,conf,jdk
oss_bucket=
s3_bucket=
cos_bucket=
remote_host=
remote_dir=

# ===== JVM 监控阈值 =====
jvm_heap_threshold=85       # 堆使用率告警阈值(%)
jvm_fullgc_threshold=20     # Full GC 次数告警阈值
jvm_thread_threshold=2000   # 线程数告警阈值
disk_threshold=85

# ===== 告警配置 =====
alert_email=
webhook_url=
```

### 7.2 versions.txt 结构

```bash
# OpenJDK 版本清单
# feature 版本（用于包名与目录名推导）
jdk8_ver=8
jdk11_ver=11
jdk17_ver=17
jdk18_ver=18
jdk21_ver=21

# 可选：锁定补丁版本（留空则 binary 模式自动取 Adoptium 最新 GA）
# 取值格式参考 Adoptium release_name，如 8u462-b08 / 21.0.7+6
jdk8_patch_ver=
jdk11_patch_ver=
jdk17_patch_ver=
jdk18_patch_ver=
jdk21_patch_ver=

# 默认安装版本（对应 install.sh 的 jdk_option 默认值）
jdk_default_ver=17
```

### 7.3 config/openjdk.sh.tpl 模板

```bash
# /etc/profile.d/openjdk.sh — 由 install.sh 生成，请勿手工编辑
export JAVA_HOME={{JAVA_HOME}}
export CLASSPATH={{CLASSPATH}}
export PATH=$JAVA_HOME/bin:$PATH
```

### 7.4 config/jvm_opts.conf 推荐参数模板

```bash
# 供业务组件（ZooKeeper/Doris/DolphinScheduler 等）参考的 JVM 参数
# JDK 8
JDK8_OPTS="-server -Xms2g -Xmx2g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 \
  -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/openjdk \
  -Djava.security.egd=file:/dev/./urandom -Dfile.encoding=UTF-8"

# JDK 11 / 17
JDK11_OPTS="-server -Xms2g -Xmx2g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 \
  -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/openjdk \
  -Xlog:gc*:file=/var/log/openjdk/gc.log:time,uptime:filecount=10,filesize=32M \
  -Dfile.encoding=UTF-8"

# JDK 21（可选分代 ZGC）
JDK21_OPTS="-server -Xms4g -Xmx4g -XX:+UseZGC -XX:+ZGenerational \
  -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/openjdk \
  -Xlog:gc*:file=/var/log/openjdk/gc.log:time,uptime:filecount=10,filesize=32M \
  -Dfile.encoding=UTF-8"
```

## 8. 命令行参数设计

### install.sh

| 参数 | 说明 |
|------|------|
| `-h, --help` | 显示帮助 |
| `-v, --version` | 显示脚本版本 |
| `-q, --quiet` | 静默模式，跳过所有确认 |
| `--jdk_option [1-5]` | 1=OpenJDK8 2=OpenJDK11 3=OpenJDK17 4=OpenJDK18 5=OpenJDK21 |
| `--install_method [package\|binary]` | 安装方式，默认 package |
| `--jdk_patch_ver <ver>` | binary 模式锁定补丁版本 |
| `--set_default` | 安装后将该版本设为默认（默认行为，可用 `--no_default` 关闭） |
| `--no_default` | 安装但不改变当前默认 JDK |

### uninstall.sh

| 参数 | 说明 |
|------|------|
| `--jdk_option [1-5]` | 卸载指定版本 |
| `--all` | 卸载所有已装 OpenJDK 并清理环境变量 |
| `--force` | 存在 JVM 进程占用时强制卸载 |
| `--keep-backup` | 保留卸载前的目录备份 |
| `-q, --quiet` | 跳过确认 |

### upgrade.sh / switch.sh / monitor.sh

| 命令 | 参数 | 说明 |
|------|------|------|
| `upgrade.sh` | `--jdk_option [1-5]`、`--jdk_patch_ver <ver>` | 同 feature 版本内补丁升级 |
| `switch.sh` | `--jdk_option [1-5]`、`--list` | 切换默认版本 / 列出已装版本 |
| `monitor.sh` | `--status`、`--check`、`--jvm <pid>` | 状态报告 / 健康检查 / 指定 JVM 详情 |

---

# Part B: AI 编程完整提示词

> 以下提示词可直接复制给 AI 编程工具（如 Cursor/Windsurf/Copilot），生成完整的 OpenJDK 运维代码。

---

## 提示词全文

```markdown
# 角色

你是一位资深的 Linux 运维自动化工程师，精通 Bash Shell 编程、JVM 运行时管理和多版本 JDK 环境治理。
你的任务是为 **OpenJDK** 编写一套完整的运维自动化脚本，代码风格严格对齐 oneinstack 项目
（参考 oneinstack/include/openjdk-8.sh、openjdk-11.sh、openjdk-17.sh、openjdk-18.sh、check_os.sh、uninstall.sh）。

# 软件信息

- **软件名称**: OpenJDK
- **支持版本**: 8、11、17、18、21（feature 版本；18 为已 EOL 的非 LTS，仅作兼容保留并在菜单中标注不推荐）
- **默认版本**: 17
- **安装方式**: 双模式
  - `package`（默认）：发行版包管理器安装；发行版仓库缺包时自动配置 Adoptium 仓库安装 temurin-{N}-jdk
  - `binary`：通过 Adoptium API 下载 tar.gz，解压到 ${jdk_base_dir}/jdk-{N}
- **运行用户**: 无（JDK 为运行时，不创建专用用户，不注册 systemd 服务，不监听端口）
- **核心交付物**: JAVA_HOME、PATH、CLASSPATH、alternatives 链接、/usr/local/java 统一软链
- **健康检查**: `java -version`、`javac -version`、`jps`
- **目标 OS**: CentOS/RHEL 7+（含 Alma/Rocky/Anolis/OpenCloudOS/openEuler/Kylin 等衍生版）、Debian 9+、Ubuntu 16+；支持 x86_64 与 aarch64

# 关键设计约束（务必遵守）

1. **不生成 init.d/*.service**：OpenJDK 无常驻进程。
2. **多版本共存**：安装新版本不得破坏已装版本；默认版本仅由 `/usr/local/java` 软链与 alternatives 决定。
3. **环境变量统一走 `/etc/profile.d/openjdk.sh`**（幂等重写），不得反复追加 `/etc/profile`；
   但卸载时必须兼容清理历史遗留的 `/etc/profile` 中 `JAVA_HOME`/`CLASSPATH`/`PATH` 记录。
4. **CLASSPATH 分版本**：JDK 8 写 `tools.jar`/`dt.jar`；JDK 9+ 只写 `.`（模块化后这两个 jar 不存在）。
5. **JAVA_HOME 探测必须兼容**：`java-1.8.0-openjdk`、`java-{N}-openjdk`、`java-{N}-openjdk-${SYS_ARCH}`、
   `temurin-{N}-jdk[-${SYS_ARCH}]`、`${jdk_base_dir}/jdk-{N}`，其中 `SYS_ARCH` 为 `amd64`/`arm64`（参考 oneinstack check_os.sh）。
6. **Adoptium API 架构名**为 `x64`/`aarch64`（与 SYS_ARCH 不同，勿混用）。
7. **卸载安全**：先检测是否有 JVM 进程正在使用该 JDK（`ps -eo pid,args | grep "${JAVA_HOME}/bin/java"`），
   有占用则拒绝并提示 `--force`；卸载当前默认版本后必须自动改指向其他已装版本或彻底清理环境变量。
8. **升级仅限同 feature 版本**：跨大版本必须报错并引导 `install.sh` + `switch.sh`；升级失败要能自动回滚。
9. **补丁版本不硬编码**：`versions.txt` 只固定 feature 版本，补丁版本留空时由 Adoptium API 取最新 GA。
10. **国内网络优先**：Adoptium 仓库与镜像默认使用清华镜像（`https://mirrors.tuna.tsinghua.edu.cn/Adoptium/...`），
    GPG 公钥优先读取本地 `src/adoptium.key`，读取失败再走网络。

# 输出要求

请生成以下文件，每个文件的代码必须完整、可直接运行：

## 文件清单

### 1. `options.conf` — 中央配置文件
- 镜像源：mirror_link、adoptium_deb_mirror、adoptium_rpm_mirror、adoptium_api
- 安装方式：install_method（package|binary）
- 路径：jdk_base_dir、jdk_link（/usr/local/java）、log_dir
- 版本：jdk_support_vers、jdk_current_ver（自动写入）、jdk_patch_ver
- 备份：backup_dir、expired_days、backup_destination、backup_content（cacerts,conf,jdk）、各云存储 bucket
- 监控阈值：jvm_heap_threshold、jvm_fullgc_threshold、jvm_thread_threshold、disk_threshold
- 告警：alert_email、webhook_url

### 2. `versions.txt` — 版本号清单
- `jdk8_ver=8` … `jdk21_ver=21`
- `jdk{N}_patch_ver=`（留空=自动取最新 GA）
- `jdk_default_ver=17`

### 3. `include/color.sh` — 颜色定义
- CSUCCESS(绿)、CFAILURE(红)、CWARNING(黄)、CMSG(青)、CEND(重置)

### 4. `include/check_os.sh` — 操作系统检测
- 解析 `/etc/os-release`，输出 `Platform`、`Family`(rhel/debian/ubuntu)、`PM`(yum/apt-get)、
  `RHEL_ver`/`Debian_ver`/`Ubuntu_ver`、`ARCH`、`SYS_ARCH`(amd64/arm64)、`THREAD`
- 拒绝 32 位系统；识别 CentOS/RHEL 主流衍生版并归一化版本号
- 不支持的 OS：输出红色提示并 `kill -9 $$; exit 1`

### 5. `include/check_env.sh` — 环境检测
- `Check_Deps()` — 确保 wget/curl/tar/gzip 存在（缺失则用 $PM 安装）；Debian 系确保
  `software-properties-common`、`gnupg`、`apt-transport-https`、`ca-certificates`
- `Check_Installed_JDK(ver)` — 判断指定 feature 版本是否已安装（幂等依据）
- `Detect_JAVA_HOME(ver)` — 按候选路径列表 + 模糊匹配探测，排除 jre 目录
- `Check_Net()` — 检测能否访问 Adoptium API/镜像，失败时提示使用本地 src 包

### 6. `include/download.sh` — 下载函数
- `Download_src()`：通过 `src_url` 传入地址，多源容错（Adoptium API → 清华镜像 → 本地 src 已有包）
- 支持断点续传（wget -c）；下载结果 <1KB 或含 HTML 标签视为错误页并换源
- 全部失败时打印手动下载路径并退出

### 7. `include/adoptium_repo.sh` — Adoptium 仓库配置
- `Add_Adoptium_Repo()`：
  - rhel：写 `/etc/yum.repos.d/adoptium.repo`（baseurl 使用 `rhel$releasever-$basearch`，gpgcheck=0）
  - debian/ubuntu：导入 `src/adoptium.key`（缺失则网络获取）→ `apt-add-repository --yes ${adoptium_deb_mirror}` → `apt-get -y update`
- `Del_Adoptium_Repo()`：卸载时可选清理仓库配置

### 8. `include/openjdk_package.sh` — 包管理器安装
- `Get_Pkg_Name(ver)`：输出 `pkg_name`、`java_home`、`use_temurin`，覆盖以下已知缺包场景：
  - RHEL 7：17/18/21 走 temurin
  - Debian 10+：8 走 temurin；Debian 9/10：17/21 走 temurin
  - Ubuntu 16：11/17/18/21 走 temurin
  - 其余走发行版包（`java-1.8.0-openjdk-devel`、`java-{N}-openjdk-devel`、`openjdk-{N}-jdk`）
- `Install_JDK_Package(ver)`：必要时配置 Adoptium 仓库 → 安装 → 二次探测 JAVA_HOME
- `Uninstall_JDK_Package(ver)`：yum remove / apt purge + autoremove

### 9. `include/openjdk_binary.sh` — tar.gz 二进制安装
- `Get_Adoptium_URL(ver)`：Adoptium API v3，`latest/{ver}/ga/linux/{x64|aarch64}/jdk/hotspot/normal/eclipse`；
  指定 `jdk_patch_ver` 时改用 `version/jdk-{patch}/...`
- `Install_JDK_Binary(ver)`：下载 → 解压 → 已存在同版本目录先重命名备份 → 移动到 `${jdk_base_dir}/jdk-{ver}` → 清理临时目录
- `Uninstall_JDK_Binary(ver)`：目录重命名备份，按 `--keep-backup` 决定是否删除

### 10. `include/jdk_env.sh` — 环境变量与 alternatives 管理
- `Set_JDK_Env(java_home, ver)`：更新 `${jdk_link}` 软链 + 幂等重写 `/etc/profile.d/openjdk.sh`（CLASSPATH 分版本）+ 立即 source
- `Unset_JDK_Env()`：删除 profile.d 文件与软链，并 sed 清理 `/etc/profile` 的历史 JAVA_HOME/CLASSPATH/PATH 残留
- `Register_Alternatives(java_home, ver)`：注册 java/javac/jar/javadoc/keytool/jshell/jcmd/jstack/jmap/jstat，priority=ver*100，
  自动区分 `alternatives`(rhel) 与 `update-alternatives`(debian 系)，仅注册实际存在的命令
- `Unregister_Alternatives(java_home)`：`--remove` 逐一注销
- `List_JDK()`：输出 `feature_ver full_ver java_home [*]`（`*` 表示当前默认）
- `Switch_JDK(ver)`：切软链 + alternatives --set + 写回 options.conf + 校验并提示需重启 JVM 进程

### 11. `include/openjdk.sh` — 安装/卸载编排
- `Install_OpenJDK(ver)`：
  1. 已装检测（幂等，已装则提示并可选设为默认后返回）
  2. `Check_Deps`
  3. 按 `install_method` 调用 package 或 binary 实现
  4. `Detect_JAVA_HOME` 校验
  5. 非 `--no_default` 时 `Set_JDK_Env` + `Register_Alternatives`
  6. 创建 `log_dir`
  7. 验证 `java -version` 与 `javac -version`，成功输出绿色摘要（版本、JAVA_HOME、安装方式），失败输出红色提示 +
     `grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release` + `kill -9 $$; exit 1`
  8. 写回 options.conf 的 `jdk_current_ver`
- `Print_OpenJDK(ver)`：卸载预览（JDK 目录、软链、profile.d、alternatives 条目）
- `Uninstall_OpenJDK(ver)`：占用检测 → 注销 alternatives → 按安装方式卸载 → 默认版本回退或清理环境 → 清理 options.conf
- `Check_JDK_InUse(java_home)`：列出占用该 JDK 的 JVM 进程

### 12. `include/upgrade_jdk.sh` — 升级模块
- `Upgrade_OpenJDK(ver)`：当前版本检测 → Adoptium API 取最新补丁 → 交互确认目标版本 →
  校验（不可同版本、feature 版本必须一致）→ 备份（`lib/security`+`conf` 打 tgz，目录 cp -a 备份）→
  安装新补丁 → 更新软链/alternatives → 验证 → 失败自动回滚 → 成功清理备份并打印
  `Successfully upgrade OpenJDK from X to Y`
- 升级前列出依赖该 JDK 的 JVM 进程，提示用户升级后需重启这些服务

### 13. `include/monitor_jdk.sh` — 监控模块
- `Check_JDK_Health()` — JAVA_HOME 软链有效性、`java -version` 可执行、PATH 中 java 与 JAVA_HOME 是否一致
- `Check_JVM_Process()` — `jps -l` 列出所有 JVM
- `Check_JVM_Heap()` — `jcmd GC.heap_info` + `VM.flags` 计算堆使用率，超过 `jvm_heap_threshold` 告警
- `Check_JVM_GC()` — `jstat -gcutil` 读取 Full GC 次数与耗时，超阈值告警
- `Check_JVM_Thread()` — `/proc/{pid}/task` 统计线程数，超阈值告警
- `Check_Disk()` — 磁盘使用率检查
- `Send_Alert()` — 写日志 + 邮件 + Webhook（钉钉/飞书/Slack 通用 JSON）
- `Monitor_Status()` — 输出默认 JDK、已装版本清单、JVM 进程与 GC 概览

### 14. `install.sh` — 安装主入口
- 头部：`#!/bin/bash`、固定 PATH、root 检查、`openjdk_dir=$(dirname "$(readlink -f $0)")`、
  source options.conf/versions.txt/include 各模块
- getopt 解析：`-h/--help`、`-v/--version`、`-q/--quiet`、`--jdk_option`、`--install_method`、
  `--jdk_patch_ver`、`--set_default`、`--no_default`；参数非法时给出黄色提示并退出
- `ARG_NUM=$#`，为 0 时进入交互菜单：
  - 菜单一：选择 JDK 版本（1=8 2=11 3=17(默认) 4=18(EOL,不推荐) 5=21）
  - 菜单二：选择安装方式（1=包管理器(默认) 2=tar.gz 二进制）
  - 菜单三：是否设为默认 JDK
- 全过程 `2>&1 | tee -a ${openjdk_dir}/install.log`
- 结束打印摘要：版本、JAVA_HOME、安装方式、已装版本清单、生效方式（`source /etc/profile.d/openjdk.sh`）

### 15. `uninstall.sh` — 卸载主入口
- getopt：`--jdk_option`、`--all`、`--force`、`--keep-backup`、`-q/--quiet`
- 无参数进交互菜单，列出已装版本供选择
- 先 `Print_OpenJDK` 预览 → `Uninstall_status()` 确认（`[y/n]` 正则校验）→ 执行
- `--all` 时逐个卸载并最终 `Unset_JDK_Env`

### 16. `upgrade.sh` — 升级主入口
- getopt：`--jdk_option`、`--jdk_patch_ver`、`-q/--quiet`
- 无参数时列出已装版本菜单，source `include/upgrade_jdk.sh` 调用 `Upgrade_OpenJDK`

### 17. `switch.sh` — 默认 JDK 切换（OpenJDK 专属）
- getopt：`--jdk_option`、`--list`
- `--list` 调用 `List_JDK` 表格化输出；无参数时交互选择
- 切换后回显 `java -version`，并提示已运行的 JVM 进程需重启才生效

### 18. `backup.sh` — 备份执行脚本
- 由 cron 调用，读取 options.conf
- 备份内容按 `backup_content`：`cacerts`（lib/security）、`conf`（conf 或 jre/lib/security）、`jdk`（整目录）
- 附带生成已装 JDK 清单文件，便于灾备重建
- 目标按 `backup_destination` 分发：local/remote(rsync|scp)/oss(ossutil)/cos(coscli)/s3(aws s3)
- 命名 `JDK_{ver}_{YYYYmmdd}_{HHMMSS}.tgz`；按 `expired_days` 清理过期备份

### 19. `backup_setup.sh` — 备份配置向导
- 交互式选择备份目标、备份内容、云存储凭证并测试连通性
- 结果 sed 写回 options.conf
- 写入 cron（如 `0 3 * * * /path/backup.sh`），写入前先去重

### 20. `monitor.sh` — 监控主入口
- getopt：`--status`、`--check`、`--jvm <pid>`
- `--check` 依次执行 Check_JDK_Health / Check_JVM_Heap / Check_JVM_GC / Check_JVM_Thread / Check_Disk
- `--jvm <pid>` 输出该进程的 `jinfo`/`jstat -gcutil`/线程数/堆信息
- 输出同时写入 `${log_dir}/monitor.log`；异常触发 Send_Alert

### 21. `tools/jvm_diag.sh` — JVM 诊断采集
- 输入 pid，采集 `jcmd VM.version`、`VM.flags`、`Thread.print`（3 次间隔 5 秒）、`jstat -gcutil`（10 次）、
  可选 `jmap -dump:live`（需 `--heapdump` 显式开启，因为会 STW）
- 打包为 `jvmdiag_{pid}_{timestamp}.tgz` 输出到 backup_dir

### 22. `tools/cacerts_import.sh` — 企业 CA 导入
- 输入证书文件与别名，`keytool -importcert` 导入 `${JAVA_HOME}/lib/security/cacerts`（JDK 8 为 `jre/lib/security/cacerts`）
- 导入前自动备份 cacerts；默认口令 changeit 可通过参数覆盖；导入后 `keytool -list` 校验

### 23. `tools/jdk_list.sh` — 已装 JDK 清单
- 表格输出 feature 版本、完整版本、发行方（openjdk/temurin）、JAVA_HOME、是否当前默认

### 24. `config/openjdk.sh.tpl` — profile.d 模板
- 占位符 `{{JAVA_HOME}}`、`{{CLASSPATH}}`，由 `Set_JDK_Env` 渲染

### 25. `config/jvm_opts.conf` — 推荐 JVM 参数模板
- 按 JDK 8 / 11-17 / 21 给出堆、GC（G1/ZGC）、GC 日志、OOM HeapDump、编码等推荐参数

### 26. `README.md`
- 支持版本与 OS 矩阵、包名/路径对照表、快速开始（安装/切换/升级/卸载/监控/备份）、常见问题
  （无网环境离线安装、Adoptium 仓库不可用、多 JDK 场景下业务未生效需重启）

# 代码规范约束

1. **Shell 版本**: `#!/bin/bash`，兼容 Bash 4.0+
2. **缩进**: 2 空格
3. **变量命名**: 小写 + 下划线（`jdk_install_dir`、`java_home`），常量大写（`THREAD`、`PM`、`SYS_ARCH`）
4. **函数命名**: 大驼峰下划线（`Install_OpenJDK`、`Detect_JAVA_HOME`、`Switch_JDK`）
5. **幂等性**: 重复执行安装不报错、不破坏已有版本；profile.d 与 alternatives 重复注册安全
6. **错误处理**: 关键失败 `kill -9 $$; exit 1`；删除目录前先重命名备份（`/bin/mv dir{,$(date +%Y%m%d%H)}`）
7. **日志输出**: 统一使用 color.sh 颜色变量；安装过程 `tee -a install.log`
8. **PATH 固定**: 脚本开头 `export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin`
9. **root 检查**: `[ $(id -u) != '0' ] && { echo "${CFAILURE}Error: must be root${CEND}"; exit 1; }`
10. **目录切换**: 使用 `pushd/popd > /dev/null`
11. **临时文件**: 解压产物与临时目录用完即清理
12. **配置分离**: 可变参数放 options.conf，版本号放 versions.txt，代码内只引用变量，禁止硬编码路径与版本
13. **安全**: 不硬编码任何口令；keytool 默认口令通过参数传入；仓库 GPG key 优先用本地文件
14. **兼容性**: x86_64 与 aarch64；RHEL/Debian/Ubuntu 系列及主流国产衍生版

请基于以上规范，生成 OpenJDK 的完整运维代码。每个文件独立输出，包含完整可运行的代码。
```

---

## 提示词使用说明

### 如何使用

1. **复制上述提示词**（从 `# 角色` 到 `请基于以上规范...`）
2. **粘贴到 AI 编程工具**（Cursor / Windsurf / ChatGPT 等）
3. AI 将生成一套完整的 OpenJDK 运维脚本

### 快速部署示例

```bash
# 交互式安装
./install.sh

# 静默安装 OpenJDK 17（包管理器方式，并设为默认）
./install.sh -q --jdk_option 3 --install_method package

# 安装 OpenJDK 21（tar.gz 方式，锁定补丁版本，不改变默认 JDK）
./install.sh -q --jdk_option 5 --install_method binary --jdk_patch_ver 21.0.7+6 --no_default

# 多版本共存 + 切换默认
./switch.sh --list
./switch.sh --jdk_option 2      # 切到 OpenJDK 11
```

### 常用运维命令

```bash
# 查看状态（默认 JDK、已装版本、JVM 进程）
./monitor.sh --status

# 健康检查（堆/GC/线程/磁盘）
./monitor.sh --check

# 指定 JVM 进程详情
./monitor.sh --jvm 12345

# 同 feature 版本补丁升级
./upgrade.sh --jdk_option 3

# 备份 cacerts 与安全配置
./backup.sh

# 卸载 OpenJDK 18（保留目录备份）
./uninstall.sh --jdk_option 4 --keep-backup
```

---

# 附录：OpenJDK 运维速查表

## A. 包名与 JAVA_HOME 对照表

| OS 家族 | 版本条件 | JDK | 包名 | JAVA_HOME |
|---------|---------|-----|------|-----------|
| rhel | 全部 | 8 | `java-1.8.0-openjdk-devel` | `/usr/lib/jvm/java-1.8.0-openjdk` |
| rhel | 8+ | 11/17/21 | `java-{N}-openjdk-devel` | `/usr/lib/jvm/java-{N}-openjdk` |
| rhel | 7 | 17/18/21 | `temurin-{N}-jdk`（Adoptium） | `/usr/lib/jvm/temurin-{N}-jdk` |
| debian | 9 | 8 | `openjdk-8-jdk` | `/usr/lib/jvm/java-8-openjdk-${SYS_ARCH}` |
| debian | 10~13 | 8 | `temurin-8-jdk`（Adoptium） | `/usr/lib/jvm/temurin-8-jdk-${SYS_ARCH}` |
| debian | 11+ | 11/17/21 | `openjdk-{N}-jdk` | `/usr/lib/jvm/java-{N}-openjdk-${SYS_ARCH}` |
| ubuntu | 16 | 11/17/18/21 | `temurin-{N}-jdk`（Adoptium） | `/usr/lib/jvm/temurin-{N}-jdk-${SYS_ARCH}` |
| ubuntu | 18+ | 8/11/17/21 | `openjdk-{N}-jdk` | `/usr/lib/jvm/java-{N}-openjdk-${SYS_ARCH}` |
| 任意 | binary 模式 | 全部 | — | `${jdk_base_dir}/jdk-{N}` |

> `SYS_ARCH`：x86_64 → `amd64`；aarch64 → `arm64`（来源 oneinstack `check_os.sh`）。
> Adoptium API 架构名不同：x86_64 → `x64`；aarch64 → `aarch64`。

## B. 常用 JDK 工具速查

| 命令 | 用途 | 示例 |
|------|------|------|
| `java -version` | 查看版本 | `java -version` |
| `jps -l` | 列出 JVM 进程 | `jps -l` |
| `jstat -gcutil` | GC 统计 | `jstat -gcutil 1234 1000 10` |
| `jcmd VM.flags` | 查看生效 JVM 参数 | `jcmd 1234 VM.flags` |
| `jcmd GC.heap_info` | 堆使用情况 | `jcmd 1234 GC.heap_info` |
| `jstack` | 线程栈（排查死锁/卡顿） | `jstack 1234 > stack.txt` |
| `jmap -histo:live` | 对象分布（会触发 GC） | `jmap -histo:live 1234 \| head -30` |
| `jmap -dump:live` | 堆转储（STW，谨慎） | `jmap -dump:live,format=b,file=h.hprof 1234` |
| `keytool -list` | 查看证书库 | `keytool -list -keystore $JAVA_HOME/lib/security/cacerts` |
| `alternatives --config java` | 切换默认 java（rhel） | `alternatives --config java` |
| `update-alternatives --config java` | 切换默认 java（debian 系） | `update-alternatives --config java` |

## C. 组件与 JDK 版本兼容参考

| 组件 | 推荐 JDK |
|------|---------|
| ZooKeeper 3.7 / 3.8 | 8 或 11 |
| ZooKeeper 3.9 | 11+ |
| Doris FE 2.0 | 8 或 11 |
| Doris FE 2.1 / 3.x | 17 |
| DolphinScheduler 3.x | 8 或 11（3.2+ 支持 17） |
| SeaTunnel 2.3.x | 8 或 11 |
| Tomcat 9 / 10 / 11 | 8+ / 11+ / 17+ |

## D. oneinstack 模式映射表

| 模式 | oneinstack 原实现 | 本方案通用化 |
|------|------------------|-------------|
| 按 OS 分支选包 | `openjdk-8/11/17.sh` 中 `Family` + `*_ver` 判断 | `Get_Pkg_Name()` 统一映射表 |
| 老系统兜底 | 挂清华 Adoptium 源装 `temurin-*-jdk` | `Add_Adoptium_Repo()` + `use_temurin` 标志 |
| 环境变量写入 | `cat > /etc/profile.d/openjdk.sh` | `Set_JDK_Env()`（保留此法，弃用 `openjdk-18.sh` 追加 /etc/profile 的写法） |
| 安装校验 | `[ -e "${JAVA_HOME}/bin/java" ]` + 成功/失败双分支 | `java -version` + `javac -version` 双校验 |
| 失败处理 | 打印 os-release + `kill -9 $$; exit 1` | 完全沿用 |
| 环境清理 | `uninstall.sh` 中 sed 删除 JAVA_HOME/CLASSPATH/PATH | `Unset_JDK_Env()`，兼容历史残留 |
| 多版本切换 | 官方 `change_jdk_version.sh` | `switch.sh` + 软链 + alternatives |
| GPG 公钥本地化 | `cat ${oneinstack_dir}/src/adoptium.key \| apt-key add -` | 优先本地 `src/adoptium.key`，失败再走网络 |
