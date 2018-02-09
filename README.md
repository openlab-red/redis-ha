# Reliable, Scalable Redis on OpenShift

The following document describes the deployment of a reliable, multi-node Redis on OpenShift. 

It deploys a master with replicated slaves, as well as replicated redis sentinels which are use for health checking and failover.

## Build configuration

1. Create image stream and build config

    ```shell
        oc process -f build/redis-build.yml \
            -p REDIS_IMAGE_NAME=redis-ha \
            -p GIT_REPO=https://github.com/openlab-red/redis-ha.git \
            | oc create -f -
    ```
2. Start the build

    ```shell
        oc start-build redis-ha-build
    ```

## Deployment Configuration

### Persistent

Create a persistent storage, the storage must be **RWX**.

### Create a new persistent storage (RWX)

```yml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backend-redis-storage
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

### Turning up an initial master/sentinel pod

Create a bootstrap master and sentinels with relative service

```shell
    export REDIS_PREFIX=backend
    export REDIS_NAME=${REDIS_PREFIX}-redis
    
    oc process -f templates/redis-master.yml \
        -p REDIS_SERVICE_PREFIX=${REDIS_PREFIX} \
        -p REDIS_IMAGE=redis-ha:latest \
        -p REDIS_PV=${REDIS_NAME}-storage \
        | oc create -f -
```

### Turning up replicated redis slave servers

Create a deployment config for redis slave servers

```shell
    oc process -f templates/redis-slave.yml \
        -p REDIS_SERVICE_PREFIX=${REDIS_PREFIX} \
        -p REDIS_IMAGE=redis-ha:latest \
        -p REDIS_PV=${REDIS_NAME}-storage \
        | oc create -f -
```

Create a deployment config for redis sentinels


```shell
    oc process -f templates/redis-sentinel.yml \
        -p REDIS_SERVICE_PREFIX=${REDIS_PREFIX} \
        -p REDIS_IMAGE=redis-ha:latest \
        | oc create -f -
```

### Scale down the bootstrap master

Scale down the original master pod

```shell
    oc scale --replicas=0 dc ${REDIS_NAME}-master
```

### Failover

### Recommended setup

For a recommended setup that can resist more failures, set the replicas to 5 (default) for Redis and Sentinel.

>
> With 5 or 6 sentinels, a maximum of 2 can go down for a failover begin.
>
> With 7 sentinels, a maximum of 3 nodes can go down.
>

### Custom settings

|       Environment         |  Default Value   | Note                                                                                                      | 
| ------------------------- | ---------------- | --------------------------------------------------------------------------------------------------------- |
| REDIS_DOWN_AFTER_MILLIS   | 30000            | The time in milliseconds an instance should not be reachable for a Sentinel starting to think it is down  |    
| REDIS_FAILOVER_TIMEOUT    | 180000           | Specifies the failover timeout in milliseconds.                                                           |

For a fast failover under 1 minute

* REDIS_DOWN_AFTER_MILLIS=20000
* REDIS_FAILOVER_TIMEOUT=30000

## Migration from existing single Redis instance

[Migration from existing single redis instance](./management/migrate/README.md)

## Backup and Recovery

[Backup and Recovery](./management/backup/README.md)

## References

* https://redis.io/topics/sentinel
* https://github.com/kubernetes/examples/blob/master/staging/storage/redis/README.md
* https://github.com/sclorg/redis-container/blob/master/README.md
* https://github.com/mjudeikis/redis-openshift/blob/master/README.md
