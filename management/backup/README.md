# Backup and Recovery

When the current master goes down, redis sentinels start the failover to choose new master from the slaves.
There is not a way to switch back the process.
For persistent point of view the data that matters are those on the slave directory.

1. Connect to the redis sentinel and ask for the master

    ```shell
        oc debug dc/backend-redis
    
        redis-cli -h backend-redis-sentinel -p 26379 --csv SENTINEL get-master-addr-by-name mymaster
        "172.16.14.214","6379"
    ```

2. Connect to the master and launch the backup

    ```shell
       redis-cli -h 172.16.14.214 -p 6379 bgsave       
    ```
    
3. Check if it is successful

    ```shell
       date -d @$(redis-cli -h 172.16.14.214 -p 6379 lastsave | cut -d ' ' -f1)
       Wed Feb  7 10:21:04 UTC 2018
    ```

4. Get the pod master name

    ```shell
        export REDIS_MASTER=$(oc get pods -lapp=backend-redis -o custom-columns=NAME:.metadata.name,IP:.status.podIP --no-headers | grep 172.16.14.214  | cut -d ' ' -f1)
    ```
    
5. Backup your data

    ```shell
        oc rsync $REDIS_MASTER:/var/lib/redis/data/$REDIS_MASTER/appendonly.aof backup/
        oc rsync $REDIS_MASTER:/var/lib/redis/data/$REDIS_MASTER/dump.rdb backup/
    ```

6. Restore data during the bootstrap process.

    ```shell
       
       export REDIS_MASTER=$(oc get pods -lapp=backend-redis-master -o custom-columns=NAME:.metadata.name --no-headers)
       oc rsync backup/ $REDIS_MASTER:/var/lib/redis/data
    ```