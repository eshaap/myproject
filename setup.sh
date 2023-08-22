#!/bin/bash

now=$(date +%d%b%Y-%H%M)
USER="devops"
GROUP="devops"

exp() {
  "${1}" < <(cat <<-EOF
    spawn passwd $USER
    expect "Enter new UNIX password:"
    send -- "$passw\r"
    expect "Retype new UNIX password:"
    send -- "$passw\r"
    expect eof
    EOF
  )
  echo "Password for USER $USER updated successfully - adding to sudoers file now"
}

setup_pass() {
  if ! command -v expect &>/dev/null; then
    case "$1" in
      sles | amzn)
        zypper install -y expect
        ;;
      ubuntu)
        apt-get update
        apt-get install -y expect
        ;;
      centos)
        yum install -y expect
        ;;
      *)
        echo "Unsupported distribution: $1"
        exit 1
        ;;
    esac
  fi

  exp "expect"
}

update_conf() {
  sudofile="/etc/sudoers"
  sshdfile="/etc/ssh/sshd_config"
  backup_dir="/home/backup"

  mkdir -p "$backup_dir"

  if [ -f "$sudofile" ]; then
    cp -p "$sudofile" "$backup_dir/sudoers-$now"
    if ! grep -q "$USER" "$sudofile"; then
      echo "$USER ALL=(ALL) NOPASSWD: ALL" >> "$sudofile"
      echo "Updated the sudoers file successfully"
    else
      echo "$USER user already present in $sudofile - no changes required"
    fi
  else
    echo "Could not find $sudofile"
  fi

  if [ -f "$sshdfile" ]; then
    cp -p "$sshdfile" "$backup_dir/sshd_config-$now"
    sed -i '/ClientAliveInterval.*0/d' "$sshdfile"
    echo "ClientAliveInterval 240" >> "$sshdfile"
    sed -i '/PasswordAuthentication.*no/d' "$sshdfile"
    sed -i '/PasswordAuthentication.*yes/d' "$sshdfile"
    echo "PasswordAuthentication yes" >> "$sshdfile"
    systemctl restart sshd
    echo "Updated $sshdfile successfully -- restarted sshd service"
  else
    echo "Could not find $sshdfile"
  fi
}

############### MAIN ###################

passw="today@1234"

if id -u "$USER" &>/dev/null; then
  echo "devops user exists, no action required..."
  exit 0
else
  echo "devops user missing, continuing to create it..."
fi

if [ -f "/etc/os-release" ]; then
  osname=$(grep ID /etc/os-release | grep -E -v 'VERSION|LIKE|VARIANT|PLATFORM' | cut -d'=' -f2 | tr -d '"')
  echo "$osname"
else
  echo "Cannot locate /etc/os-release - unable to determine the OS name"
  exit 8
fi

case "$osname" in
  sles | amzn | ubuntu | centos)
    userdel -r "$USER" 
    groupdel "$GROUP"
    sleep 3
    groupadd "$GROUP"
    useradd "$USER" -m -d "/home/$USER" -s "/bin/bash" -g "$GROUP"
    setup_pass "$osname"
    update_conf
    ;;
  *)
    echo "Could not determine the correct OS name -- found: $osname"
    exit 1
    ;;
esac

exit 0
