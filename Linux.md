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
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
sudo sysctl vm.swappiness=100
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
