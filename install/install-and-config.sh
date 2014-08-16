#!/bin/bash -x

export DEBIAN_FRONTEND=noninteractive

### read the settings if they are given
settings=$1
if test -f $settings
then
    set -a
    source $settings
    set +a
    container=true   # this is installation of a docker container
fi

### update /etc/apt/sources.list
cat << EOF > /etc/apt/sources.list
deb $apt_mirror $suite main restricted universe multiverse
deb $apt_mirror $suite-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $suite-security main restricted universe multiverse
EOF

### upgrade and install other needed packages
apt-get update
apt-get -y upgrade
install='apt-get -y -o DPkg::Options::=--force-confdef -o DPkg::Options::=--force-confold install'
$install psmisc openssh-server netcat cron mini-httpd supervisor
initctl reload-configuration

### generates the file /etc/defaults/locale
$install language-pack-en
update-locale

### create a user 'vnc'
useradd --system --create-home vnc

### copy overlay files over to the system
dir=$(dirname $0)
cp -TdR $dir/overlay/ /

### if this is a docker container, then
### supervisor should not run as a daemon
if [ "$container" = 'true' ]
then
    sed -i /etc/supervisord.conf \
        -e '/^nodaemon/ c nodaemon=false/'
fi

### set correct permissions
chown vnc:vnc -R /home/vnc/
chmod 700 /home/vnc/.ssh

### customize the configuration of the chroot system
/home/vnc/regenerate_special_keys.sh
/home/vnc/change_sshd_port.sh $sshd_port

### customize the configuration of sshd
sed -i /etc/ssh/sshd_config \
    -e 's/^Port/#Port/' \
    -e 's/^PermitRootLogin/#PermitRootLogin/' \
    -e 's/^PasswordAuthentication/#PasswordAuthentication/' \
    -e 's/^X11Forwarding/#X11Forwarding/' \
    -e 's/^UseLogin/#UseLogin/' \
    -e 's/^AllowUsers/#AllowUsers/' \
    -e 's/^Banner/#Banner/'

sed -i /etc/ssh/sshd_config \
    -e '/^### p2p config/,$ d'

cat <<EOF >> /etc/ssh/sshd_config
### p2p config
Port $sshd_port
PermitRootLogin no
PasswordAuthentication no
X11Forwarding no
UseLogin no
AllowUsers vnc
Banner /etc/issue
EOF

### customize the configuration of mini-httpd
sed -i /etc/mini-httpd.conf \
    -e 's/^host/#host/' \
    -e 's/^port/#port/' \
    -e 's/^chroot/#chroot/' \
    -e 's/^nochroot/#nochroot/' \
    -e 's/^data_dir/#data_dir/' \

sed -i /etc/mini-httpd.conf \
    -e '/^### p2p config/,$ d'

cat <<EOF >> /etc/mini-httpd.conf
### p2p config
host=0.0.0.0
port=$httpd_port
chroot
data_dir=/home/vnc/www
EOF

sed -i /etc/default/mini-httpd \
    -e '/^START/ c START=1'

### customize the shell prompt
echo $target > /etc/debian_chroot
sed -i /root/.bashrc \
    -e '/^#force_color_prompt=/c force_color_prompt=yes' \
    -e '/^# get the git branch/,+4 d'
cat <<EOF >> /root/.bashrc
# get the git branch (used in the prompt below)
function parse_git_branch {
    git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}
EOF
PS1='\\n\\[\\033[01;32m\\]${debian_chroot:+($debian_chroot)}\\[\\033[00m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\e[32m\\]$(parse_git_branch)\\n==> \\$ \\[\\033[00m\\]'
sed -i /root/.bashrc \
    -e "/^if \[ \"\$color_prompt\" = yes \]/,+2 s/PS1=.*/PS1='$PS1'/"