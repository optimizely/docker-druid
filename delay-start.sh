#!/bin/sh -e

sleep $1
shift
exec "$@"
