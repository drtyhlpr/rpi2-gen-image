#
# Setup logging
#

. ./functions.sh

# Disable rsyslog
if [ "$ENABLE_RSYSLOG" = false ]; then
  sed -i 's|[#]*ForwardToSyslog=yes|ForwardToSyslog=no|g' $R/etc/systemd/journald.conf
  chroot_exec systemctl disable rsyslog
  chroot_exec apt-get purge -q -y --force-yes rsyslog
fi
