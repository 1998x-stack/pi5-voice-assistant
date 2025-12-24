#!/bin/bash

###############################################
# AI Voice Assistant - 维护脚本
# 用于系统管理、监控和维护
###############################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目路径
PROJECT_DIR="$HOME/ai-assistant"
BIN_DIR="$PROJECT_DIR/bin"
MODELS_DIR="$PROJECT_DIR/models"
LOGS_DIR="$PROJECT_DIR/logs"

# 服务名称
SERVICE_NAME="ai-assistant"

###############################################
# 工具函数
###############################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

###############################################
# 状态检查
###############################################

check_status() {
    print_header "系统状态检查"
    
    # 检查服务状态
    echo -e "\n📊 服务状态:"
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_success "服务正在运行"
        systemctl status $SERVICE_NAME --no-pager | grep "Active:"
    else
        print_error "服务未运行"
    fi
    
    # 检查系统资源
    echo -e "\n💻 系统资源:"
    echo "  CPU温度: $(vcgencmd measure_temp)"
    echo "  内存使用: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo "  磁盘使用: $(df -h $PROJECT_DIR | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}')"
    
    # 检查进程
    echo -e "\n🔍 相关进程:"
    ps aux | grep -E "voice_assistant|qwen_inference" | grep -v grep || echo "  无相关进程运行"
    
    # 检查模型文件
    echo -e "\n📁 模型文件:"
    if [ -f "$MODELS_DIR/qwen3-0.6b-q8_0.gguf" ]; then
        size=$(du -h "$MODELS_DIR/qwen3-0.6b-q8_0.gguf" | cut -f1)
        print_success "LLM模型: $size"
    else
        print_error "LLM模型缺失"
    fi
    
    if [ -f "$MODELS_DIR/ggml-small.en.bin" ]; then
        size=$(du -h "$MODELS_DIR/ggml-small.en.bin" | cut -f1)
        print_success "Whisper模型: $size"
    else
        print_error "Whisper模型缺失"
    fi
    
    if [ -f "$MODELS_DIR/en_US-amy-medium.onnx" ]; then
        size=$(du -h "$MODELS_DIR/en_US-amy-medium.onnx" | cut -f1)
        print_success "TTS模型: $size"
    else
        print_error "TTS模型缺失"
    fi
    
    # 检查音频设备
    echo -e "\n🎤 音频设备:"
    if arecord -l &>/dev/null; then
        print_success "录音设备可用"
    else
        print_error "录音设备不可用"
    fi
    
    if aplay -l &>/dev/null; then
        print_success "播放设备可用"
    else
        print_error "播放设备不可用"
    fi
    
    # 检查最近的日志
    echo -e "\n📝 最近日志:"
    if [ -d "$LOGS_DIR" ]; then
        latest_log=$(ls -t $LOGS_DIR/*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            echo "  最新日志: $(basename $latest_log)"
            echo "  大小: $(du -h $latest_log | cut -f1)"
            echo "  最后更新: $(stat -c %y $latest_log | cut -d'.' -f1)"
        else
            print_warning "无日志文件"
        fi
    fi
}

###############################################
# 服务管理
###############################################

start_service() {
    print_header "启动服务"
    sudo systemctl start $SERVICE_NAME
    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_success "服务已启动"
    else
        print_error "服务启动失败"
        print_info "查看日志: sudo journalctl -u $SERVICE_NAME -n 50"
    fi
}

stop_service() {
    print_header "停止服务"
    sudo systemctl stop $SERVICE_NAME
    sleep 1
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        print_success "服务已停止"
    else
        print_error "服务停止失败"
    fi
}

restart_service() {
    print_header "重启服务"
    sudo systemctl restart $SERVICE_NAME
    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_success "服务已重启"
    else
        print_error "服务重启失败"
    fi
}

enable_service() {
    print_header "启用开机自启"
    sudo systemctl enable $SERVICE_NAME
    print_success "已设置开机自启"
}

disable_service() {
    print_header "禁用开机自启"
    sudo systemctl disable $SERVICE_NAME
    print_success "已禁用开机自启"
}

###############################################
# 日志管理
###############################################

show_logs() {
    print_header "查看日志"
    
    echo -e "\n选择日志源:"
    echo "  1) 系统日志 (journalctl)"
    echo "  2) 应用日志 (logs/)"
    echo "  3) 实时日志 (tail -f)"
    echo -n "请选择 [1-3]: "
    read choice
    
    case $choice in
        1)
            echo -e "\n📋 系统日志 (最近50行):"
            sudo journalctl -u $SERVICE_NAME -n 50 --no-pager
            ;;
        2)
            if [ -d "$LOGS_DIR" ]; then
                latest_log=$(ls -t $LOGS_DIR/*.log 2>/dev/null | head -1)
                if [ -n "$latest_log" ]; then
                    echo -e "\n📋 应用日志: $(basename $latest_log)"
                    tail -n 50 "$latest_log"
                else
                    print_error "无日志文件"
                fi
            else
                print_error "日志目录不存在"
            fi
            ;;
        3)
            echo -e "\n📋 实时日志 (Ctrl+C 退出):"
            sudo journalctl -u $SERVICE_NAME -f
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

clear_logs() {
    print_header "清理日志"
    
    echo -n "确认清理所有日志？[y/N]: "
    read confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # 清理应用日志
        if [ -d "$LOGS_DIR" ]; then
            rm -f $LOGS_DIR/*.log
            print_success "应用日志已清理"
        fi
        
        # 清理系统日志
        sudo journalctl --rotate
        sudo journalctl --vacuum-time=1d
        print_success "系统日志已清理"
    else
        print_info "操作已取消"
    fi
}

###############################################
# 性能监控
###############################################

monitor_performance() {
    print_header "实时性能监控"
    print_info "按 Ctrl+C 退出"
    
    while true; do
        clear
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}  实时性能监控${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        
        # CPU温度
        temp=$(vcgencmd measure_temp | cut -d= -f2)
        echo -e "🌡️  CPU温度: ${YELLOW}$temp${NC}"
        
        # CPU频率
        freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
        freq_mhz=$((freq / 1000))
        echo -e "⚡ CPU频率: ${GREEN}${freq_mhz}MHz${NC}"
        
        # 内存使用
        mem_info=$(free -h | grep Mem)
        mem_used=$(echo $mem_info | awk '{print $3}')
        mem_total=$(echo $mem_info | awk '{print $2}')
        echo -e "💾 内存使用: ${mem_used} / ${mem_total}"
        
        # 进程信息
        echo -e "\n📊 相关进程:"
        ps aux | grep -E "voice_assistant|qwen_inference" | grep -v grep | \
            awk '{printf "  PID: %-6s  CPU: %-5s  MEM: %-5s  CMD: %s\n", $2, $3"%", $4"%", $11}'
        
        sleep 2
    done
}

###############################################
# 系统维护
###############################################

system_cleanup() {
    print_header "系统清理"
    
    # 清理包缓存
    echo -e "\n🧹 清理包缓存..."
    sudo apt clean
    sudo apt autoremove -y
    
    # 清理临时文件
    echo -e "\n🧹 清理临时文件..."
    sudo rm -rf /tmp/*
    
    # 清理日志
    echo -e "\n🧹 清理旧日志..."
    sudo journalctl --vacuum-time=7d
    
    # 显示释放的空间
    echo -e "\n💾 磁盘空间:"
    df -h / | tail -1 | awk '{print "  可用: " $4 " / " $2 " (" $5 " 已用)"}'
    
    print_success "清理完成"
}

update_system() {
    print_header "系统更新"
    
    echo -n "确认更新系统？[y/N]: "
    read confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        sudo apt update
        sudo apt upgrade -y
        print_success "系统更新完成"
        print_warning "建议重启系统"
    else
        print_info "操作已取消"
    fi
}

optimize_system() {
    print_header "系统优化"
    
    # 设置CPU为性能模式
    echo -e "\n⚡ 设置CPU性能模式..."
    echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
    print_success "CPU已设置为性能模式"
    
    # 调整swap倾向
    echo -e "\n💾 优化内存参数..."
    sudo sysctl -w vm.swappiness=10
    print_success "内存参数已优化"
    
    # 禁用不必要的服务
    echo -e "\n🚫 禁用不必要的服务..."
    services=("bluetooth" "avahi-daemon" "triggerhappy")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            sudo systemctl stop $service
            sudo systemctl disable $service
            echo "  已禁用: $service"
        fi
    done
    
    print_success "系统优化完成"
}

###############################################
# 测试功能
###############################################

run_tests() {
    print_header "运行系统测试"
    
    # 测试音频
    echo -e "\n🎤 测试音频设备..."
    if arecord -l &>/dev/null && aplay -l &>/dev/null; then
        print_success "音频设备正常"
    else
        print_error "音频设备异常"
    fi
    
    # 测试LLM
    echo -e "\n🤖 测试LLM推理..."
    if [ -f "$BIN_DIR/qwen_inference" ] && [ -f "$MODELS_DIR/qwen3-0.6b-q8_0.gguf" ]; then
        timeout 30s $BIN_DIR/qwen_inference \
            --model $MODELS_DIR/qwen3-0.6b-q8_0.gguf \
            --threads 2 \
            --max-tokens 10 \
            < /dev/null &> /tmp/llm_test.log
        
        if [ $? -eq 0 ]; then
            print_success "LLM推理正常"
        else
            print_error "LLM推理失败"
            print_info "查看日志: cat /tmp/llm_test.log"
        fi
    else
        print_error "LLM文件缺失"
    fi
    
    # 测试TTS
    echo -e "\n🔊 测试语音合成..."
    if [ -f "$BIN_DIR/piper" ] && [ -f "$MODELS_DIR/en_US-amy-medium.onnx" ]; then
        echo "Test" | $BIN_DIR/piper \
            --model $MODELS_DIR/en_US-amy-medium.onnx \
            --output_file /tmp/tts_test.wav &> /dev/null
        
        if [ $? -eq 0 ] && [ -f /tmp/tts_test.wav ]; then
            print_success "语音合成正常"
            rm /tmp/tts_test.wav
        else
            print_error "语音合成失败"
        fi
    else
        print_error "TTS文件缺失"
    fi
    
    echo -e "\n✅ 测试完成"
}

###############################################
# 备份与恢复
###############################################

backup_system() {
    print_header "系统备份"
    
    backup_dir="$HOME/backups"
    mkdir -p $backup_dir
    
    backup_file="$backup_dir/ai-assistant-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo -e "\n📦 创建备份..."
    tar -czf $backup_file \
        -C $PROJECT_DIR \
        models src/*.cpp bin scripts \
        2> /dev/null
    
    if [ $? -eq 0 ]; then
        size=$(du -h $backup_file | cut -f1)
        print_success "备份完成: $backup_file ($size)"
    else
        print_error "备份失败"
    fi
}

###############################################
# 主菜单
###############################################

show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  AI Voice Assistant - 维护工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "  1)  查看系统状态"
    echo "  2)  启动服务"
    echo "  3)  停止服务"
    echo "  4)  重启服务"
    echo "  5)  启用开机自启"
    echo "  6)  禁用开机自启"
    echo ""
    echo "  7)  查看日志"
    echo "  8)  清理日志"
    echo "  9)  实时性能监控"
    echo ""
    echo " 10)  运行测试"
    echo " 11)  系统清理"
    echo " 12)  系统更新"
    echo " 13)  系统优化"
    echo " 14)  创建备份"
    echo ""
    echo "  0)  退出"
    echo ""
    echo -n "请选择操作 [0-14]: "
}

main() {
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) check_status ;;
            2) start_service ;;
            3) stop_service ;;
            4) restart_service ;;
            5) enable_service ;;
            6) disable_service ;;
            7) show_logs ;;
            8) clear_logs ;;
            9) monitor_performance ;;
            10) run_tests ;;
            11) system_cleanup ;;
            12) update_system ;;
            13) optimize_system ;;
            14) backup_system ;;
            0) 
                echo -e "\n${GREEN}👋 再见！${NC}"
                exit 0
                ;;
            *)
                print_error "无效选择"
                ;;
        esac
        
        echo ""
        echo -n "按 Enter 继续..."
        read
    done
}

# 命令行模式
if [ $# -gt 0 ]; then
    case "$1" in
        status) check_status ;;
        start) start_service ;;
        stop) stop_service ;;
        restart) restart_service ;;
        logs) show_logs ;;
        monitor) monitor_performance ;;
        test) run_tests ;;
        backup) backup_system ;;
        *) 
            echo "用法: $0 {status|start|stop|restart|logs|monitor|test|backup}"
            echo "或直接运行以显示交互式菜单"
            exit 1
            ;;
    esac
else
    main
fi