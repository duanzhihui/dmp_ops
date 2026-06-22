#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Configuration Generation Module
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

Generate_Seatunnel_Yaml() {
  local config_dir=${1:-${seatunnel_install_dir}/config}
  local backup_count=${imap_backup_count:-1}
  local checkpoint_interval_val=${checkpoint_interval:-10000}
  local checkpoint_timeout_val=${checkpoint_timeout:-60000}
  local checkpoint_retained=${checkpoint_max_retained:-3}
  local checkpoint_type=${checkpoint_storage_type:-localfile}
  local checkpoint_ns=${seatunnel_checkpoint_dir:-/opt/seatunnel/checkpoint}
  local history_expire=${history_job_expire_minutes:-1440}
  local schedule_strategy=${job_schedule_strategy:-REJECT}

  echo "${CMSG}Generating seatunnel.yaml...${CEND}"

  cat > ${config_dir}/seatunnel.yaml << EOF
seatunnel:
  engine:
    backup-count: ${backup_count}
    queue-type: blockingqueue
    slot-service:
      dynamic-slot: true
    checkpoint:
      interval: ${checkpoint_interval_val}
      timeout: ${checkpoint_timeout_val}
      storage:
        type: ${checkpoint_type}
        max-retained: ${checkpoint_retained}
        plugin-config:
          namespace: ${checkpoint_ns}
    history-job-expire-minutes: ${history_expire}
    classloader-cache-mode: true
    job-schedule-strategy: ${schedule_strategy}
EOF

  echo "${CSUCCESS}seatunnel.yaml generated successfully!${CEND}"
}

Generate_Hazelcast_Yaml() {
  local config_dir=${1:-${seatunnel_install_dir}/config}
  local cluster=${cluster_name:-seatunnel}
  local port=${hazelcast_port:-5801}
  local members=${cluster_members:-127.0.0.1}

  echo "${CMSG}Generating hazelcast.yaml...${CEND}"

  # Convert comma-separated members to YAML list
  local member_list=""
  IFS=',' read -ra ADDR <<< "${members}"
  for addr in "${ADDR[@]}"; do
    member_list="${member_list}          - ${addr}\n"
  done

  cat > ${config_dir}/hazelcast.yaml << EOF
hazelcast:
  cluster-name: ${cluster}
  network:
    rest-api:
      enabled: true
      endpoint-groups:
        CLUSTER_READ:
          enabled: true
        DATA:
          enabled: true
    join:
      tcp-ip:
        enabled: true
        member-list:
$(echo -e "${member_list}" | sed 's/^//')
    port:
      auto-increment: false
      port: ${port}
  properties:
    hazelcast.invocation.max.retry.count: 20
    hazelcast.tcp.join.port.try.count: 30
    hazelcast.logging.type: log4j2
    hazelcast.operation.generic.thread.count: 50
EOF

  echo "${CSUCCESS}hazelcast.yaml generated successfully!${CEND}"
}

Generate_Hazelcast_Client_Yaml() {
  local config_dir=${1:-${seatunnel_install_dir}/config}
  local cluster=${cluster_name:-seatunnel}
  local members=${cluster_members:-127.0.0.1}

  echo "${CMSG}Generating hazelcast-client.yaml...${CEND}"

  # Convert comma-separated members to YAML list
  local member_list=""
  IFS=',' read -ra ADDR <<< "${members}"
  for addr in "${ADDR[@]}"; do
    member_list="${member_list}        - ${addr}:5801\n"
  done

  cat > ${config_dir}/hazelcast-client.yaml << EOF
hazelcast-client:
  cluster-name: ${cluster}
  properties:
    hazelcast.logging.type: log4j2
  network:
    cluster-members:
$(echo -e "${member_list}" | sed 's/^//')
EOF

  echo "${CSUCCESS}hazelcast-client.yaml generated successfully!${CEND}"
}

Generate_JVM_Options() {
  local config_dir=${1:-${seatunnel_install_dir}/config}
  local heap_size=${jvm_heap_size:-2g}
  local metaspace=${jvm_metaspace_size:-256m}
  local mode=${2:-hybrid}

  echo "${CMSG}Generating JVM options for ${mode} mode...${CEND}"

  local jvm_content="# JVM Heap
-Xms${heap_size}
-Xmx${heap_size}

# JVM Dump
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/tmp/seatunnel/dump/zeta-server

# Metaspace
-XX:MaxMetaspaceSize=${metaspace}

# G1GC
-XX:+UseG1GC"

  if [ "${mode}" == "hybrid" ]; then
    echo "${jvm_content}" > ${config_dir}/jvm_options
    echo "${CSUCCESS}jvm_options generated successfully!${CEND}"
  elif [ "${mode}" == "separated" ]; then
    echo "${jvm_content}" > ${config_dir}/jvm_master_options
    echo "${jvm_content}" > ${config_dir}/jvm_worker_options
    echo "${CSUCCESS}jvm_master_options and jvm_worker_options generated successfully!${CEND}"
  fi

  # Client JVM options (smaller heap)
  cat > ${config_dir}/jvm_client_options << EOF
# JVM Heap
-Xms512m
-Xmx512m

# Metaspace
-XX:MaxMetaspaceSize=128m

# G1GC
-XX:+UseG1GC
EOF
  echo "${CSUCCESS}jvm_client_options generated successfully!${CEND}"
}

Generate_Plugin_Config() {
  local config_dir=${1:-${seatunnel_install_dir}/config}
  local connector_list=${connectors:-connector-fake,connector-console}

  echo "${CMSG}Generating plugin_config...${CEND}"

  cat > ${config_dir}/plugin_config << EOF
--seatunnel-connectors--
EOF

  IFS=',' read -ra CONNECTORS <<< "${connector_list}"
  for connector in "${CONNECTORS[@]}"; do
    echo "${connector}" >> ${config_dir}/plugin_config
  done

  echo "--end--" >> ${config_dir}/plugin_config

  echo "${CSUCCESS}plugin_config generated successfully!${CEND}"
}

Generate_All_Configs() {
  local config_dir=${1:-${seatunnel_install_dir}/config}
  local mode=${deploy_mode:-hybrid}

  mkdir -p ${config_dir}
  mkdir -p ${seatunnel_checkpoint_dir:-/opt/seatunnel/checkpoint}
  mkdir -p /tmp/seatunnel/dump

  Generate_Seatunnel_Yaml ${config_dir}
  Generate_Hazelcast_Yaml ${config_dir}
  Generate_Hazelcast_Client_Yaml ${config_dir}
  Generate_JVM_Options ${config_dir} ${mode}
  Generate_Plugin_Config ${config_dir}
}
