### 设置源 *Debian 13* *可选*
```
# 清华大学 Debian 13 镜像源
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie-backports main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security trixie-security main contrib non-free
```
### 设置源 *Debian 12* *可选*
```
# Debian 12 中科大
# 默认镜像源
deb https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware

# 安全更新
deb https://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware

# 软件更新（可选）
deb https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware

# Backports（可选）
# deb https://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
# deb-src https://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
```
---
### 设置源 *Debian 11* *可选*
```
# Debian 11 中科大
# 默认镜像源
deb https://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free
deb-src https://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free

# 安全更新
deb https://mirrors.ustc.edu.cn/debian-security/ bullseye-security main contrib non-free
deb-src https://mirrors.ustc.edu.cn/debian-security/ bullseye-security main contrib non-free

# 软件更新（可选）
deb https://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free
deb-src https://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free

# Backports（可选）
# deb https://mirrors.ustc.edu.cn/debian/ bullseye-backports main contrib non-free
# deb-src https://mirrors.ustc.edu.cn/debian/ bullseye-backports main contrib non-free
```
---
### 设置虚拟内存 *可选*
```
dd if=/dev/zero of=/root/swapfile bs=1M count=24576 && chmod 600 /root/swapfile && mkswap /root/swapfile && swapon /root/swapfile && sysctl vm.swappiness=100 && echo "/root/swapfile none swap sw 0 0" >> /etc/fstab && echo "vm.swappiness=100" >> /etc/sysctl.conf
```
---
### 设置每天凌晨三点自动重启 *可选*
```
chmod +x /root/restart_csgo.sh
crontab -e
0 3 * * * /root/restart_csgo.sh >> /root/restart_csgo.log 2>&1
```
---
### 安装依赖项
```
dpkg --add-architecture i386
apt-get update
apt-get install lib32gcc-s1 -y
apt install lib32stdc++6 -y
apt install screen -y
```
---
### 安装steamcmd
```
mkdir ~/steamcmd && cd ~/steamcmd
wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xvzf steamcmd_linux.tar.gz
```
---
### 运行steamcmd
```
./steamcmd.sh
```
---
### 安装csgo服务端
```
force_install_dir /root/csgo_ds
login anonymous
app_update 740
```
---
### 修复运行库问题
```
cp /usr/lib32/libgcc_s.so.1 /root/csgo_ds/bin
```
### 如果要使用MySQL
```
apt install zlib1g:i386 -y
ln -sf /lib/i386-linux-gnu/libz.so.1 /lib/libz.so.1
```
### 内核优化
```
apt install gnupg -y
wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/xanmod-archive-keyring.gpg
echo 'deb http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-release.list
apt update
apt install linux-xanmod-x64v3 -y
echo 'net.core.default_qdisc = cake' | sudo tee /etc/sysctl.d/90-override.conf
apt install tuned -y
tuned-adm profile latency-performance
reboot
```
### 查看硬件温度
```
watch -n 1 'for hw in /sys/class/hwmon/hwmon*; do 
    name=$(cat "$hw/name"); 
    for t in $hw/temp*_input; do 
        num=$(basename "$t" | sed "s/temp\([0-9]*\)_input/\1/"); 
        val=$(cat "$t"); 
        temp=$(echo "scale=1; $val/1000" | bc); 
        printf "%s temp%s: %s°C\n" "$name" "$num" "$temp"; 
    done; 
done'
```
### 将 *Debian 12* 升级到 *Debian13*
```
apt update
apt upgrade --without-new-pkgs -y
apt full-upgrade -y
apt autoremove --purge
apt autoclean
reboot
# 修改/etc/apt/sources.list为Debian 13源
apt update
apt full-upgrade -y
apt autoremove --purge
apt autoclean
reboot
```

### 封海外策略
```
# GSLT认证
# AS32590 - Valve Corporation - valvesoftware.com

# CDN下载
# AS20940 - Akamai International B.V. - akamai.com
# AS54113 - Fastly, Inc. - fastly.com

# Valve's IP
192.69.96.0/22
208.78.164.0/22
155.133.236.0/23
155.133.240.0/23
45.121.184.0/24
103.10.124.0/24
103.10.125.0/24
103.28.54.0/24
146.66.152.0/24
146.66.155.0/24
155.133.224.0/24
155.133.225.0/24
155.133.226.0/24
155.133.227.0/24
155.133.228.0/24
155.133.229.0/24
155.133.230.0/24
155.133.238.0/24
155.133.244.0/24
155.133.246.0/24
155.133.248.0/24
155.133.249.0/24
155.133.250.0/24
155.133.251.0/24
155.133.252.0/24
155.133.254.0/24
155.133.255.0/24
162.254.192.0/24
162.254.193.0/24
162.254.194.0/24
162.254.195.0/24
162.254.196.0/24
162.254.197.0/24
162.254.198.0/24
162.254.199.0/24
185.25.182.0/24
185.25.183.0/24
205.196.6.0/24
208.64.200.0/24
208.64.201.0/24
208.64.202.0/24
208.64.203.0/24
```
