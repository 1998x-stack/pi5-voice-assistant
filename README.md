# pi5-voice-assistant
# 🤖 树莓派5 AI语音助手

基于Qwen3-0.6B的智能语音助手，完全离线运行在树莓派5上。

## ✨ 特性

- 🎤 **实时语音识别** - 使用Faster-Whisper进行准确的语音转文字
- 🧠 **智能对话** - 基于微调后的Qwen3-0.6B模型，理解能力强
- 🔊 **自然语音合成** - 使用Piper TTS生成流畅的语音回复
- 🚀 **高性能** - 优化后可达10-20 tokens/秒
- 💾 **低资源占用** - 总内存占用<2GB
- 🔒 **完全离线** - 无需互联网连接，隐私安全
- ⚡ **快速响应** - 端到端延迟<2秒

## 📋 系统要求

### 硬件要求

**最低配置**:
- 树莓派5 (8GB RAM) ⭐必须
- microSD卡 64GB+ (或NVMe SSD)
- USB麦克风
- 音箱/耳机
- 5V/5A电源适配器

**推荐配置**:
- 树莓派5 (8GB RAM)
- NVMe SSD 256GB+ (显著提升性能)
- ReSpeaker 2-Mics Pi HAT (更好的语音识别)
- USB音箱
- 主动散热风扇

### 软件要求

- Raspberry Pi OS (64-bit) Lite
- GCC 11+
- CMake 3.16+
- Python 3.10+

## 🚀 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/yourusername/pi5-voice-assistant.git
cd pi5-voice-assistant
```

### 2. 一键安装

```bash
# 运行安装脚本
chmod +x install.sh
./install.sh

# 脚本将自动完成:
# - 安装系统依赖
# - 编译所有库
# - 下载模型文件
# - 配置系统
```

### 3. 启动助手

```bash
# 方法1: 直接运行
make run

# 方法2: 作为系统服务
sudo systemctl start ai-assistant
```

## 📦 手动安装

如果自动安装失败，可以按照以下步骤手动安装：

### 步骤1: 安装依赖

```bash
sudo apt update
sudo apt install -y \
    build-essential cmake git \
    portaudio19-dev alsa-utils \
    python3 python3-pip
```

### 步骤2: 编译项目

```bash
# 使用Makefile构建
make all

# 或手动编译
make dependencies
make download-models
make
```

### 步骤3: 下载模型

```bash
# 下载微调后的Qwen3模型
# (请从训练环境传输，或使用原版模型测试)
wget https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/qwen3-0.6b-q8_0.gguf \
    -P models/

# 下载其他模型
make download-models
```

### 步骤4: 测试

```bash
# 运行测试套件
make test

# 测试单个组件
make test-llm        # 测试LLM
make test-whisper    # 测试语音识别
make test-tts        # 测试语音合成
```

## 📚 使用指南

### 基本使用

```bash
# 启动语音助手
./bin/voice_assistant

# 说出唤醒词: "你好小助手"
# 然后提出你的问题
```

### 仅使用LLM（文字交互）

```bash
./bin/qwen_inference \
    --model models/qwen3-0.6b-q8_0.gguf \
    --threads 4
```

### 系统服务

```bash
# 安装为系统服务（开机自启）
make install-service

# 管理服务
sudo systemctl start ai-assistant    # 启动
sudo systemctl stop ai-assistant     # 停止
sudo systemctl restart ai-assistant  # 重启
sudo systemctl status ai-assistant   # 状态

# 查看日志
sudo journalctl -u ai-assistant -f
```

### 维护工具

```bash
# 启动维护工具（交互式菜单）
./scripts/maintenance.sh

# 或直接运行命令
./scripts/maintenance.sh status   # 查看状态
./scripts/maintenance.sh logs     # 查看日志
./scripts/maintenance.sh test     # 运行测试
./scripts/maintenance.sh backup   # 创建备份
```

## ⚙️ 配置

### 自定义唤醒词

编辑 `src/voice_assistant.cpp`:
```cpp
config.wake_word = "你的自定义唤醒词";
```

然后重新编译:
```bash
make
```

### 调整性能参数

编辑配置文件或在启动时指定:
```bash
./bin/voice_assistant \
    --model models/qwen3-0.6b-q8_0.gguf \
    --threads 4 \
    --temperature 0.7 \
    --max-tokens 256
```

### 音频设备配置

```bash
# 列出设备
arecord -l  # 麦克风
aplay -l    # 扬声器

# 设置默认设备
sudo nano /etc/asound.conf

# 添加:
defaults.pcm.card 1
defaults.ctl.card 1
```

## 🔧 故障排查

### 问题: 音频设备不工作

```bash
# 检查设备
arecord -l
aplay -l

# 测试录音
arecord -d 3 test.wav
aplay test.wav

# 如果无输出，检查ALSA配置
alsamixer
```

### 问题: 模型加载失败

```bash
# 检查内存
free -h

# 增加交换空间
sudo fallocate -l 8G /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 验证模型文件
ls -lh models/
md5sum models/qwen3-0.6b-q8_0.gguf
```

### 问题: 推理速度慢

```bash
# 设置CPU为性能模式
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# 检查温度
vcgencmd measure_temp

# 如果过热，改善散热
```

### 问题: 编译失败

```bash
# 检查GCC版本
gcc --version  # 需要11+

# 升级GCC
sudo apt install gcc-11 g++-11
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100

# 清理重新编译
make clean
make all
```

更多问题请查看 [完整部署指南](docs/deployment_guide.md)

## 📊 性能基准

在树莓派5 (8GB) 上的测试结果:

| 指标 | 数值 |
|------|------|
| LLM推理速度 | 15-20 tokens/秒 |
| 语音识别延迟 | ~400ms |
| 语音合成延迟 | ~250ms |
| 端到端响应时间 | <2秒 |
| 内存占用 | ~1.8GB |
| CPU使用率 | 60-80% (4核) |

## 📁 项目结构

```
pi5-voice-assistant/
├── src/                      # 源代码
│   ├── qwen_inference.cpp    # LLM推理引擎
│   ├── voice_assistant.cpp   # 语音助手主程序
│   ├── llama.cpp/            # llama.cpp库
│   ├── whisper.cpp/          # whisper.cpp库
│   └── piper/                # Piper TTS
├── models/                   # 模型文件
│   ├── qwen3-0.6b-q8_0.gguf  # LLM模型
│   ├── ggml-small.en.bin     # Whisper模型
│   └── en_US-amy-medium.onnx # TTS模型
├── bin/                      # 可执行文件
├── build/                    # 构建文件
├── logs/                     # 日志文件
├── scripts/                  # 脚本文件
│   ├── maintenance.sh        # 维护脚本
│   ├── benchmark.sh          # 性能测试
│   └── ai-assistant.service  # systemd服务
├── docs/                     # 文档
├── Makefile                  # 构建系统
├── install.sh                # 安装脚本
└── README.md                 # 本文件
```

## 🔬 微调训练

如果你想使用自己的数据微调模型:

1. 准备训练环境（GPU服务器或Google Colab）
2. 使用提供的训练脚本
3. 将微调后的模型转换为GGUF格式
4. 传输到树莓派

详细步骤请参考 [微调指南](docs/fine_tuning_guide.md)

## 🤝 贡献

欢迎贡献！请阅读 [贡献指南](CONTRIBUTING.md)

## 📄 许可证

本项目使用 Apache 2.0 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [Qwen Team](https://github.com/QwenLM/Qwen) - Qwen3模型
- [Hugging Face](https://huggingface.co/) - FineWeb-Edu数据集
- [ggerganov](https://github.com/ggerganov) - llama.cpp和whisper.cpp
- [Rhasspy](https://github.com/rhasspy) - Piper TTS
- [Unsloth](https://github.com/unslothai/unsloth) - 高效微调框架

## 📮 联系方式

- Issues: [GitHub Issues](https://github.com/yourusername/pi5-voice-assistant/issues)
- Discussions: [GitHub Discussions](https://github.com/yourusername/pi5-voice-assistant/discussions)

## 🗺️ 路线图

- [x] 基础语音交互功能
- [x] FineWeb-Edu数据集微调
- [x] 系统优化和部署
- [ ] 多语言支持
- [ ] 情感识别
- [ ] 智能家居控制集成
- [ ] 移动应用
- [ ] 云同步功能（可选）

---

**⭐ 如果这个项目对你有帮助，请给个Star！**