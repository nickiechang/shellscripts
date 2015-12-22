#!/bin/bash

set -o xtrace
set -o errexit

cd /etc/init/; for i in $( ls "$1"-* ); do sudo service $i restart; done

set +o xtrace

