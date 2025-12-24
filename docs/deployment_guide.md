# 树莓派5 AI助手完整部署指南

## 目录
1. [系统准备](#系统准备)
2. [系统安装](#系统安装)
3. [环境配置](#环境配置)
4. [依赖安装](#依赖安装)
5. [模型部署](#模型部署)
6. [编译程序](#编译程序)
7. [系统服务配置](#系统服务配置)
8. [测试验证](#测试验证)
9. [故障排查](#故障排查)

---

## 系统准备

### 1. 烧录系统镜像

#### 下载系统
- 推荐: **Raspberry Pi OS (64-bit) Lite**
- 下载地址: https://www.raspberrypi.com/software/operating-systems/
- 选择 "Raspberry Pi OS Lite (64-bit)" - 无桌面环境，节省资源

#### 使用 Raspberry Pi Imager 烧录
```bash
# 1. 下载并安装 Raspberry Pi Imager
# Windows/Mac: https://www.raspberrypi.com/software/
# Linux:
sudo apt install rpi-imager

# 2. 打开 Imager
#    - 选择 OS: Raspberry Pi OS (64-bit) Lite
#    - 选择存储卡: 你的 microSD 卡
#    - 点击设置（齿轮图标）:
#      ✓ 启用 SSH
#      ✓ 设置用户名和密码 (例如: pi / raspberry)
#      ✓ 配置WiFi (可选)
#      ✓ 设置主机名: raspberrypi5

# 3. 写入并等待完成
```

### 2. 首次启动

```bash
# 插入SD卡，连接电源
# 等待约2分钟让系统首次启动

# 通过SSH连接（如果配置了WiFi）
ssh pi@raspberrypi5.local

# 或通过路由器找到IP地址
ssh pi@192.168.1.xxx

# 首次登录后更新系统
sudo apt update && sudo apt upgrade -y
```

---

## 系统安装

### 1. 基础系统配置

```bash
# 配置系统
sudo raspi-config

# 推荐配置项:
# - System Options → Boot / Auto Login → Console Autologin
# - Performance Options → GPU Memory → 设为 16MB (节省内存)
# - Localisation Options → 设置时区和语言
# - Interface Options → 启用 SSH (如果没开启)

# 重启系统
sudo reboot
```

### 2. 安装NVMe SSD支持（如果使用）

```bash
# 更新固件
sudo rpi-eeprom-update
sudo rpi-eeprom-update -a  # 如果有更新

# 检测NVMe SSD
lsblk  # 应该看到 nvme0n1

# 格式化并挂载
sudo mkfs.ext4 /dev/nvme0n1
sudo mkdir /mnt/ssd
sudo mount /dev/nvme0n1 /mnt/ssd

# 自动挂载
echo '/dev/nvme0n1 /mnt/ssd ext4 defaults 0 2' | sudo tee -a /etc/fstab

# 测试速度
sudo hdparm -t /dev/nvme0n1
# 应该看到 200MB/s 以上
```

### 3. 创建工作目录

```bash
# 如果使用SSD
sudo mkdir -p /mnt/ssd/ai-assistant
sudo chown pi:pi /mnt/ssd/ai-assistant
cd /mnt/ssd/ai-assistant

# 如果使用SD卡
mkdir -p ~/ai-assistant
cd ~/ai-assistant

# 创建子目录
mkdir -p models src build logs
```

---

## 环境配置

### 1. 安装编译工具

```bash
# 基础编译工具
sudo apt install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    pkg-config

# C++编译器升级（需要C++17支持）
sudo apt install -y gcc-11 g++-11
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100
```

### 2. 安装Python环境（用于辅助脚本）

```bash
# Python 3.11
sudo apt install -y python3 python3-pip python3-venv

# 创建虚拟环境
python3 -m venv ~/venv
source ~/venv/bin/activate

# 安装工具
pip install huggingface-hub requests tqdm
```

### 3. 配置交换空间（重要！）

```bash
# 树莓派5需要足够的交换空间
# 创建8GB交换文件
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 永久启用
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 验证
free -h
# 应该看到 8GB 交换空间
```

---

## 依赖安装

### 1. 安装音频库

```bash
# PortAudio (音频输入输出)
sudo apt install -y portaudio19-dev

# ALSA工具
sudo apt install -y alsa-utils libasound2-dev

# 测试音频
arecord -l  # 列出麦克风
aplay -l    # 列出扬声器

# 录制测试
arecord -d 3 -f cd test.wav
aplay test.wav
```

### 2. 编译 llama.cpp

```bash
cd ~/ai-assistant/src

# 克隆仓库
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

# 编译（针对树莓派5优化）
mkdir build && cd build
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_NATIVE=ON \
    -DLLAMA_LTO=ON

make -j4  # 使用4个核心编译

# 测试
./bin/main --version
# 应该显示版本信息

cd ~/ai-assistant
```

### 3. 编译 whisper.cpp

```bash
cd ~/ai-assistant/src

# 克隆仓库
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# 编译
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

# 下载模型
cd ../models
bash download-ggml-model.sh small.en  # 或 small (多语言)

# 测试
cd ..
./bin/main -m models/ggml-small.en.bin -f samples/jfk.wav

cd ~/ai-assistant
```

### 4. 安装 Piper TTS

```bash
cd ~/ai-assistant/src

# 下载预编译的Piper（ARM64版本）
wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_arm64.tar.gz
tar -xvzf piper_arm64.tar.gz
mv piper ~/ai-assistant/bin/

# 下载TTS模型
cd ~/ai-assistant/models
wget https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/medium/en_US-amy-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/medium/en_US-amy-medium.onnx.json

# 测试
echo "Hello, this is a test." | ~/ai-assistant/bin/piper \
    --model models/en_US-amy-medium.onnx \
    --output_file test.wav
aplay test.wav
```

---

## 模型部署

### 1. 下载微调后的模型

```bash
cd ~/ai-assistant/models

# 方法1: 从训练机器传输
# 在训练机器上:
# scp qwen3-0.6b-fineweb-edu/gguf/qwen3-0.6b-q8_0.gguf pi@raspberrypi5:/home/pi/ai-assistant/models/

# 方法2: 从Hugging Face下载（如果已上传）
source ~/venv/bin/activate
pip install huggingface-hub

python3 << EOF
from huggingface_hub import hf_hub_download
model_file = hf_hub_download(
    repo_id="your-username/qwen3-0.6b-fineweb",
    filename="qwen3-0.6b-q8_0.gguf",
    local_dir="."
)
print(f"模型已下载: {model_file}")
EOF

# 方法3: 使用原版Qwen3-0.6B测试
wget https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/qwen3-0.6b-q8_0.gguf
```

### 2. 验证模型

```bash
cd ~/ai-assistant

# 测试LLM
./src/llama.cpp/build/bin/main \
    -m models/qwen3-0.6b-q8_0.gguf \
    -n 128 \
    -p "Q: What is machine learning?\nA:"

# 如果运行正常，会看到模型生成的文本
```

### 3. 模型文件清单

```bash
# 检查所有模型文件
ls -lh ~/ai-assistant/models/

# 应该看到:
# - qwen3-0.6b-q8_0.gguf          (~700MB - LLM)
# - ggml-small.en.bin             (~466MB - Whisper)
# - en_US-amy-medium.onnx         (~63MB - Piper TTS)
# - en_US-amy-medium.onnx.json    (~几KB - TTS配置)
```

---

## 编译程序

### 1. 编译推理引擎

```bash
cd ~/ai-assistant

# 复制之前的C++代码
# 将 qwen_inference.cpp 保存到 src/ 目录

# 编译
g++ -O3 -std=c++17 -march=native -mtune=native \
    src/qwen_inference.cpp -o bin/qwen_inference \
    -I./src/llama.cpp \
    -L./src/llama.cpp/build \
    -lllama -pthread

# 测试
./bin/qwen_inference \
    --model models/qwen3-0.6b-q8_0.gguf \
    --threads 4

# 输入测试: "你好"
# 应该看到模型回复
```

### 2. 编译语音助手

```bash
# 将 voice_assistant.cpp 保存到 src/ 目录

# 编译（需要链接所有库）
g++ -O3 -std=c++17 -march=native \
    src/voice_assistant.cpp -o bin/voice_assistant \
    -I./src/whisper.cpp \
    -L./src/whisper.cpp/build \
    -lwhisper \
    -I./src/llama.cpp \
    -L./src/llama.cpp/build \
    -lllama \
    -lportaudio -pthread

# 设置库路径
export LD_LIBRARY_PATH=~/ai-assistant/src/llama.cpp/build:~/ai-assistant/src/whisper.cpp/build:$LD_LIBRARY_PATH

# 测试
./bin/voice_assistant \
    --wake-word "你好小助手"
```

---

## 系统服务配置

### 1. 创建systemd服务

```bash
# 创建服务文件
sudo nano /etc/systemd/system/ai-assistant.service
```

内容如下:
```ini
[Unit]
Description=AI Voice Assistant
After=network.target sound.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/ai-assistant
Environment="LD_LIBRARY_PATH=/home/pi/ai-assistant/src/llama.cpp/build:/home/pi/ai-assistant/src/whisper.cpp/build"
ExecStart=/home/pi/ai-assistant/bin/voice_assistant --wake-word "你好小助手"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 2. 启用服务

```bash
# 重新加载systemd
sudo systemctl daemon-reload

# 启用服务（开机自启）
sudo systemctl enable ai-assistant

# 启动服务
sudo systemctl start ai-assistant

# 查看状态
sudo systemctl status ai-assistant

# 查看日志
sudo journalctl -u ai-assistant -f
```

### 3. 创建启动脚本（替代方案）

```bash
# 创建启动脚本
nano ~/ai-assistant/start.sh
```

内容:
```bash
#!/bin/bash

# AI助手启动脚本
cd /home/pi/ai-assistant

# 设置环境变量
export LD_LIBRARY_PATH=./src/llama.cpp/build:./src/whisper.cpp/build:$LD_LIBRARY_PATH

# 日志文件
LOG_FILE=./logs/assistant-$(date +%Y%m%d-%H%M%S).log

# 启动助手
echo "🚀 启动AI助手..." | tee -a $LOG_FILE
./bin/voice_assistant --wake-word "你好小助手" 2>&1 | tee -a $LOG_FILE
```

```bash
# 赋予执行权限
chmod +x ~/ai-assistant/start.sh

# 测试
~/ai-assistant/start.sh
```

---

## 测试验证

### 1. 基础功能测试

```bash
# 测试麦克风
arecord -d 5 -f cd test-mic.wav
aplay test-mic.wav

# 测试扬声器
speaker-test -c 2 -t wav -l 1

# 测试Whisper
./src/whisper.cpp/bin/main \
    -m models/ggml-small.en.bin \
    -f test-mic.wav

# 测试LLM
./bin/qwen_inference \
    --model models/qwen3-0.6b-q8_0.gguf

# 测试TTS
echo "测试语音合成" | ./bin/piper \
    --model models/en_US-amy-medium.onnx \
    --output_file test-tts.wav
aplay test-tts.wav
```

### 2. 性能测试

```bash
# 创建性能测试脚本
nano ~/ai-assistant/benchmark.sh
```

内容:
```bash
#!/bin/bash

echo "🔍 性能测试报告"
echo "================="

# 系统信息
echo "📊 系统信息:"
echo "CPU: $(cat /proc/cpuinfo | grep 'model name' | uniq | cut -d: -f2)"
echo "内存: $(free -h | grep Mem | awk '{print $2}')"
echo "温度: $(vcgencmd measure_temp)"

# LLM推理速度
echo -e "\n🤖 LLM推理速度:"
time ./src/llama.cpp/build/bin/main \
    -m models/qwen3-0.6b-q8_0.gguf \
    -n 100 \
    -p "What is AI?" \
    2>&1 | grep "tokens per second"

# Whisper识别速度
echo -e "\n🗣️  Whisper识别速度:"
time ./src/whisper.cpp/bin/main \
    -m models/ggml-small.en.bin \
    -f samples/jfk.wav \
    2>&1 | grep "load time"

# 内存使用
echo -e "\n💾 内存使用:"
ps aux | grep -E 'voice_assistant|qwen_inference' | grep -v grep

echo -e "\n✅ 测试完成！"
```

```bash
chmod +x ~/ai-assistant/benchmark.sh
./benchmark.sh
```

### 3. 完整流程测试

```bash
# 启动语音助手
./bin/voice_assistant

# 测试流程:
# 1. 说出唤醒词: "你好小助手"
# 2. 等待提示音
# 3. 提问: "什么是人工智能?"
# 4. 听取回复

# 查看日志
tail -f logs/assistant-*.log
```

---

## 故障排查

### 问题1: 音频设备未找到

```bash
# 检查音频设备
arecord -l
aplay -l

# 配置默认设备
sudo nano /etc/asound.conf

# 内容:
defaults.pcm.card 1
defaults.ctl.card 1

# 重启ALSA
sudo alsa force-reload
```

### 问题2: 模型加载失败

```bash
# 检查文件权限
ls -l models/*.gguf

# 检查内存
free -h
# 如果可用内存<2GB，增加交换空间

# 检查模型完整性
md5sum models/qwen3-0.6b-q8_0.gguf
# 对比原始MD5值
```

### 问题3: 推理速度慢

```bash
# 检查CPU频率
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq

# 设置性能模式
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# 检查温度
watch -n 1 vcgencmd measure_temp
# 如果>75°C，改善散热

# 降低线程数
./bin/qwen_inference --threads 2  # 尝试2个线程
```

### 问题4: 内存不足

```bash
# 清理缓存
sudo sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

# 增加swap
sudo swapoff /swapfile
sudo rm /swapfile
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 使用更小的模型
# 尝试 INT4 量化版本而非 INT8
```

### 问题5: 服务无法启动

```bash
# 查看详细日志
sudo journalctl -u ai-assistant -n 50 --no-pager

# 手动测试
cd ~/ai-assistant
./start.sh

# 检查依赖
ldd ./bin/voice_assistant
# 确保所有库都能找到
```

---

## 优化建议

### 1. 性能优化

```bash
# CPU调度器
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# 禁用不必要的服务
sudo systemctl disable bluetooth
sudo systemctl disable avahi-daemon
sudo systemctl disable triggerhappy

# 优化内核参数
sudo nano /etc/sysctl.conf
# 添加:
vm.swappiness=10
vm.dirty_ratio=15
```

### 2. 存储优化

```bash
# 如果使用SD卡，减少写入
sudo nano /etc/fstab
# 添加 noatime 选项:
/dev/mmcblk0p2  /  ext4  defaults,noatime  0  1

# 日志轮转
sudo nano /etc/logrotate.d/ai-assistant
# 内容:
/home/pi/ai-assistant/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
```

### 3. 电源管理

```bash
# 禁用USB自动休眠
echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend

# 禁用WiFi省电模式
sudo iwconfig wlan0 power off
```

---

## 维护操作

### 日常维护

```bash
# 查看系统状态
./maintenance.sh status

# 查看日志
./maintenance.sh logs

# 重启服务
./maintenance.sh restart

# 更新模型
./maintenance.sh update-model
```

### 备份

```bash
# 备份配置和模型
tar -czf ai-assistant-backup-$(date +%Y%m%d).tar.gz \
    ~/ai-assistant/models \
    ~/ai-assistant/src/*.cpp \
    ~/ai-assistant/start.sh

# 传输到远程
scp ai-assistant-backup-*.tar.gz user@backup-server:/backups/
```

---

## 总结

完成以上步骤后，你的树莓派5 AI助手应该已经:

✅ 系统完整安装并优化
✅ 所有依赖库正确编译
✅ 模型成功部署
✅ 语音交互功能正常
✅ 开机自动启动
✅ 性能达到预期（10-20 tokens/秒）

**下一步可以**:
- 添加更多功能（如日程管理、智能家居控制）
- 优化唤醒词检测
- 添加情感识别
- 连接其他设备

祝使用愉快！🎉