#!/bin/bash

set -e

cp /data/os/ubuntu-24.04-server-cloudimg-amd64.img ubuntu-cloudimg.img

for deb in linux-guest/linux-*.deb; do
	guestfish --rw -a ubuntu-cloudimg.img -i <<-EOF
		copy-in $deb /root/
		command "dpkg -i /root/$(basename $deb)"
		command "rm /root/$(basename $deb)"
	EOF
done
