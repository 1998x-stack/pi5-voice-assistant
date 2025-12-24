/**
 * qwen_inference.cpp
 * 
 * 使用 llama.cpp 在树莓派5上运行 Qwen3-0.6B 的推理引擎
 * 
 * 编译方法:
 * g++ -O3 -std=c++17 -march=native -mtune=native \
 *     qwen_inference.cpp -o qwen_inference \
 *     -I./llama.cpp -L./llama.cpp -lllama -pthread
 * 
 * 依赖:
 * - llama.cpp (https://github.com/ggerganov/llama.cpp)
 */

#include <iostream>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <memory>
#include <chrono>
#include "llama.h"

// ============ 配置类 ============
struct InferenceConfig {
    std::string model_path = "./models/qwen3-0.6b-q8_0.gguf";
    int n_ctx = 2048;           // 上下文长度
    int n_threads = 4;          // 线程数（树莓派5有4核）
    int n_gpu_layers = 0;       // GPU层数（树莓派无GPU，设为0）
    int n_batch = 512;          // 批处理大小
    float temperature = 0.7;    // 温度参数
    float top_p = 0.9;          // top-p采样
    int max_tokens = 512;       // 最大生成token数
    bool verbose = false;       // 详细输出
};

// ============ LLM推理类 ============
class QwenInference {
private:
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    InferenceConfig config;
    
public:
    QwenInference(const InferenceConfig& cfg) : config(cfg) {}
    
    ~QwenInference() {
        if (ctx) llama_free(ctx);
        if (model) llama_free_model(model);
        llama_backend_free();
    }
    
    // 初始化模型
    bool initialize() {
        std::cout << "🚀 初始化模型..." << std::endl;
        
        // 初始化llama.cpp后端
        llama_backend_init(false);
        
        // 模型参数
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = config.n_gpu_layers;
        
        // 加载模型
        std::cout << "  加载模型文件: " << config.model_path << std::endl;
        model = llama_load_model_from_file(
            config.model_path.c_str(), 
            model_params
        );
        
        if (!model) {
            std::cerr << "❌ 模型加载失败！" << std::endl;
            return false;
        }
        
        // 上下文参数
        llama_context_params ctx_params = llama_context_default_params();
        ctx_params.seed = 42;
        ctx_params.n_ctx = config.n_ctx;
        ctx_params.n_batch = config.n_batch;
        ctx_params.n_threads = config.n_threads;
        ctx_params.n_threads_batch = config.n_threads;
        
        // 创建上下文
        ctx = llama_new_context_with_model(model, ctx_params);
        
        if (!ctx) {
            std::cerr << "❌ 上下文创建失败！" << std::endl;
            return false;
        }
        
        std::cout << "✅ 模型初始化完成！" << std::endl;
        std::cout << "  上下文长度: " << config.n_ctx << std::endl;
        std::cout << "  线程数: " << config.n_threads << std::endl;
        
        return true;
    }
    
    // 分词
    std::vector<llama_token> tokenize(const std::string& text, bool add_bos = true) {
        int n_tokens = text.length() + (add_bos ? 1 : 0);
        std::vector<llama_token> tokens(n_tokens);
        
        int actual_tokens = llama_tokenize(
            model,
            text.c_str(),
            text.length(),
            tokens.data(),
            tokens.size(),
            add_bos,
            false  // special tokens
        );
        
        if (actual_tokens < 0) {
            tokens.resize(-actual_tokens);
            actual_tokens = llama_tokenize(
                model,
                text.c_str(),
                text.length(),
                tokens.data(),
                tokens.size(),
                add_bos,
                false
            );
        }
        
        tokens.resize(actual_tokens);
        return tokens;
    }
    
    // 生成文本
    std::string generate(const std::string& prompt) {
        auto start_time = std::chrono::high_resolution_clock::now();
        
        if (config.verbose) {
            std::cout << "\n📝 输入提示:\n" << prompt << std::endl;
            std::cout << "\n🤖 生成中..." << std::endl;
        }
        
        // 分词
        auto tokens = tokenize(prompt, true);
        
        if (config.verbose) {
            std::cout << "  Token数量: " << tokens.size() << std::endl;
        }
        
        // 清空KV缓存
        llama_kv_cache_clear(ctx);
        
        // 处理prompt
        for (size_t i = 0; i < tokens.size(); i += config.n_batch) {
            size_t batch_size = std::min(
                config.n_batch, 
                (int)(tokens.size() - i)
            );
            
            llama_batch batch = llama_batch_init(batch_size, 0, 1);
            
            for (size_t j = 0; j < batch_size; j++) {
                llama_batch_add(batch, tokens[i + j], i + j, {0}, false);
            }
            
            // 最后一个token需要输出logits
            if (i + batch_size >= tokens.size()) {
                batch.logits[batch_size - 1] = true;
            }
            
            if (llama_decode(ctx, batch) != 0) {
                std::cerr << "❌ 解码失败！" << std::endl;
                llama_batch_free(batch);
                return "";
            }
            
            llama_batch_free(batch);
        }
        
        // 生成
        std::string generated_text;
        int n_cur = tokens.size();
        int n_generated = 0;
        
        while (n_generated < config.max_tokens) {
            // 获取logits
            float* logits = llama_get_logits_ith(ctx, -1);
            int n_vocab = llama_n_vocab(model);
            
            // 采样
            std::vector<llama_token_data> candidates;
            candidates.reserve(n_vocab);
            
            for (int i = 0; i < n_vocab; i++) {
                candidates.push_back({i, logits[i], 0.0f});
            }
            
            llama_token_data_array candidates_p = {
                candidates.data(),
                candidates.size(),
                false
            };
            
            // Top-p采样
            llama_sample_top_p(ctx, &candidates_p, config.top_p, 1);
            llama_sample_temp(ctx, &candidates_p, config.temperature);
            llama_token new_token = llama_sample_token(ctx, &candidates_p);
            
            // 检查EOS
            if (new_token == llama_token_eos(model)) {
                break;
            }
            
            // 解码token
            const char* piece = llama_token_to_piece(model, new_token);
            if (piece) {
                generated_text += piece;
                if (config.verbose) {
                    std::cout << piece << std::flush;
                }
            }
            
            // 准备下一次迭代
            llama_batch batch = llama_batch_init(1, 0, 1);
            llama_batch_add(batch, new_token, n_cur, {0}, true);
            
            if (llama_decode(ctx, batch) != 0) {
                llama_batch_free(batch);
                break;
            }
            
            llama_batch_free(batch);
            
            n_cur++;
            n_generated++;
        }
        
        auto end_time = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            end_time - start_time
        ).count();
        
        if (config.verbose) {
            std::cout << "\n\n⏱️  生成统计:" << std::endl;
            std::cout << "  生成token数: " << n_generated << std::endl;
            std::cout << "  总耗时: " << duration << "ms" << std::endl;
            std::cout << "  速度: " << (n_generated * 1000.0 / duration) 
                      << " tokens/秒" << std::endl;
        }
        
        return generated_text;
    }
    
    // 对话生成（使用Qwen3格式）
    std::string chat(const std::string& user_message, 
                     const std::string& system_message = "你是一个有帮助的AI助手。") {
        // Qwen3 chat模板
        std::string prompt = "<|im_start|>system\n" + system_message + "<|im_end|>\n";
        prompt += "<|im_start|>user\n" + user_message + "<|im_end|>\n";
        prompt += "<|im_start|>assistant\n";
        
        return generate(prompt);
    }
};

// ============ 主函数 ============
int main(int argc, char** argv) {
    std::cout << "=" << std::string(58, '=') << "=" << std::endl;
    std::cout << "  Qwen3-0.6B 推理引擎 (树莓派5版本)" << std::endl;
    std::cout << "=" << std::string(58, '=') << "=" << std::endl;
    
    // 配置
    InferenceConfig config;
    config.verbose = true;
    
    // 解析命令行参数
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--model" && i + 1 < argc) {
            config.model_path = argv[++i];
        } else if (arg == "--threads" && i + 1 < argc) {
            config.n_threads = std::stoi(argv[++i]);
        } else if (arg == "--max-tokens" && i + 1 < argc) {
            config.max_tokens = std::stoi(argv[++i]);
        } else if (arg == "--temperature" && i + 1 < argc) {
            config.temperature = std::stof(argv[++i]);
        }
    }
    
    // 初始化
    QwenInference inference(config);
    if (!inference.initialize()) {
        return 1;
    }
    
    // 交互式对话
    std::cout << "\n💬 进入对话模式（输入 'quit' 退出）\n" << std::endl;
    
    std::string line;
    while (true) {
        std::cout << "用户: ";
        std::getline(std::cin, line);
        
        if (line == "quit" || line == "exit") {
            break;
        }
        
        if (line.empty()) {
            continue;
        }
        
        std::cout << "助手: ";
        std::string response = inference.chat(line);
        std::cout << response << std::endl << std::endl;
    }
    
    std::cout << "👋 再见！" << std::endl;
    
    return 0;
}