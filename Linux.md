/### 设置源 *Debian 12* *可选*
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
sudo apt install gnupg
wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/xanmod-archive-keyring.gpg
echo 'deb http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-release.list
apt update
apt install linux-xanmod-x64v3
# apt install intel-microcode iucode-tool
# apt install amd64-microcode
echo 'net.core.default_qdisc = cake' | sudo tee /etc/sysctl.d/90-override.conf
apt install tuned
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
