#!/bin/bash -e

export HOSTIP="$(resolveip -s $HOSTNAME)"

supervisord &

# start druid services after mysql is ready, otherwise overlord may be stuck in a bad state
while ! mysqladmin status > /dev/null 2>&1; do
  echo "waiting for mysql to be ready ..."
  sleep 1
done

supervisorctl start "druid:*"

wait $!
