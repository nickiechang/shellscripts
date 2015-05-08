#!/bin/bash

echo $1
ip netns list|grep "$1"| while read line ; do echo "$line";ip netns exec "$line" ip addr list; done