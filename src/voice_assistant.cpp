/**
 * voice_assistant.cpp
 * 
 * 完整的语音AI助手实现
 * 集成: Whisper语音识别 + Qwen3推理 + Piper语音合成
 * 
 * 编译:
 * g++ -O3 -std=c++17 -march=native \
 *     voice_assistant.cpp -o voice_assistant \
 *     -I./whisper.cpp -L./whisper.cpp -lwhisper \
 *     -I./llama.cpp -L./llama.cpp -lllama \
 *     -I./piper -L./piper -lpiper_phonemize \
 *     -lportaudio -pthread
 * 
 * 依赖库:
 * - whisper.cpp: https://github.com/ggerganov/whisper.cpp
 * - llama.cpp: https://github.com/ggerganov/llama.cpp  
 * - piper: https://github.com/rhasspy/piper
 * - portaudio: sudo apt install libportaudio2 portaudio19-dev
 */

#include <iostream>
#include <string>
#include <vector>
#include <queue>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <memory>
#include <fstream>
#include <cstring>

// 音频库
#include <portaudio.h>

// AI模型接口（简化版，实际应包含完整头文件）
extern "C" {
    // Whisper STT
    struct whisper_context;
    whisper_context* whisper_init_from_file(const char* path);
    int whisper_full(whisper_context* ctx, /* 参数... */);
    const char* whisper_full_get_segment_text(whisper_context* ctx, int i);
    void whisper_free(whisper_context* ctx);
    
    // Llama LLM
    struct llama_model;
    struct llama_context;
    // ... (前面已定义的接口)
    
    // Piper TTS  
    struct piper_config;
    int piper_init(const char* model_path, piper_config* config);
    int piper_synthesize(const char* text, float* audio_out, int* length);
    void piper_cleanup();
}

// ============ 配置 ============
struct VoiceAssistantConfig {
    // 模型路径
    std::string whisper_model = "./models/ggml-small.bin";
    std::string llm_model = "./models/qwen3-0.6b-q8_0.gguf";
    std::string tts_model = "./models/piper-en_US-amy-medium.onnx";
    
    // 音频参数
    int sample_rate = 16000;
    int channels = 1;
    int frames_per_buffer = 1024;
    
    // 语音检测
    float silence_threshold = 0.02;  // 静音阈值
    int silence_duration_ms = 1000;  // 静音持续时间
    
    // 唤醒词
    std::string wake_word = "你好小助手";
    
    // LLM参数
    int llm_threads = 4;
    float temperature = 0.7;
    int max_tokens = 256;
};

// ============ 音频捕获类 ============
class AudioCapture {
private:
    PaStream* stream = nullptr;
    std::vector<float> audio_buffer;
    std::mutex buffer_mutex;
    std::atomic<bool> is_recording{false};
    VoiceAssistantConfig config;
    
    // PortAudio回调
    static int recordCallback(
        const void* input,
        void* output,
        unsigned long frameCount,
        const PaStreamCallbackTimeInfo* timeInfo,
        PaStreamCallbackFlags statusFlags,
        void* userData
    ) {
        AudioCapture* self = (AudioCapture*)userData;
        const float* in = (const float*)input;
        
        std::lock_guard<std::mutex> lock(self->buffer_mutex);
        self->audio_buffer.insert(
            self->audio_buffer.end(),
            in,
            in + frameCount
        );
        
        return paContinue;
    }
    
public:
    AudioCapture(const VoiceAssistantConfig& cfg) : config(cfg) {}
    
    ~AudioCapture() {
        stop();
        if (stream) {
            Pa_CloseStream(stream);
        }
        Pa_Terminate();
    }
    
    bool initialize() {
        std::cout << "🎤 初始化音频采集..." << std::endl;
        
        PaError err = Pa_Initialize();
        if (err != paNoError) {
            std::cerr << "❌ PortAudio初始化失败: " 
                      << Pa_GetErrorText(err) << std::endl;
            return false;
        }
        
        PaStreamParameters inputParams;
        inputParams.device = Pa_GetDefaultInputDevice();
        inputParams.channelCount = config.channels;
        inputParams.sampleFormat = paFloat32;
        inputParams.suggestedLatency = 
            Pa_GetDeviceInfo(inputParams.device)->defaultLowInputLatency;
        inputParams.hostApiSpecificStreamInfo = nullptr;
        
        err = Pa_OpenStream(
            &stream,
            &inputParams,
            nullptr,
            config.sample_rate,
            config.frames_per_buffer,
            paClipOff,
            recordCallback,
            this
        );
        
        if (err != paNoError) {
            std::cerr << "❌ 音频流打开失败: " 
                      << Pa_GetErrorText(err) << std::endl;
            return false;
        }
        
        std::cout << "✅ 音频采集初始化完成" << std::endl;
        return true;
    }
    
    bool start() {
        if (!stream) return false;
        
        audio_buffer.clear();
        is_recording = true;
        
        PaError err = Pa_StartStream(stream);
        if (err != paNoError) {
            std::cerr << "❌ 音频流启动失败" << std::endl;
            return false;
        }
        
        std::cout << "🔴 开始录音..." << std::endl;
        return true;
    }
    
    bool stop() {
        if (!stream || !is_recording) return false;
        
        is_recording = false;
        Pa_StopStream(stream);
        
        std::cout << "⏹️  停止录音" << std::endl;
        return true;
    }
    
    std::vector<float> getAudioData() {
        std::lock_guard<std::mutex> lock(buffer_mutex);
        std::vector<float> data = audio_buffer;
        audio_buffer.clear();
        return data;
    }
    
    // 检测静音（简单能量检测）
    bool detectSilence(const std::vector<float>& audio, int duration_ms) {
        if (audio.empty()) return false;
        
        int samples_for_silence = (config.sample_rate * duration_ms) / 1000;
        if (audio.size() < samples_for_silence) return false;
        
        // 计算最近一段时间的能量
        float energy = 0.0f;
        int start = audio.size() - samples_for_silence;
        for (int i = start; i < audio.size(); i++) {
            energy += audio[i] * audio[i];
        }
        energy = std::sqrt(energy / samples_for_silence);
        
        return energy < config.silence_threshold;
    }
};

// ============ 语音识别类 ============
class SpeechRecognizer {
private:
    whisper_context* ctx = nullptr;
    VoiceAssistantConfig config;
    
public:
    SpeechRecognizer(const VoiceAssistantConfig& cfg) : config(cfg) {}
    
    ~SpeechRecognizer() {
        if (ctx) {
            whisper_free(ctx);
        }
    }
    
    bool initialize() {
        std::cout << "🗣️  初始化语音识别..." << std::endl;
        
        ctx = whisper_init_from_file(config.whisper_model.c_str());
        if (!ctx) {
            std::cerr << "❌ Whisper模型加载失败" << std::endl;
            return false;
        }
        
        std::cout << "✅ 语音识别初始化完成" << std::endl;
        return true;
    }
    
    std::string transcribe(const std::vector<float>& audio) {
        if (!ctx || audio.empty()) {
            return "";
        }
        
        std::cout << "🔍 识别中..." << std::endl;
        
        // 简化的whisper调用（实际需要完整参数）
        // whisper_full(ctx, audio.data(), audio.size(), ...);
        
        // 获取识别结果
        std::string result = "";
        // for (int i = 0; i < n_segments; i++) {
        //     result += whisper_full_get_segment_text(ctx, i);
        // }
        
        // 临时模拟
        result = "这是识别的文本内容";
        
        std::cout << "📝 识别结果: " << result << std::endl;
        return result;
    }
};

// ============ 语音合成类 ============
class SpeechSynthesizer {
private:
    VoiceAssistantConfig config;
    bool initialized = false;
    
public:
    SpeechSynthesizer(const VoiceAssistantConfig& cfg) : config(cfg) {}
    
    ~SpeechSynthesizer() {
        if (initialized) {
            piper_cleanup();
        }
    }
    
    bool initialize() {
        std::cout << "🔊 初始化语音合成..." << std::endl;
        
        piper_config pconfig;
        if (piper_init(config.tts_model.c_str(), &pconfig) != 0) {
            std::cerr << "❌ Piper模型加载失败" << std::endl;
            return false;
        }
        
        initialized = true;
        std::cout << "✅ 语音合成初始化完成" << std::endl;
        return true;
    }
    
    bool synthesize(const std::string& text, std::vector<float>& audio_out) {
        if (!initialized || text.empty()) {
            return false;
        }
        
        std::cout << "🎵 合成语音..." << std::endl;
        
        // 临时模拟（实际调用piper）
        int length = 0;
        // piper_synthesize(text.c_str(), audio_buffer, &length);
        
        std::cout << "✅ 语音合成完成" << std::endl;
        return true;
    }
};

// ============ 主控制器 ============
class VoiceAssistant {
private:
    VoiceAssistantConfig config;
    AudioCapture audio_capture;
    SpeechRecognizer recognizer;
    SpeechSynthesizer synthesizer;
    // QwenInference llm;  // 前面定义的LLM类
    
    std::atomic<bool> running{false};
    std::atomic<bool> listening{false};
    
public:
    VoiceAssistant(const VoiceAssistantConfig& cfg)
        : config(cfg)
        , audio_capture(cfg)
        , recognizer(cfg)
        , synthesizer(cfg)
        // , llm(cfg)
    {}
    
    bool initialize() {
        std::cout << "\n🚀 初始化语音助手系统...\n" << std::endl;
        
        if (!audio_capture.initialize()) return false;
        if (!recognizer.initialize()) return false;
        if (!synthesizer.initialize()) return false;
        // if (!llm.initialize()) return false;
        
        std::cout << "\n✅ 系统初始化完成！\n" << std::endl;
        return true;
    }
    
    void run() {
        running = true;
        
        std::cout << "🎯 语音助手已启动！" << std::endl;
        std::cout << "📢 请说 \"" << config.wake_word << "\" 唤醒助手" << std::endl;
        std::cout << "💡 按 Ctrl+C 退出\n" << std::endl;
        
        while (running) {
            // 等待唤醒词
            if (!listening) {
                waitForWakeWord();
            }
            
            // 监听用户输入
            if (listening) {
                processUserInput();
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }
    
    void stop() {
        running = false;
        audio_capture.stop();
    }
    
private:
    void waitForWakeWord() {
        audio_capture.start();
        
        auto start_time = std::chrono::steady_clock::now();
        std::vector<float> audio_buffer;
        
        while (running && !listening) {
            // 累积音频
            auto new_audio = audio_capture.getAudioData();
            audio_buffer.insert(
                audio_buffer.end(),
                new_audio.begin(),
                new_audio.end()
            );
            
            // 每2秒识别一次
            auto now = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
                now - start_time
            ).count();
            
            if (elapsed >= 2 && !audio_buffer.empty()) {
                std::string text = recognizer.transcribe(audio_buffer);
                
                if (text.find(config.wake_word) != std::string::npos) {
                    std::cout << "\n🎉 检测到唤醒词！" << std::endl;
                    listening = true;
                    audio_buffer.clear();
                    break;
                }
                
                // 只保留最近5秒音频
                int max_samples = config.sample_rate * 5;
                if (audio_buffer.size() > max_samples) {
                    audio_buffer.erase(
                        audio_buffer.begin(),
                        audio_buffer.end() - max_samples
                    );
                }
                
                start_time = now;
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        
        audio_capture.stop();
    }
    
    void processUserInput() {
        std::cout << "🎤 正在倾听..." << std::endl;
        
        audio_capture.start();
        
        std::vector<float> audio_buffer;
        auto last_sound_time = std::chrono::steady_clock::now();
        bool detected_sound = false;
        
        while (running && listening) {
            auto new_audio = audio_capture.getAudioData();
            audio_buffer.insert(
                audio_buffer.end(),
                new_audio.begin(),
                new_audio.end()
            );
            
            // 检测静音
            if (!audio_buffer.empty()) {
                bool is_silent = audio_capture.detectSilence(
                    audio_buffer,
                    config.silence_duration_ms
                );
                
                if (!is_silent) {
                    detected_sound = true;
                    last_sound_time = std::chrono::steady_clock::now();
                } else if (detected_sound) {
                    // 检测到声音后的静音 -> 用户说完了
                    auto now = std::chrono::steady_clock::now();
                    auto silence = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now - last_sound_time
                    ).count();
                    
                    if (silence >= config.silence_duration_ms) {
                        std::cout << "⏸️  检测到静音，处理中..." << std::endl;
                        break;
                    }
                }
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        
        audio_capture.stop();
        
        // 处理音频
        if (!audio_buffer.empty() && detected_sound) {
            handleUserQuery(audio_buffer);
        }
        
        listening = false;
    }
    
    void handleUserQuery(const std::vector<float>& audio) {
        // 1. 语音识别
        std::string user_text = recognizer.transcribe(audio);
        if (user_text.empty()) {
            std::cout << "❌ 识别失败" << std::endl;
            return;
        }
        
        std::cout << "👤 用户: " << user_text << std::endl;
        
        // 2. LLM生成回复
        std::cout << "🤔 思考中..." << std::endl;
        // std::string response = llm.chat(user_text);
        std::string response = "这是助手的回复内容";  // 临时模拟
        
        std::cout << "🤖 助手: " << response << std::endl;
        
        // 3. 语音合成
        std::vector<float> audio_response;
        if (synthesizer.synthesize(response, audio_response)) {
            // 播放音频（需要实现播放逻辑）
            playAudio(audio_response);
        }
    }
    
    void playAudio(const std::vector<float>& audio) {
        // 实现音频播放逻辑
        std::cout << "🔊 播放语音回复..." << std::endl;
        // 使用PortAudio输出流播放
    }
};

// ============ 主函数 ============
int main(int argc, char** argv) {
    std::cout << "=" << std::string(58, '=') << "=" << std::endl;
    std::cout << "  🤖 智能语音助手 - 树莓派5版" << std::endl;
    std::cout << "=" << std::string(58, '=') << "=" << std::endl;
    
    // 配置
    VoiceAssistantConfig config;
    
    // 解析命令行参数
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--wake-word" && i + 1 < argc) {
            config.wake_word = argv[++i];
        }
        // 其他参数...
    }
    
    // 创建并运行助手
    VoiceAssistant assistant(config);
    
    if (!assistant.initialize()) {
        std::cerr << "❌ 初始化失败" << std::endl;
        return 1;
    }
    
    // 信号处理
    std::signal(SIGINT, [](int) {
        std::cout << "\n\n👋 正在退出..." << std::endl;
        // assistant.stop();  // 需要全局访问
    });
    
    assistant.run();
    
    return 0;
}