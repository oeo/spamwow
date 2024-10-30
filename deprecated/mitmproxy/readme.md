# custom proxy script

this project provides a customizable proxy script that can modify web content on-the-fly. it's designed to work both standalone and behind a reverse proxy.

## files

- `proxy_script.py`: the main python script that handles the proxying and content modification
- `config.example.yml`: an example configuration file
- `dockerfile`: for building a docker image of the proxy
- `requirements.txt`: python dependencies
- `run_proxy.sh`: a bash script to easily run the proxy in a docker container

## usage

1. copy `config.example.yml` to `config.yml` and modify it according to your needs
2. run the proxy:

```
./run_proxy.sh config.yml [port]
```

if no port is specified, it will default to 8080

3. configure your browser or system to use the proxy (usually `localhost:8080` or whatever port you specified)

## reverse proxy setup

if you're using a reverse proxy:

1. ensure your reverse proxy sets the `X-Forwarded-Host` and `X-Forwarded-Proto` headers
2. set the `NEW_HOST` in your config file to match the host that clients will use to access your reverse proxy

