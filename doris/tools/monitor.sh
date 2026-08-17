#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Simple monitoring script for Doris cluster

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

doris_dir=$(dirname "$(dirname "$(readlink -f $0)")")
pushd ${doris_dir} > /dev/null
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${doris_dir}"
. ./options.conf
. ./include/color.sh

LOCAL_IP=$(hostname -I | awk '{print $1}')

echo "========================================"
echo "  Doris Cluster Monitor"
echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Host: ${LOCAL_IP}"
echo "========================================"
echo ""

# Check FE process
echo "=== FE Process ==="
if ps aux | grep -v grep | grep -q "${fe_install_dir}"; then
  fe_pid=$(ps aux | grep -v grep | grep "${fe_install_dir}" | awk '{print $2}' | head -1)
  fe_mem=$(ps -p ${fe_pid} -o %mem= 2>/dev/null | tr -d ' ')
  fe_cpu=$(ps -p ${fe_pid} -o %cpu= 2>/dev/null | tr -d ' ')
  echo "  Status: RUNNING (PID: ${fe_pid})"
  echo "  Memory: ${fe_mem}%"
  echo "  CPU:    ${fe_cpu}%"
else
  echo "  Status: NOT RUNNING"
fi
echo ""

# Check BE process
echo "=== BE Process ==="
if ps aux | grep -v grep | grep -q "${be_install_dir}"; then
  be_pid=$(ps aux | grep -v grep | grep "${be_install_dir}" | awk '{print $2}' | head -1)
  be_mem=$(ps -p ${be_pid} -o %mem= 2>/dev/null | tr -d ' ')
  be_cpu=$(ps -p ${be_pid} -o %cpu= 2>/dev/null | tr -d ' ')
  echo "  Status: RUNNING (PID: ${be_pid})"
  echo "  Memory: ${be_mem}%"
  echo "  CPU:    ${be_cpu}%"
else
  echo "  Status: NOT RUNNING"
fi
echo ""

# Check MS process
echo "=== MS Process ==="
if ps aux | grep -v grep | grep -q "doris_cloud\|meta_service\|${ms_install_dir}"; then
  ms_pid=$(ps aux | grep -v grep | grep -E "doris_cloud|meta_service|${ms_install_dir}" | awk '{print $2}' | head -1)
  ms_mem=$(ps -p ${ms_pid} -o %mem= 2>/dev/null | tr -d ' ')
  ms_cpu=$(ps -p ${ms_pid} -o %cpu= 2>/dev/null | tr -d ' ')
  echo "  Status: RUNNING (PID: ${ms_pid})"
  echo "  Memory: ${ms_mem}%"
  echo "  CPU:    ${ms_cpu}%"
else
  echo "  Status: NOT RUNNING (or not installed)"
fi
echo ""

# Check disk usage
echo "=== Disk Usage ==="
if [ -d "${fe_meta_dir}" ]; then
  fe_disk=$(df -h ${fe_meta_dir} | tail -1 | awk '{print $5}')
  echo "  FE Meta (${fe_meta_dir}): ${fe_disk} used"
fi
if [ -d "${be_data_dir}" ]; then
  be_disk=$(df -h ${be_data_dir} | tail -1 | awk '{print $5}')
  be_size=$(du -sh ${be_data_dir} 2>/dev/null | awk '{print $1}')
  echo "  BE Data (${be_data_dir}): ${be_disk} used, Data size: ${be_size}"
fi
echo ""

# Check connectivity
echo "=== Connectivity ==="
if mysql -uroot -P${fe_query_port} -h${LOCAL_IP} -e "SELECT 1" > /dev/null 2>&1; then
  echo "  FE Query Port (${fe_query_port}): OK"

  # Get cluster metrics
  be_count=$(mysql -uroot -P${fe_query_port} -h${LOCAL_IP} -N -e "SELECT COUNT(*) FROM information_schema.backends WHERE Alive='true'" 2>/dev/null)
  fe_count=$(mysql -uroot -P${fe_query_port} -h${LOCAL_IP} -N -e "SELECT COUNT(*) FROM information_schema.frontends WHERE Alive='true'" 2>/dev/null)
  echo "  Active FE nodes: ${fe_count:-N/A}"
  echo "  Active BE nodes: ${be_count:-N/A}"
else
  echo "  FE Query Port (${fe_query_port}): FAILED"
fi
echo ""

# Check FE HTTP
if curl -s -o /dev/null -w "%{http_code}" http://${LOCAL_IP}:${fe_http_port} | grep -q "200\|302"; then
  echo "  FE HTTP Port (${fe_http_port}): OK"
else
  echo "  FE HTTP Port (${fe_http_port}): FAILED"
fi

popd > /dev/null
