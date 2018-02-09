FROM rhscl/redis-32-rhel7:latest

COPY redis-master.conf ${HOME}/redis-master/redis.conf
COPY redis-slave.conf ${HOME}/redis-slave/redis.conf
COPY run.sh ${REDIS_PREFIX}/bin/run.sh

USER root

RUN yum install hostname -y

RUN chown -R redis.0 ${HOME}/redis-master && \
	chown -R redis.0 ${HOME}/redis-slave && \
	chmod -R 777 ${HOME}/redis-*

USER 1001

CMD [ "run.sh" ]