#!/bin/bash

temp_dir="/tmp/tclxebY2XrKE6CGcH"
current_dir=$(pwd)
CorePure64_url="http://tinycorelinux.net/15.x/x86_64/release/CorePure64-15.0.iso"
CorePure64_name="CorePure64-15.0.iso"
tcz_version="15.x"
kernel_version="6.6.8-tinycore64"

trap _exit INT QUIT TERM

_red() {
    printf '\033[0;31;31m%b\033[0m' "$1"
}

_green() {
    printf '\033[0;31;32m%b\033[0m' "$1"
}

_blue() {
    printf '\033[0;31;36m%b\033[0m' "$1"
}

_exists() {
    local cmd="$1"
    if eval type type >/dev/null 2>&1; then
        eval type "$cmd" >/dev/null 2>&1
    elif command >/dev/null 2>&1; then
        command -v "$cmd" >/dev/null 2>&1
    else
        which "$cmd" >/dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

_error() {
    _red "[Error]: $1\n"
    rm -fr $temp_dir
    exit 1
}

_exit() {
    _red "Terminated by user\n"
    rm -fr $temp_dir
    exit 1
}

check_tools() {
    for i in "$@"; do
        case "$i" in
        advdef)
            k="advancecomp"
            ;;
        unsquashfs)
            k="squashfs-tools"
            ;;
        *)
            k="$i"
            ;;
        esac

        if _exists "$i"; then
            _green "$k command is found\n"
        else
            _error "$k command not found.\n"
        fi
    done
}

create_dir() {
    mkdir -p "$temp_dir/mnt"
    mkdir -p "$temp_dir/down"
    mkdir -p "$temp_dir/ext"
    mkdir -p "$temp_dir/new/boot"
}
download_files() {
    pushd $temp_dir/down || _error "pushd $temp_dir/down\n"

    wget -q "$CorePure64_url" -O $CorePure64_name
    wget -q "$CorePure64_url.md5.txt" -O CorePure64.iso.md5.txt
    md5sum -c CorePure64.iso.md5.txt || _error "[Error]: md5 check error \n"
    popd || _error "popd $temp_dir/down\n"
    ls $temp_dir/down
    _green "files download succeeded\n"
}

install_package() {
    local pacakge_name="$1"
    [ -z "$pacakge_name" ] && return
    pushd $temp_dir/down || _error "pushd $temp_dir/down\n"
    wget -q "http://tinycorelinux.net/${tcz_version}/x86_64/tcz/${pacakge_name}.tcz" -O "$pacakge_name".tcz
    wget -q "http://tinycorelinux.net/${tcz_version}/x86_64/tcz/${pacakge_name}.tcz.md5.txt" -O "$pacakge_name".tcz.md5.txt
    md5sum -c "$pacakge_name".tcz.md5.txt || _error "md5 check error for $pacakge_name\n"
    popd || _error "popd $temp_dir/down\n"
    _green "package $pacakge_name download succeeded\n"
    pushd $temp_dir/ext || _error "pushd $temp_dir/ext\n"
    unsquashfs -f -d . $temp_dir/down/"$pacakge_name".tcz
    popd || _error "popd $temp_dir/ext\n"
    _green "package $pacakge_name install succeeded\n"
}

extract_file() {
    7z x $temp_dir/down/$CorePure64_name -o$temp_dir/mnt
    cp -ar $temp_dir/mnt/boot/corepure64.gz $temp_dir/mnt/boot/vmlinuz64 $temp_dir/mnt/boot/isolinux $temp_dir
    pushd $temp_dir/ext || _error "pushd $temp_dir/ext\n"
    zcat $temp_dir/corepure64.gz | cpio -i -H newc -d
    popd || _error "popd $temp_dir/ext\n"

    # Base packages for SSH and rsync
    install_package "openssh"
    install_package "openssl"
    install_package "ipv6-netfilter-${kernel_version}"
    install_package "rsync"
    install_package "attr"
    install_package "acl"
    install_package "liblz4"
    install_package "xxhash"
    install_package "libzstd"
    install_package "pv"
    install_package "glibc_gconv"
    install_package "util-linux"
    install_package "tar"
    install_package "xz"
    install_package "ca-certificates"
    install_package "wget"

    # Install extra packages from environment variable
    if [ -n "$EXTRA_PACKAGES" ]; then
        echo "$EXTRA_PACKAGES" | tr ',' '\n' | while read pkg; do
            [ -n "$pkg" ] && install_package "$pkg"
        done
    fi

    pushd $temp_dir/ext || _error "pushd $temp_dir/ext\n"
    cp -a usr/local/etc/ssh/sshd_config.orig usr/local/etc/ssh/sshd_config

    # prepare for chroot
    mount -t proc /proc proc/
    mount -t sysfs /sys sys/
    mount --bind /dev dev/
    mount --bind /run run/
    echo "nameserver 8.8.4.4" > etc/resolv.conf
    chroot . /bin/sh <<EOF
export PS1="(chroot) \$PS1"
echo "tc:${PASSWORD:-toor}" | chpasswd
/sbin/ldconfig
for i in \`ls -1 /usr/local/tce.installed\`; do [ -f /usr/local/tce.installed/\$i ] && sh /usr/local/tce.installed/\$i ; done
/sbin/ldconfig
exit
EOF
    umount -f proc sys dev run
    cp -f "$current_dir"/bootlocal.sh opt/bootlocal.sh
    chmod +x opt/bootlocal.sh
    find . | cpio -o -H newc | gzip -9 >$temp_dir/my_core.gz
    popd || _error "popd $temp_dir/ext\n"
    advdef -z4 $temp_dir/my_core.gz
    # change isolinux/isolinux.cfg  timeout 10
    sed -i 's/timeout 300/timeout 10/g' $temp_dir/isolinux/isolinux.cfg
    # append boot parameters
    BOOT_PARAMS=""
    [ -n "$PASSWORD" ] && BOOT_PARAMS="$BOOT_PARAMS password=$PASSWORD"
    [ -n "$IP" ] && BOOT_PARAMS="$BOOT_PARAMS ip=$IP"
    [ -n "$NETMASK" ] && BOOT_PARAMS="$BOOT_PARAMS netmask=$NETMASK"
    [ -n "$GATEWAY" ] && BOOT_PARAMS="$BOOT_PARAMS gateway=$GATEWAY"
    [ -n "$NAMESERVER" ] && BOOT_PARAMS="$BOOT_PARAMS nameserver=$NAMESERVER"
    [ -n "$SSH_PORT" ] && BOOT_PARAMS="$BOOT_PARAMS ssh_port=$SSH_PORT"

    if [ -n "$BOOT_PARAMS" ]; then
        sed -i "/append loglevel=3/ s/$/$BOOT_PARAMS/" $temp_dir/isolinux/isolinux.cfg
    fi
    ls $temp_dir
}

create_iso() {
    cp -a $temp_dir/my_core.gz $temp_dir/new/boot/corepure64.gz
    cp -a $temp_dir/vmlinuz64 $temp_dir/new/boot/vmlinuz64
    cp -a $temp_dir/isolinux $temp_dir/new/boot/isolinux
    xorriso -as mkisofs -l -J -R -V TC-custom -no-emul-boot -boot-load-size 4 \
        -boot-info-table -b /boot/isolinux/isolinux.bin \
        -c /boot/isolinux/boot.cat -o /tmp/tcl.iso $temp_dir/new
}

# check root account
[[ $EUID -ne 0 ]] && _error "This script must be run as root\n"
check_tools cpio tar gzip advdef xorriso wget unsquashfs 7z
create_dir
download_files
extract_file
create_iso
rm -fr $temp_dir
_blue "done iso_file: /tmp/tcl.iso\n"
exit 0
