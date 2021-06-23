#!/bin/bash

#docker run --rm -it --network active_publisher_default -e URI=amqp://guest:guest@rabbitmq:5672/%2f pivotalrabbitmq/perf-test:2.11.0-ubuntu --json-body --size 1000 -x 1 -y 0 -c 500
docker run --rm -it -v "$PWD":/usr/src/app -w /usr/src/app --network active_publisher_default jruby:9 bash -c 'apt update && apt install --no-install-recommends git -y; bundle install; exec bash'
