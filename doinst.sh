config() {
  NEW="$1"
  OLD="$(dirname $NEW)/$(basename $NEW .new)"
  if [ ! -r $OLD ]; then
    mv $NEW $OLD
  elif [ "$(cat $OLD | md5sum)" = "$(cat $NEW | md5sum)" ]; then
    rm $NEW
  fi
}

config etc/ld.so.conf.d/rocm.conf.new
config etc/profile.d/rocm.sh.new

# Only meaningful once rocm.conf has landed under its real name:
if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig 2>/dev/null
fi
