#!/bin/bash
# SSH 互信工具主入口
# 项目: sshtrust
# 用法: ./sshtrust.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本目录
script_dir=$(cd "$(dirname "$0")" && pwd)

# 加载配置和公共库
. "${script_dir}/options.conf"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/check_env.sh"
. "${script_dir}/include/sshtrust_core.sh"

# 显示帮助
Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

SSH Trust Management Tool

Options:
  -h, --help              Show this help message
  -q, --quiet             Quiet mode, skip confirmations

  -a, --add HOST [HOST...]  Add trust host(s)
      Format: host | user@host | user@host:port | host:port
  -f, --add-file FILE       Import hosts from file and add trust
      File format: one host per line, # for comments
  -r, --remove HOST [HOST...]  Remove trust host(s)
  -l, --list              List current trust configuration
  -c, --check             Check trust connectivity
  -m, --mesh              Setup full mesh trust (all-to-all)
      --init              Initialize local SSH key pair only

  -u, --user USER         Override SSH user (default: ${ssh_user})
  -p, --port PORT         Override SSH port (default: ${ssh_port})

Examples:
  # Interactive menu
  $0

  # Add single host
  $0 --add 192.168.1.10

  # Add multiple hosts with custom user
  $0 --add 192.168.1.10 192.168.1.11 --user root

  # Add host with specific user and port
  $0 --add root@192.168.1.12:2222

  # Import hosts from file
  $0 --add-file hosts.txt

  # Remove trust
  $0 --remove 192.168.1.10

  # List current configuration
  $0 --list

  # Check connectivity
  $0 --check

  # Setup full mesh trust
  $0 --mesh

  # Initialize key pair only
  $0 --init

EOF
}

# 交互式菜单
Show_Menu() {
  clear
  echo ""
  echo "${CMSG}#######################################################################${CEND}"
  echo "${CMSG}#                     SSH Trust Management Tool                      #${CEND}"
  echo "${CMSG}#                          sshtrust                                   #${CEND}"
  echo "${CMSG}#######################################################################${CEND}"
  echo ""

  while :; do
    echo "${CMSG}Main Menu:${CEND}"
    echo "  1) Add trust host(s) — manual input"
    echo "  2) Add trust host(s) — from file"
    echo "  3) Remove trust host(s)"
    echo "  4) List current trust configuration"
    echo "  5) Check trust connectivity"
    echo "  6) Setup full mesh trust (all-to-all)"
    echo "  7) Initialize local SSH key pair"
    echo "  8) Quit"
    echo ""

    read -e -p "Enter your choice [1-8]: " choice

    case "${choice}" in
      1)
        echo ""
        echo "${CMSG}Add Trust Host(s)${CEND}"
        echo "Enter host(s), space separated."
        echo "Format: host | user@host | user@host:port"
        echo "Example: 192.168.1.10 root@192.168.1.11:2222"
        echo ""
        read -e -p "Hosts: " input_hosts
        [ -z "${input_hosts}" ] && {
          echo "${CWARNING}No hosts entered${CEND}"
          echo ""
          continue
        }
        echo ""
        Check_All || { echo ""; continue; }
        echo ""
        Add_Trust ${input_hosts}
        echo ""
        read -e -p "Press Enter to continue..."
        ;;
      2)
        echo ""
        echo "${CMSG}Add Trust Host(s) From File${CEND}"
        read -e -p "Enter file path: " file_path
        [ -z "${file_path}" ] && {
          echo "${CWARNING}No file specified${CEND}"
          echo ""
          continue
        }
        echo ""
        Check_All || { echo ""; continue; }
        echo ""
        Add_Trust_From_File "${file_path}"
        echo ""
        read -e -p "Press Enter to continue..."
        ;;
      3)
        echo ""
        echo "${CMSG}Remove Trust Host(s)${CEND}"
        if [ -z "${trust_hosts}" ]; then
          echo "${CWARNING}No trust hosts configured${CEND}"
          echo ""
          continue
        fi
        List_Trust
        echo "Enter host(s) to remove, space separated:"
        read -e -p "Hosts: " rm_hosts
        [ -z "${rm_hosts}" ] && {
          echo "${CWARNING}No hosts entered${CEND}"
          echo ""
          continue
        }
        echo ""
        Remove_Trust ${rm_hosts}
        echo ""
        read -e -p "Press Enter to continue..."
        ;;
      4)
        echo ""
        List_Trust
        read -e -p "Press Enter to continue..."
        ;;
      5)
        echo ""
        Check_Trust
        echo ""
        read -e -p "Press Enter to continue..."
        ;;
      6)
        echo ""
        echo "${CMSG}Setup Full Mesh Trust${CEND}"
        echo "This will establish mutual trust between ALL configured hosts."
        if [ -z "${trust_hosts}" ]; then
          echo "${CFAILURE}No trust hosts configured${CEND}"
          echo "Please add hosts first (option 1 or 2)."
          echo ""
          continue
        fi
        echo ""
        List_Trust
        read -e -p "Continue with mesh setup? [y/n]: " mesh_confirm
        [ "${mesh_confirm}" != "y" ] && {
          echo "Cancelled."
          echo ""
          continue
        }
        echo ""
        Check_All || { echo ""; continue; }
        echo ""
        Setup_Mesh
        echo ""
        read -e -p "Press Enter to continue..."
        ;;
      7)
        echo ""
        Check_OS
        echo ""
        Generate_Key
        echo ""
        read -e -p "Press Enter to continue..."
        ;;
      8)
        echo "Bye."
        exit 0
        ;;
      *)
        echo "${CWARNING}Invalid choice, please try again${CEND}"
        echo ""
        ;;
    esac
  done
}

# 解析参数
ARG_NUM=$#
quiet_mode=0
action=""
hosts=()
file_path=""
override_user=""
override_port=""

TEMP=$(getopt -o hqma:f:r:lcu:p: --long help,quiet,add:,add-file:,remove:,list,check,mesh,init,user:,port: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }

eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    -q|--quiet)
      quiet_mode=1
      shift
      ;;
    -a|--add)
      action="add"
      shift
      # 收集所有非选项参数直到下一个选项
      while [ $# -gt 0 ] && [[ "$1" != -* ]]; do
        hosts+=("$1")
        shift
      done
      ;;
    -f|--add-file)
      action="add-file"
      file_path="$2"
      shift 2
      ;;
    -r|--remove)
      action="remove"
      shift
      while [ $# -gt 0 ] && [[ "$1" != -* ]]; do
        hosts+=("$1")
        shift
      done
      ;;
    -l|--list)
      action="list"
      shift
      ;;
    -c|--check)
      action="check"
      shift
      ;;
    -m|--mesh)
      action="mesh"
      shift
      ;;
    --init)
      action="init"
      shift
      ;;
    -u|--user)
      override_user="$2"
      shift 2
      ;;
    -p|--port)
      override_port="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

# 应用覆盖参数
[ -n "${override_user}" ] && ssh_user="${override_user}"
[ -n "${override_port}" ] && ssh_port="${override_port}"

# 主逻辑
main() {
  if [ ${ARG_NUM} -eq 0 ]; then
    Show_Menu
    exit 0
  fi

  case "${action}" in
    add)
      Check_OS > /dev/null 2>&1
      Check_All || exit 1
      echo ""
      Add_Trust "${hosts[@]}"
      exit $?
      ;;
    add-file)
      Check_OS > /dev/null 2>&1
      Check_All || exit 1
      echo ""
      Add_Trust_From_File "${file_path}"
      exit $?
      ;;
    remove)
      echo ""
      Remove_Trust "${hosts[@]}"
      exit $?
      ;;
    list)
      List_Trust
      exit 0
      ;;
    check)
      echo ""
      Check_Trust
      exit $?
      ;;
    mesh)
      Check_OS > /dev/null 2>&1
      Check_All || exit 1
      echo ""
      Setup_Mesh
      exit $?
      ;;
    init)
      Check_OS
      echo ""
      Generate_Key
      exit $?
      ;;
    *)
      echo "${CFAILURE}No action specified${CEND}"
      Show_Help
      exit 1
      ;;
  esac
}

main
