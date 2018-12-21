## AnyKernel methods (DO NOT CHANGE)
# set up extracted files and directories
ramdisk=/tmp/anykernel/ramdisk;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;
patch=/tmp/anykernel/patch;

chmod -R 755 $bin;
mkdir -p $split_img;

FD=$1;
OUTFD=/proc/self/fd/$FD;

# ui_print <text>
ui_print() { echo -e "ui_print $1\nui_print" > $OUTFD; }

# contains <string> <substring>
contains() { test "${1#*$2}" != "$1" && return 0 || return 1; }

# file_getprop <file> <property>
file_getprop() { grep "^$2=" "$1" | cut -d= -f2; }

# reset anykernel directory
reset_ak() {
  local i;
  rm -rf $(dirname /tmp/anykernel/*-files/current)/ramdisk;
  for i in $ramdisk $split_img /tmp/anykernel/rdtmp /tmp/anykernel/boot.img /tmp/anykernel/*-new*; do
    cp -af $i $(dirname /tmp/anykernel/*-files/current);
  done;
  rm -rf $ramdisk $split_img $patch /tmp/anykernel/rdtmp /tmp/anykernel/boot.img /tmp/anykernel/*-new* /tmp/anykernel/*-files/current;
  . /tmp/anykernel/tools/ak2-core.sh $FD;
}

# dump boot and extract ramdisk
split_boot() {
  local nooktest nookoff dumpfail;
  if [ ! -e "$(echo $block | cut -d\  -f1)" ]; then
    ui_print " "; ui_print "Invalid partition. Aborting..."; exit 1;
  fi;
  if [ -f "$bin/nanddump" ]; then
    $bin/nanddump -f /tmp/anykernel/boot.img $block;
  else
    dd if=$block of=/tmp/anykernel/boot.img;
  fi;
  nooktest=$(strings /tmp/anykernel/boot.img | grep -E 'Red Loader|Green Loader|Green Recovery|eMMC boot.img|eMMC recovery.img|BauwksBoot');
  if [ "$nooktest" ]; then
    case $nooktest in
      *BauwksBoot*) nookoff=262144;;
      *) nookoff=1048576;;
    esac;
    mv -f /tmp/anykernel/boot.img /tmp/anykernel/boot-orig.img;
    dd bs=$nookoff count=1 conv=notrunc if=/tmp/anykernel/boot-orig.img of=$split_img/boot.img-master_boot.key;
    dd bs=$nookoff skip=1 conv=notrunc if=/tmp/anykernel/boot-orig.img of=/tmp/anykernel/boot.img;
  fi;
  if [ -f "$bin/unpackelf" -a "$($bin/unpackelf -i /tmp/anykernel/boot.img -h -q 2>/dev/null; echo $?)" == 0 ]; then
    if [ -f "$bin/elftool" ]; then
      mkdir $split_img/elftool_out;
      $bin/elftool unpack -i /tmp/anykernel/boot.img -o $split_img/elftool_out;
      cp -f $split_img/elftool_out/header $split_img/boot.img-header;
    fi;
    $bin/unpackelf -i /tmp/anykernel/boot.img -o $split_img;
    mv -f $split_img/boot.img-ramdisk.cpio.gz $split_img/boot.img-ramdisk.gz;
  elif [ -f "$bin/dumpimage" ]; then
    $bin/dumpimage -l /tmp/anykernel/boot.img;
    $bin/dumpimage -l /tmp/anykernel/boot.img > $split_img/boot.img-header;
    grep "Name:" $split_img/boot.img-header | cut -c15- > $split_img/boot.img-name;
    grep "Type:" $split_img/boot.img-header | cut -c15- | cut -d\  -f1 > $split_img/boot.img-arch;
    grep "Type:" $split_img/boot.img-header | cut -c15- | cut -d\  -f2 > $split_img/boot.img-os;
    grep "Type:" $split_img/boot.img-header | cut -c15- | cut -d\  -f3 | cut -d- -f1 > $split_img/boot.img-type;
    grep "Type:" $split_img/boot.img-header | cut -d\( -f2 | cut -d\) -f1 | cut -d\  -f1 | cut -d- -f1 > $split_img/boot.img-comp;
    grep "Address:" $split_img/boot.img-header | cut -c15- > $split_img/boot.img-addr;
    grep "Point:" $split_img/boot.img-header | cut -c15- > $split_img/boot.img-ep;
    $bin/dumpimage -i /tmp/anykernel/boot.img -p 0 $split_img/boot.img-zImage;
    test $? != 0 && dumpfail=1;
    if [ "$(cat $split_img/boot.img-type)" == "Multi" ]; then
      $bin/dumpimage -i /tmp/anykernel/boot.img -p 1 $split_img/boot.img-ramdisk.gz;
    fi;
    test $? != 0 && dumpfail=1;
  elif [ -f "$bin/rkcrc" ]; then
    dd bs=4096 skip=8 iflag=skip_bytes conv=notrunc if=/tmp/anykernel/boot.img of=$split_img/boot.img-ramdisk.gz;
  elif [ -f "$bin/pxa-unpackbootimg" ]; then
    $bin/pxa-unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  else
    $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  fi;
  if [ $? != 0 -o "$dumpfail" ]; then
    ui_print " "; ui_print "Dumping/splitting image failed. Aborting..."; exit 1;
  fi;
  if [ 
