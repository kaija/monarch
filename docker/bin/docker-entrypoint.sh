#!/bin/sh
set -e

environment=${ENV:-}

if [ -d /docker-entrypoint.d/ ]; then
    find /docker-entrypoint.d/ -type f -name "*.sh" \
        -exec chmod +x {} \;
    sync
    find /docker-entrypoint.d/ -type f -name "*.sh" \
        -exec echo Running {} \; -exec {} \;
fi

if [ "$environment" = "production" ];
then
    exec 
else
    exec gunicorn recognition_api.agent:app -w 2 -k uvicorn.workers.UvicornWorker --timeout 30 -b 0.0.0.0:8000 --limit-request-line 0 --limit-request-field_size 0 --log-level debug
fi
