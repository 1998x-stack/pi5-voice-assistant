# ============================================
# AI Voice Assistant for Raspberry Pi 5
# Makefile
# ============================================

# 编译器配置
CXX = g++
CXXFLAGS = -O3 -std=c++17 -march=native -mtune=native -Wall -Wextra
LDFLAGS = -pthread

# 目录配置
SRC_DIR = src
BUILD_DIR = build
BIN_DIR = bin
MODELS_DIR = models

# 依赖库路径
LLAMA_DIR = $(SRC_DIR)/llama.cpp
WHISPER_DIR = $(SRC_DIR)/whisper.cpp
PIPER_DIR = $(SRC_DIR)/piper

LLAMA_LIB = $(LLAMA_DIR)/build/libllama.a
WHISPER_LIB = $(WHISPER_DIR)/build/libwhisper.a

# 包含路径
INCLUDES = -I$(LLAMA_DIR) -I$(WHISPER_DIR) -I$(PIPER_DIR)

# 链接库
LIBS = -L$(LLAMA_DIR)/build -L$(WHISPER_DIR)/build \
       -lllama -lwhisper -lportaudio -lm

# 目标程序
TARGETS = $(BIN_DIR)/qwen_inference $(BIN_DIR)/voice_assistant

# 默认目标
.PHONY: all
all: setup dependencies $(TARGETS)

# ============================================
# 项目设置
# ============================================

.PHONY: setup
setup:
	@echo "📁 创建目录结构..."
	@mkdir -p $(BUILD_DIR) $(BIN_DIR) $(MODELS_DIR) logs
	@echo "✅ 目录创建完成"

# ============================================
# 依赖库编译
# ============================================

.PHONY: dependencies
dependencies: llama-cpp whisper-cpp piper-tts

.PHONY: llama-cpp
llama-cpp:
	@echo "🔨 编译 llama.cpp..."
	@if [ ! -d "$(LLAMA_DIR)" ]; then \
		git clone https://github.com/ggerganov/llama.cpp.git $(LLAMA_DIR); \
	fi
	@if [ ! -f "$(LLAMA_LIB)" ]; then \
		cd $(LLAMA_DIR) && mkdir -p build && cd build && \
		cmake .. -DCMAKE_BUILD_TYPE=Release -DLLAMA_NATIVE=ON -DLLAMA_LTO=ON && \
		make -j4; \
	fi
	@echo "✅ llama.cpp 编译完成"

.PHONY: whisper-cpp
whisper-cpp:
	@echo "🔨 编译 whisper.cpp..."
	@if [ ! -d "$(WHISPER_DIR)" ]; then \
		git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_DIR); \
	fi
	@if [ ! -f "$(WHISPER_LIB)" ]; then \
		cd $(WHISPER_DIR) && mkdir -p build && cd build && \
		cmake .. -DCMAKE_BUILD_TYPE=Release && \
		make -j4; \
	fi
	@echo "✅ whisper.cpp 编译完成"

.PHONY: piper-tts
piper-tts:
	@echo "📦 下载 Piper TTS..."
	@if [ ! -f "$(BIN_DIR)/piper" ]; then \
		wget -q https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_arm64.tar.gz -O /tmp/piper.tar.gz && \
		tar -xzf /tmp/piper.tar.gz -C /tmp && \
		mv /tmp/piper/piper $(BIN_DIR)/ && \
		rm -rf /tmp/piper /tmp/piper.tar.gz; \
	fi
	@echo "✅ Piper TTS 安装完成"

# ============================================
# 编译目标程序
# ============================================

$(BIN_DIR)/qwen_inference: $(SRC_DIR)/qwen_inference.cpp $(LLAMA_LIB)
	@echo "🔨 编译 qwen_inference..."
	$(CXX) $(CXXFLAGS) $< -o $@ \
		$(INCLUDES) \
		-L$(LLAMA_DIR)/build -lllama \
		$(LDFLAGS)
	@echo "✅ qwen_inference 编译完成"

$(BIN_DIR)/voice_assistant: $(SRC_DIR)/voice_assistant.cpp $(LLAMA_LIB) $(WHISPER_LIB)
	@echo "🔨 编译 voice_assistant..."
	$(CXX) $(CXXFLAGS) $< -o $@ \
		$(INCLUDES) \
		$(LIBS) \
		$(LDFLAGS)
	@echo "✅ voice_assistant 编译完成"

# ============================================
# 模型下载
# ============================================

.PHONY: download-models
download-models: download-llm download-whisper download-tts

.PHONY: download-llm
download-llm:
	@echo "📥 下载 LLM 模型..."
	@if [ ! -f "$(MODELS_DIR)/qwen3-0.6b-q8_0.gguf" ]; then \
		echo "请手动下载微调后的模型，或使用原版:"; \
		echo "wget https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/qwen3-0.6b-q8_0.gguf -P $(MODELS_DIR)"; \
	else \
		echo "✅ LLM 模型已存在"; \
	fi

.PHONY: download-whisper
download-whisper:
	@echo "📥 下载 Whisper 模型..."
	@if [ ! -f "$(MODELS_DIR)/ggml-small.en.bin" ]; then \
		cd $(WHISPER_DIR)/models && \
		bash download-ggml-model.sh small.en && \
		cp ggml-small.en.bin ../../../$(MODELS_DIR)/; \
	else \
		echo "✅ Whisper 模型已存在"; \
	fi

.PHONY: download-tts
download-tts:
	@echo "📥 下载 TTS 模型..."
	@if [ ! -f "$(MODELS_DIR)/en_US-amy-medium.onnx" ]; then \
		wget -q https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/medium/en_US-amy-medium.onnx -P $(MODELS_DIR) && \
		wget -q https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/medium/en_US-amy-medium.onnx.json -P $(MODELS_DIR); \
	else \
		echo "✅ TTS 模型已存在"; \
	fi

# ============================================
# 测试
# ============================================

.PHONY: test
test: test-audio test-llm test-whisper test-tts

.PHONY: test-audio
test-audio:
	@echo "🔊 测试音频设备..."
	@arecord -l || echo "❌ 未找到录音设备"
	@aplay -l || echo "❌ 未找到播放设备"

.PHONY: test-llm
test-llm:
	@echo "🤖 测试 LLM..."
	@$(BIN_DIR)/qwen_inference \
		--model $(MODELS_DIR)/qwen3-0.6b-q8_0.gguf \
		--threads 4 \
		--max-tokens 50 < /dev/null || echo "❌ LLM 测试失败"

.PHONY: test-whisper
test-whisper:
	@echo "🗣️  测试 Whisper..."
	@if [ -f "$(WHISPER_DIR)/samples/jfk.wav" ]; then \
		$(WHISPER_DIR)/build/bin/main \
			-m $(MODELS_DIR)/ggml-small.en.bin \
			-f $(WHISPER_DIR)/samples/jfk.wav; \
	else \
		echo "⚠️  缺少测试音频文件"; \
	fi

.PHONY: test-tts
test-tts:
	@echo "🎵 测试 TTS..."
	@echo "Hello, this is a test." | $(BIN_DIR)/piper \
		--model $(MODELS_DIR)/en_US-amy-medium.onnx \
		--output_file /tmp/test-tts.wav
	@aplay /tmp/test-tts.wav 2>/dev/null && rm /tmp/test-tts.wav

# ============================================
# 运行
# ============================================

.PHONY: run
run:
	@echo "🚀 启动语音助手..."
	@export LD_LIBRARY_PATH=$(LLAMA_DIR)/build:$(WHISPER_DIR)/build:$$LD_LIBRARY_PATH && \
	$(BIN_DIR)/voice_assistant --wake-word "你好小助手"

.PHONY: run-inference
run-inference:
	@echo "🚀 启动推理引擎..."
	@export LD_LIBRARY_PATH=$(LLAMA_DIR)/build:$$LD_LIBRARY_PATH && \
	$(BIN_DIR)/qwen_inference \
		--model $(MODELS_DIR)/qwen3-0.6b-q8_0.gguf \
		--threads 4

# ============================================
# 安装系统服务
# ============================================

.PHONY: install-service
install-service:
	@echo "📦 安装系统服务..."
	@sudo cp scripts/ai-assistant.service /etc/systemd/system/
	@sudo systemctl daemon-reload
	@sudo systemctl enable ai-assistant
	@echo "✅ 系统服务已安装"
	@echo "使用以下命令管理服务:"
	@echo "  启动: sudo systemctl start ai-assistant"
	@echo "  停止: sudo systemctl stop ai-assistant"
	@echo "  状态: sudo systemctl status ai-assistant"
	@echo "  日志: sudo journalctl -u ai-assistant -f"

# ============================================
# 性能测试
# ============================================

.PHONY: benchmark
benchmark:
	@echo "🔍 性能测试..."
	@chmod +x scripts/benchmark.sh
	@./scripts/benchmark.sh

# ============================================
# 清理
# ============================================

.PHONY: clean
clean:
	@echo "🧹 清理构建文件..."
	@rm -rf $(BUILD_DIR)/* $(BIN_DIR)/*
	@echo "✅ 清理完成"

.PHONY: clean-all
clean-all: clean
	@echo "🧹 完全清理..."
	@rm -rf $(LLAMA_DIR) $(WHISPER_DIR) $(PIPER_DIR)
	@rm -rf $(MODELS_DIR)/*
	@rm -rf logs/*
	@echo "✅ 完全清理完成"

# ============================================
# 帮助信息
# ============================================

.PHONY: help
help:
	@echo "=========================================="
	@echo "  AI Voice Assistant - 构建系统"
	@echo "=========================================="
	@echo ""
	@echo "使用方法: make [目标]"
	@echo ""
	@echo "主要目标:"
	@echo "  all              - 完整构建项目（默认）"
	@echo "  setup            - 创建目录结构"
	@echo "  dependencies     - 编译所有依赖库"
	@echo "  download-models  - 下载所有模型文件"
	@echo ""
	@echo "单独编译:"
	@echo "  llama-cpp        - 仅编译 llama.cpp"
	@echo "  whisper-cpp      - 仅编译 whisper.cpp"
	@echo "  piper-tts        - 仅下载 Piper TTS"
	@echo ""
	@echo "测试:"
	@echo "  test             - 运行所有测试"
	@echo "  test-audio       - 测试音频设备"
	@echo "  test-llm         - 测试 LLM"
	@echo "  test-whisper     - 测试 Whisper"
	@echo "  test-tts         - 测试 TTS"
	@echo ""
	@echo "运行:"
	@echo "  run              - 启动语音助手"
	@echo "  run-inference    - 启动推理引擎"
	@echo ""
	@echo "安装:"
	@echo "  install-service  - 安装为系统服务"
	@echo ""
	@echo "其他:"
	@echo "  benchmark        - 性能测试"
	@echo "  clean            - 清理构建文件"
	@echo "  clean-all        - 完全清理（包括依赖）"
	@echo "  help             - 显示此帮助信息"
	@echo ""
	@echo "示例:"
	@echo "  make all                    # 完整构建"
	@echo "  make download-models        # 下载模型"
	@echo "  make test                   # 测试系统"
	@echo "  make run                    # 运行助手"
	@echo ""