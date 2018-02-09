# Sample Migration from existing single Redis instance

## Manual steps

>
> Shutdown all dependencies before proceed
>

###  Scale down existing redis instance and delete the dc

```shell
    export REDIS_PREFIX=backend
    export REDIS_NAME=${REDIS_PREFIX}-redis
    
    oc scale --replicas=0 dc ${REDIS_NAME}
    oc delete dc,svc ${REDIS_NAME}
```

### Create the bootstrap master and sentinel using ephemeral template

```shell
    oc process -f templates/redis-master-ephemeral.yml \
        -p REDIS_SERVICE_PREFIX=${REDIS_PREFIX} \
        -p REDIS_IMAGE=redis-ha:latest \
        | oc create -f -
```

### Attach existing storage

```shell
    oc volume dc/${REDIS_NAME}-master --add --name=data --type=pvc --claim-name=${REDIS_NAME}-storage -m /var/lib/redis/data --overwrite
```

### Create a new persistent storage (RWX)

```yml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backend-redis-rwx-storage
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
```
```shell
    oc create -f /tmp/storage.yml
```

Mount under the slave data path **/var/lib/redis/redis-slave/data**

>
> The slave mounting point is necessary for backup and restore
>

```shell
    oc volume dc/${REDIS_NAME}-master --add --name=slave-data --type=pvc --claim-name=${REDIS_NAME}-rwx-storage -m /var/lib/redis/redis-slave/data --overwrite
```

### Create the slave redis

Wait the master pod to start up before proceed

```shell
    oc process -f templates/redis-slave.yml \
        -p REDIS_SERVICE_PREFIX=${REDIS_PREFIX} \
        -p REDIS_IMAGE=redis-ha:latest \
        -p REDIS_PV=${REDIS_NAME}-rwx-storage \
        | oc create -f -
```

### Create the sentinel redis

```shell
    oc process -f templates/redis-sentinel.yml \
        -p REDIS_SERVICE_PREFIX=${REDIS_PREFIX} \
        -p REDIS_IMAGE=redis-ha:latest \
        | oc create -f -
```

### Scale down the bootstrap master

```shell
    oc scale --replicas=0 dc ${REDIS_NAME}-master
```

Override the master data storage with the new RWX storage

```shell
   oc volume dc/${REDIS_NAME}-master --remove --name=data
   oc volume dc/${REDIS_NAME}-master --remove --name=slave-data
   oc volume dc/${REDIS_NAME}-master --add --name=data --type=pvc --claim-name=${REDIS_NAME}-rwx-storage -m /var/lib/redis/data --overwrite
   oc patch dc/${REDIS_NAME}-master -p '{"spec": {"template": {"spec": {"containers": [{"name": "backend-redis", "volumeMounts": [{"mountPath": "/var/lib/redis/data","name": "data"},{"mountPath": "/var/lib/redis/redis-slave/data","name": "data"}]}]}}}}'
```

### Delete the old storage

```shell
    oc delete pvc ${REDIS_NAME}-storage
```

## Ansible Playbook

TBD
