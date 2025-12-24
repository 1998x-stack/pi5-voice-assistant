"""
Qwen3-0.6B 在 FineWeb-Edu 数据集上的微调训练脚本
使用 Unsloth 框架进行高效训练

环境要求:
- Python 3.10+
- CUDA 12.1+
- 24GB+ GPU 显存（如 RTX 3090/4090, A100等）
- 或使用 Google Colab Pro

安装依赖:
pip install psutil  # 重要：先安装psutil
pip install unsloth
pip install --upgrade --no-cache-dir "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"
pip install datasets transformers accelerate peft trl
"""

# ============ 重要：确保 psutil 已安装 ============
try:
    import psutil
except ImportError:
    print("⚠️  psutil 未安装，正在安装...")
    import subprocess
    subprocess.check_call(["pip", "install", "psutil"])
    import psutil

import torch
from unsloth import FastLanguageModel
from datasets import load_dataset
from trl import SFTTrainer
from transformers import TrainingArguments, DataCollatorForSeq2Seq
import json
from typing import Dict, List
import random

# ============ 配置参数 ============
class Config:
    # 模型配置
    model_name = "unsloth/Qwen3-0.6B"  # Unsloth优化版本
    max_seq_length = 2048  # 上下文长度（Qwen3支持更长，但2048更快）
    load_in_4bit = True  # 4-bit量化，节省显存
    
    # LoRA配置
    lora_r = 16  # LoRA秩
    lora_alpha = 16
    lora_dropout = 0.05
    target_modules = [
        "q_proj", "k_proj", "v_proj", "o_proj",
        "gate_proj", "up_proj", "down_proj",
    ]
    
    # 训练配置
    batch_size = 4  # 根据显存调整（24GB可用4-8）
    gradient_accumulation_steps = 4  # 有效batch_size = 16
    learning_rate = 2e-4
    num_train_epochs = 3
    warmup_steps = 100
    max_steps = -1  # -1表示训练完整epoch
    
    # 数据配置
    dataset_name = "HuggingFaceFW/fineweb-edu"
    dataset_config = "sample-10BT"  # 使用10B token样本
    max_samples = 50000  # 限制样本数量，根据需要调整
    
    # 输出配置
    output_dir = "./qwen3-0.6b-fineweb-edu"
    logging_steps = 10
    save_steps = 500
    save_total_limit = 3
    
    # 数据处理配置（修复 psutil 相关问题）
    dataset_num_proc = 4  # 显式设置处理进程数，避免依赖 psutil


# ============ 1. 加载模型 ============
def load_model_and_tokenizer(config: Config):
    """加载Qwen3-0.6B模型和分词器"""
    print("🚀 加载模型和分词器...")
    
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=config.model_name,
        max_seq_length=config.max_seq_length,
        dtype=None,  # 自动检测
        load_in_4bit=config.load_in_4bit,
    )
    
    # 配置LoRA
    model = FastLanguageModel.get_peft_model(
        model,
        r=config.lora_r,
        target_modules=config.target_modules,
        lora_alpha=config.lora_alpha,
        lora_dropout=config.lora_dropout,
        bias="none",
        use_gradient_checkpointing="unsloth",  # Unsloth优化
        random_state=42,
    )
    
    # 配置分词器
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right"
    
    print(f"✅ 模型加载完成！可训练参数: {model.get_nb_trainable_parameters()}")
    
    return model, tokenizer


# ============ 2. 准备数据集 ============
def load_and_prepare_dataset(config: Config):
    """加载并预处理FineWeb-Edu数据集"""
    print("📚 加载数据集...")
    
    # 加载数据集（流式加载以节省内存）
    dataset = load_dataset(
        config.dataset_name,
        name=config.dataset_config,
        split="train",
        streaming=True
    )
    
    # 取样本
    samples = []
    for i, example in enumerate(dataset):
        if i >= config.max_samples:
            break
        samples.append(example)
        if (i + 1) % 10000 == 0:
            print(f"  已加载 {i + 1} 个样本...")
    
    # 转换为HF Dataset
    from datasets import Dataset
    dataset = Dataset.from_list(samples)
    
    print(f"✅ 数据集加载完成！共 {len(dataset)} 个样本")
    
    return dataset


def format_instruction_dataset(examples: Dict, tokenizer) -> Dict:
    """
    将FineWeb-Edu文本格式化为instruction-following格式
    使用Qwen3的chat模板
    """
    texts = []
    
    for text in examples["text"]:
        # 只使用高质量的较短文本（避免过长）
        if len(text) < 100 or len(text) > 4000:
            continue
            
        # 创建instruction格式对话
        # 从文本中提取问题或创建任务
        instruction = create_instruction_from_text(text)
        
        # 使用Qwen3 chat模板
        conversation = [
            {"role": "system", "content": "你是一个有帮助的AI助手。"},
            {"role": "user", "content": instruction},
            {"role": "assistant", "content": text}
        ]
        
        # 使用tokenizer的apply_chat_template
        formatted_text = tokenizer.apply_chat_template(
            conversation,
            tokenize=False,
            add_generation_prompt=False
        )
        
        texts.append(formatted_text)
    
    return {"text": texts}


def create_instruction_from_text(text: str) -> str:
    """根据文本内容创建instruction"""
    # 简单策略：提取前100字符作为上下文，要求生成完整内容
    instructions = [
        f"请详细解释以下内容:{text[:100]}...",
        f"继续完成这段文字:{text[:80]}...",
        f"扩展以下主题:{text[:100]}...",
        "请提供关于这个主题的详细信息。",
    ]
    return random.choice(instructions)


# ============ 3. 训练 ============
def train_model(model, tokenizer, dataset, config: Config):
    """训练模型"""
    print("🏋️ 开始训练...")
    
    # 准备数据
    print("  准备训练数据...")
    dataset = dataset.map(
        lambda examples: format_instruction_dataset(examples, tokenizer),
        batched=True,
        remove_columns=dataset.column_names,
        num_proc=1,  # 使用单进程避免潜在问题
    )
    
    # 训练参数（添加 dataset_num_proc 参数）
    training_args = TrainingArguments(
        output_dir=config.output_dir,
        per_device_train_batch_size=config.batch_size,
        gradient_accumulation_steps=config.gradient_accumulation_steps,
        warmup_steps=config.warmup_steps,
        max_steps=config.max_steps,
        num_train_epochs=config.num_train_epochs,
        learning_rate=config.learning_rate,
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(),
        logging_steps=config.logging_steps,
        save_steps=config.save_steps,
        save_total_limit=config.save_total_limit,
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="cosine",
        seed=42,
        report_to="none",  # 不使用wandb等
        dataset_num_proc=config.dataset_num_proc,  # 显式设置，避免依赖psutil
    )
    
    # 数据整理器
    data_collator = DataCollatorForSeq2Seq(
        tokenizer=tokenizer,
        pad_to_multiple_of=8,
        return_tensors="pt",
        padding=True
    )
    
    # 创建Trainer
    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=config.max_seq_length,
        data_collator=data_collator,
        args=training_args,
        packing=False,  # 不使用packing以保持对话格式
        dataset_num_proc=config.dataset_num_proc,  # 也在这里设置
    )
    
    # 开始训练
    print("🚀 训练启动！")
    trainer.train()
    
    print("✅ 训练完成！")
    
    return trainer


# ============ 4. 保存模型 ============
def save_model(model, tokenizer, config: Config):
    """保存微调后的模型"""
    print("💾 保存模型...")
    
    # 保存LoRA权重
    model.save_pretrained(f"{config.output_dir}/final")
    tokenizer.save_pretrained(f"{config.output_dir}/final")
    
    # 保存合并后的模型（可选，用于部署）
    print("  合并LoRA权重到base模型...")
    model.save_pretrained_merged(
        f"{config.output_dir}/merged",
        tokenizer,
        save_method="merged_16bit",  # 或 "merged_4bit"
    )
    
    # 保存为GGUF格式（用于llama.cpp）
    print("  转换为GGUF格式...")
    model.save_pretrained_gguf(
        f"{config.output_dir}/gguf",
        tokenizer,
        quantization_method="q8_0",  # INT8量化
    )
    
    print("✅ 模型保存完成！")
    print(f"  - LoRA权重: {config.output_dir}/final")
    print(f"  - 合并模型: {config.output_dir}/merged")
    print(f"  - GGUF模型: {config.output_dir}/gguf")


# ============ 5. 测试模型 ============
def test_model(model, tokenizer):
    """测试微调后的模型"""
    print("\n🧪 测试模型...")
    
    # 准备推理
    FastLanguageModel.for_inference(model)
    
    # 测试问题
    test_prompts = [
        "什么是机器学习？",
        "解释一下量子计算的基本原理。",
        "如何学习编程？",
    ]
    
    for prompt in test_prompts:
        print(f"\n问题: {prompt}")
        
        # 构建对话
        messages = [
            {"role": "system", "content": "你是一个有帮助的AI助手。"},
            {"role": "user", "content": prompt}
        ]
        
        # 生成回复
        inputs = tokenizer.apply_chat_template(
            messages,
            tokenize=True,
            add_generation_prompt=True,
            return_tensors="pt"
        ).to(model.device)
        
        outputs = model.generate(
            inputs,
            max_new_tokens=256,
            temperature=0.7,
            top_p=0.9,
            do_sample=True,
        )
        
        response = tokenizer.decode(outputs[0][inputs.shape[1]:], skip_special_tokens=True)
        print(f"回复: {response}")


# ============ 主函数 ============
def main():
    """主训练流程"""
    config = Config()
    
    print("=" * 60)
    print("  Qwen3-0.6B FineWeb-Edu 微调训练")
    print("=" * 60)
    
    # 1. 加载模型
    model, tokenizer = load_model_and_tokenizer(config)
    
    # 2. 加载数据
    dataset = load_and_prepare_dataset(config)
    
    # 3. 训练
    trainer = train_model(model, tokenizer, dataset, config)
    
    # 4. 保存
    save_model(model, tokenizer, config)
    
    # 5. 测试
    test_model(model, tokenizer)
    
    print("\n" + "=" * 60)
    print("  🎉 所有步骤完成！")
    print("=" * 60)


if __name__ == "__main__":
    main()