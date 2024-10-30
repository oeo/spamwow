#!/bin/bash

# check if config file is provided
if [ "$#" -lt 1 ]; then
    echo "usage: $0 <path_to_config_file> [port]"
    exit 1
fi

CONFIG_PATH=$1
PORT=${2:-8080}

# get the absolute path of the config file
ABSOLUTE_CONFIG_PATH=$(realpath "$CONFIG_PATH")

# build the docker image
docker build -t proxy-script .

# run the docker container
docker run -it --rm \
    -p $PORT:$PORT \
    -v "$ABSOLUTE_CONFIG_PATH:/app/config.yaml" \
    proxy-script -c /app/config.yaml -p $PORT

