#!/usr/bin/env bash
#
# Install HAProxy 
# Script works on Ubuntu 12.04 and 14.04 only
 
 
set -e
set -u
set -o pipefail
 
# These settings are for Ubuntu 12.04 only, where we compile from source
export HAPROXY_VERSION=1.5.3 
export HAPROXY_CPU=generic
 
 
 
# Figure out which version of Ubuntu we have
export UBUNTU_VERSION=`cat /etc/issue | awk '{print $2}' | awk -F '.' '{print $1$2}'`
 
# on Ubuntu 14.04 LTS installs from backports
function install1404 {
  export DEBIAN_FRONTEND=noninteractive
  aptitude update 
  aptitude -y -q -t trusty-backports install haproxy 
  exit 0
}
 
# on Ubuntu 12.04 LTS installs from source
function install1204 {
 
  # Download the compilers and prerequisite -dev packages
  export DEBIAN_FRONTEND=noninteractive
  aptitude update 
  aptitude -q -y install build-essential libssl-dev libpcre3-dev zlib1g-dev virt-what
 
  # If we are running on bare metal and not in a virtual environment, the compile with 
  # CPU-native features.
  export IS_VIRTUALIZED=`virt-what` 
  if [ "${IS_VIRTUALIZED}" = "" ]; then
    export HAPROXY_CPU=native
  fi
 
  # Download the source code
  cd /usr/src
  curl http://www.haproxy.org/download/1.5/src/haproxy-${HAPROXY_VERSION}.tar.gz | tar zx
  cd haproxy-${HAPROXY_VERSION}
 
  # Compile and install
  make TARGET=linux2628 CPU=${HAPROXY_CPU} USE_PCRE=1 USE_OPENSSL=1 USE_ZLIB=1 
  make install PREFIX=/usr
 
  # Test for haproxy user and create it if needed. Chroot it and prevent it from 
  # getting shell access
  id -u haproxy &>/dev/null || useradd -d /var/lib/haproxy -s /bin/false haproxy
 
  # Set up the default haproxy config files
  mkdir -p /etc/haproxy/errors
  cp examples/errorfiles/* /etc/haproxy/errors
  cat > /etc/haproxy/haproxy.cfg <<EOF
global
  log /dev/log  local0
  log /dev/log  local1 notice
  chroot /var/lib/haproxy
  stats socket /run/haproxy/admin.sock mode 660 level admin
  stats timeout 30s
  user haproxy
  group haproxy
  daemon

  # Default SSL material locations
  ca-base /etc/ssl/certs
  crt-base /etc/ssl/private

  # Default ciphers to use on SSL-enabled listening sockets.
  # For more information, see ciphers(1SSL).
  ssl-default-bind-ciphers kEECDH+aRSA+AES:kRSA+AES:+AES256:RC4-SHA:!kEDH:!LOW:!EXP:!MD5:!aNULL:!eNULL

defaults
  log global
  mode  http
  option  httplog
  option  dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
  errorfile 400 /etc/haproxy/errors/400.http
  errorfile 403 /etc/haproxy/errors/403.http
  errorfile 408 /etc/haproxy/errors/408.http
  errorfile 500 /etc/haproxy/errors/500.http
  errorfile 502 /etc/haproxy/errors/502.http
  errorfile 503 /etc/haproxy/errors/503.http
  errorfile 504 /etc/haproxy/errors/504.http
EOF
 
  # Add the /etc/default script
  cat > /etc/default/haproxy <<EOF
# Defaults file for HAProxy
#
# This is sourced by both, the initscript and the systemd unit file, so do not
# treat it as a shell script fragment.

ENABLED=1

# Change the config file location if needed
#CONFIG="/etc/haproxy/haproxy.cfg"

# Add extra flags here, see haproxy(1) for a few options
#EXTRAOPTS="-de -m 16"
EOF
 
 
  # Add the default init.d script
  cat > /etc/init.d/haproxy <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          haproxy
# Required-Start:    \$local_fs \$network \$remote_fs \$syslog
# Required-Stop:     \$local_fs \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: fast and reliable load balancing reverse proxy
# Description:       This file should be used to start and stop haproxy.
### END INIT INFO

# Author: Arnaud Cornet <acornet@debian.org>

PATH=/sbin:/usr/sbin:/bin:/usr/bin
PIDFILE=/var/run/haproxy.pid
CONFIG=/etc/haproxy/haproxy.cfg
HAPROXY=/usr/sbin/haproxy
RUNDIR=/run/haproxy
EXTRAOPTS=

test -x \$HAPROXY || exit 0

if [ -e /etc/default/haproxy ]; then
	. /etc/default/haproxy
fi

test -f "\$CONFIG" || exit 0

[ -f /etc/default/rcS ] && . /etc/default/rcS
. /lib/lsb/init-functions


check_haproxy_config()
{
	\$HAPROXY -c -f "\$CONFIG" >/dev/null
	if [ \$? -eq 1 ]; then
		log_end_msg 1
		exit 1
	fi
}

haproxy_start()
{
	[ -d "\$RUNDIR" ] || mkdir "\$RUNDIR"
	chown haproxy:haproxy "\$RUNDIR"
	chmod 2775 "\$RUNDIR"

	check_haproxy_config

	start-stop-daemon --quiet --oknodo --start --pidfile "\$PIDFILE" \\
		--exec \$HAPROXY -- -f "\$CONFIG" -D -p "\$PIDFILE" \\
		\$EXTRAOPTS || return 2
	return 0
}

haproxy_stop()
{
	if [ ! -f \$PIDFILE ] ; then
		# This is a success according to LSB
		return 0
	fi
	for pid in \$(cat \$PIDFILE) ; do
		/bin/kill \$pid || return 4
	done
	rm -f \$PIDFILE
	return 0
}

haproxy_reload()
{
	check_haproxy_config

	\$HAPROXY -f "\$CONFIG" -p \$PIDFILE -D \$EXTRAOPTS -sf \$(cat \$PIDFILE) \\
		|| return 2
	return 0
}

haproxy_status()
{
	if [ ! -f \$PIDFILE ] ; then
		# program not running
		return 3
	fi

	for pid in \$(cat \$PIDFILE) ; do
		if ! ps --no-headers p "\$pid" | grep haproxy > /dev/null ; then
			# program running, bogus pidfile
			return 1
		fi
	done

	return 0
}


case "\$1" in
start)
	log_daemon_msg "Starting haproxy" "haproxy"
	haproxy_start
	ret=\$?
	case "\$ret" in
	0)
		log_end_msg 0
		;;
	1)
		log_end_msg 1
		echo "pid file '\$PIDFILE' found, haproxy not started."
		;;
	2)
		log_end_msg 1
		;;
	esac
	exit \$ret
	;;
stop)
	log_daemon_msg "Stopping haproxy" "haproxy"
	haproxy_stop
	ret=\$?
	case "\$ret" in
	0|1)
		log_end_msg 0
		;;
	2)
		log_end_msg 1
		;;
	esac
	exit \$ret
	;;
reload|force-reload)
	log_daemon_msg "Reloading haproxy" "haproxy"
	haproxy_reload
	ret=\$?
	case "\$ret" in
	0|1)
		log_end_msg 0
		;;
	2)
		log_end_msg 1
		;;
	esac
	exit \$ret
	;;
restart)
	log_daemon_msg "Restarting haproxy" "haproxy"
	haproxy_stop
	haproxy_start
	ret=\$?
	case "\$ret" in
	0)
		log_end_msg 0
		;;
	1)
		log_end_msg 1
		;;
	2)
		log_end_msg 1
		;;
	esac
	exit \$ret
	;;
status)
	haproxy_status
	ret=\$?
	case "\$ret" in
	0)
		echo "haproxy is running."
		;;
	1)
		echo "haproxy dead, but \$PIDFILE exists."
		;;
	*)
		echo "haproxy not running."
		;;
	esac
	exit \$ret
	;;
*)
	echo "Usage: /etc/init.d/haproxy {start|stop|reload|restart|status}"
	exit 2
	;;
esac

:
EOF
  chmod +x /etc/init.d/haproxy
 
  # Make a chroot for haproxy, add syslog config to make log socket in said chroot
  mkdir -p /var/lib/haproxy/dev
 
  cat > /etc/rsyslog.d/haproxy.conf <<EOF
# Create an additional socket in haproxy's chroot in order to allow logging via
# /dev/log to chroot'ed HAProxy processes
\$AddUnixListenSocket /var/lib/haproxy/dev/log

# Send HAProxy messages to a dedicated logfile
if \$programname startswith 'haproxy' then /var/log/haproxy.log
&~
EOF
 
  # And rotate the logs so it doesn't overfill
  cat > /etc/logrotate.d/haproxy <<EOF
/var/log/haproxy.log {
    daily
    rotate 52
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        invoke-rc.d rsyslog rotate >/dev/null 2>&1 || true
    endscript
}
EOF
 
  # Start on reboot
  update-rc.d haproxy defaults
  service haproxy start
 
  # Clean up source 
  cd ~
  rm -rf /usr/src/haproxy-${HAPROXY_VERSION}
 
  exit 0
}
 
 
 
# Actually execute the installations
if [ "${UBUNTU_VERSION}" = "1404" ]; then
  install1404
fi
 
if [ "${UBUNTU_VERSION}" = "1204" ]; then
  install1204
fi
 
echo This script supports Ubuntu 12.04 or 14.04 only.
exit 1