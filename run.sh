#!/bin/bash

# Copyright 2014 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

export_vars=$(cgroup-limits); export $export_vars
source ${CONTAINER_SCRIPTS_PATH}/common.sh
set -e

[ -f ${CONTAINER_SCRIPTS_PATH}/validate-variables.sh ] && source ${CONTAINER_SCRIPTS_PATH}/validate-variables.sh

# Process the Redis configuration files
log_info 'Processing Redis configuration files ...'
if [[ -v REDIS_PASSWORD ]]; then
  envsubst < ${CONTAINER_SCRIPTS_PATH}/password.conf.template >> /etc/redis.conf
else
  log_info 'WARNING: setting REDIS_PASSWORD is recommended'
fi

# Source post-init source if exists
if [ -f ${CONTAINER_SCRIPTS_PATH}/post-init.sh ]; then
  log_info 'Sourcing post-init.sh ...'
  source ${CONTAINER_SCRIPTS_PATH}/post-init.sh
fi

# Restart the Redis server with public IP bindings
unset_env_vars
log_volume_info "${REDIS_DATADIR}"
log_info 'Running final exec -- Only Redis logs after this point'

REDIS_DATA_MAX_AGE=${REDIS_DATA_MAX_AGE:-3}
REDIS_NAMESPACE=${REDIS_NAMESPACE:-""}

# In case of ovs-subnet or projects joined
if [[ "${REDIS_NAMESPACE}" != "" ]]; then
    export REDIS_SENTINEL_SERVICE_HOST=${REDIS_SENTINEL_SERVICE_HOST}.${REDIS_NAMESPACE}
fi

# Restore data from the slave if any
# ignore in case the file are the same
function restore() {
  DUMP=$(find ${REDIS_DATADIR} -name dump.rdb -type f -printf "%T@ %p\n"| sort -nr | head -n 1 | cut -d ' ' -f2)

  if [ ! -z "${DUMP}" ]; then
    APPENDONLY=$(dirname ${DUMP})/appendonly.aof
    echo Restore: ${DUMP}
    cp -a ${DUMP} ${REDIS_DATADIR} || :

    echo Restore: ${APPENDONLY}
    cp -a ${APPENDONLY} ${REDIS_DATADIR}  || :

  fi
}

function housekeeping() {
    find ${REDIS_DATADIR} -name dump.rdb -mtime +${REDIS_DATA_MAX_AGE}  -exec sh -c 'rm -fr $(dirname "{}")' \;
}

function launchmaster() {
  if [[ ! -e ${REDIS_DATADIR} ]]; then
    echo "Redis master data doesn't exist!"
    break
  fi

  restore

  ${REDIS_PREFIX}/bin/redis-server ${HOME}/redis-master/redis.conf
}

function launchsentinel() {
  echo "Using Redis Sentinel Host ${REDIS_SENTINEL_SERVICE_HOST}"
  
  while true; do
    master=$(timeout 5 ${REDIS_PREFIX}/bin/redis-cli -h ${REDIS_SENTINEL_SERVICE_HOST} -p ${REDIS_SENTINEL_SERVICE_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
    if [[ -n ${master} ]]; then
      master="${master//\"}"
    else
      echo "Using $(hostname -i) as master"
      master=$(hostname -i)
    fi

    redis-cli -h ${master} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master ${master} failed.  Waiting..."
    sleep 10
  done

  sentinel_conf=${HOME}/sentinel.conf

  echo "sentinel monitor mymaster ${master} 6379 2" > ${sentinel_conf}
  echo "sentinel down-after-milliseconds mymaster ${REDIS_DOWN_AFTER_MILLIS:-30000}" >> ${sentinel_conf}
  echo "sentinel failover-timeout mymaster ${REDIS_FAILOVER_TIMEOUT:-180000}" >> ${sentinel_conf}
  echo "sentinel parallel-syncs mymaster 1" >> ${sentinel_conf}
  echo "bind 0.0.0.0" >> ${sentinel_conf}

  ${REDIS_PREFIX}/bin/redis-sentinel ${sentinel_conf} --protected-mode no
}

function launchslave() {
  echo "Using Redis Sentinel Host ${REDIS_SENTINEL_SERVICE_HOST}"
  
  while true; do
    master=$(timeout 5 ${REDIS_PREFIX}/bin/redis-cli -h ${REDIS_SENTINEL_SERVICE_HOST} -p ${REDIS_SENTINEL_SERVICE_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
    if [[ -n ${master} ]]; then
      master="${master//\"}"
    else
      echo "Failed to find master."
      sleep 60
      exit 1
    fi
    redis-cli -h ${master} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done
  mkdir -p ${REDIS_DATADIR}/${REDIS_POD_NAME:-noname}
  sed -i "s/%master-ip%/${master}/" ${HOME}/redis-slave/redis.conf
  sed -i "s/%master-port%/6379/" ${HOME}/redis-slave/redis.conf
  sed -i "s/%slave-data%/${REDIS_POD_NAME:-slave}/" ${HOME}/redis-slave/redis.conf
  ${REDIS_PREFIX}/bin/redis-server ${HOME}/redis-slave/redis.conf
}

if [[ "${MASTER:-false}" == "true" ]]; then
  launchmaster
  housekeeping
  exit 0
fi

if [[ "${SENTINEL:-false}" == "true" ]]; then
  launchsentinel
  exit 0
fi

launchslave
housekeeping
