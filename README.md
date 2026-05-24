
<div align="center">

# Speak

**A lightweight local LLM inference engine written in Crystal**

Run powerful language models directly on your machine with disk-based KV caching, hardware-aware configuration, and efficient resource management.

[![Crystal](https://img.shields.io/badge/Crystal-1.12-000000?logo=crystal)](https://crystal-lang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Lines of Code](https://img.shields.io/badge/LOC-1,133-blue)

<br>

<!-- Speak Logo SVG -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="120" height="120">
  <circle cx="100" cy="100" r="95" fill="#1a1a2e" stroke="#e94560" stroke-width="3"/>
  <polygon points="60,140 80,155 85,130" fill="#e94560"/>
  <rect x="40" y="50" width="120" height="85" rx="15" fill="#e94560"/>
  <rect x="52" y="62" width="96" height="60" rx="8" fill="#1a1a2e"/>
  <polygon points="100,70 115,85 100,100 85,85" fill="#e94560" opacity="0.8"/>
  <line x1="62" y1="85" x2="100" y2="85" stroke="#e94560" stroke-width="3" stroke-linecap="round"/>
  <line x1="62" y1="95" x2="118" y2="95" stroke="#e94560" stroke-width="3" stroke-linecap="round"/>
  <line x1="62" y1="105" x2="108" y2="105" stroke="#e94560" stroke-width="3" stroke-linecap="round"/>
  <text x="100" y="175" text-anchor="middle" fill="#e94560" font-size="12" font-family="monospace">speak</text>
</svg>

</div>

---

## Features

- **Disk-based KV cache** – Persistent conversation state stored on SSD, keeping RAM usage flat and low (<2GB) regardless of conversation length
- **Hardware-aware configuration** – Automatically detects total and available RAM, adjusts context size, mmap, and KV cache type
- **Resumable model downloads** – Automatic model installation with partial download recovery and real-time progress tracking
- **Streaming output** – Tokens appear as they are generated for a responsive chat experience
- **System resource monitoring** – Real‑time detection of RAM, CPU cores, AVX2, and disk space
- **Flexible model quantization** – Supports Q2_K, Q4_K_M, and Q6_K for Nanbeige4.1‑3B
- **Configurable settings** – Context size, KV cache type, temperature, max tokens via JSON
- **User overrides** – Advanced users can edit `config.json` to override any auto-detected setting
- **Custom system prompts** – Modify the embedded system prompt and recompile

---

## Requirements

- Crystal language (0.35+)
- GGUF format model (Nanbeige4.1‑3B recommended)
- Linux (uses `/proc/meminfo`) or macOS (limited support)
- Minimum 4GB RAM (8GB recommended)
- Disk space: 1.7‑4.0 GB for model storage

---

## Dependencies

- `llama.cr` – Crystal bindings to llama.cpp (installed via `shards`)

---

## Installation

```bash
git clone https://github.com/zendrx/speak.git
cd speak
shards install
crystal build src/speak.cr --release -o speak
mkdir -p ./speak/models
```

---

Usage

```bash
./speak
```

On first run, Speak will:

1. Detect total and available RAM
2. Create ./speak/config.json with optimal settings
3. Check for the model in ./speak/models/
4. Download the model if missing (resume + progress bar)
5. Initialize the LLM context (mmap if RAM < 8GB, full load otherwise)
6. Start the interactive chat interface

Chat Commands

Command Action
exit, quit Save conversation and exit
clear Clear the screen
history Show conversation history
save Manually save conversation

---

Configuration

Configuration is stored in ./speak/config.json after first run. The file contains:

```json
{
  "detected": {
    "total_ram_mb": 8192,
    "available_ram_mb": 6200,
    "os_reserved_ram_mb": 512
  },
  "active": {
    "context_size": 2048,
    "kv_cache_type": "standard",
    "model_quant": "Q4_K_M",
    "model_file": "nanbeige-3b-q4_k_m.gguf",
    "temperature": 0.7,
    "max_tokens": 512
  },
  "user_overrides": {
    "os_reserved_ram_mb": null,
    "context_size": null,
    "kv_cache_type": null,
    "model_quant": null,
    "temperature": null,
    "max_tokens": null
  }
}
```

To override auto-detected settings, edit the user_overrides section. For example:

```json
"user_overrides": {
  "context_size": 4096,
  "temperature": 0.9
}
```

System Prompt Customization

The system prompt is embedded at compile time from src/speak/system_prompt.txt. To customize the AI's behavior:

1. Edit src/speak/system_prompt.txt with your preferred instructions
2. Rebuild with crystal build src/speak.cr --release -o speak
3. Run ./speak with your custom instructions

Default system prompt:

```
You are speak, a helpful AI assistant. Be concise and accurate.
```

---

Architecture

Project Structure

```
.
├── src/
│   ├── speak.cr              # Main entry point
│   ├── speak/
│   │   ├── system.cr         # Hardware detection (RAM, CPU, disk)
│   │   ├── config.cr         # JSON configuration management
│   │   ├── install.cr        # Model downloader with resume support
│   │   ├── disk.cr           # Disk-backed KV cache (ds4-style)
│   │   ├── launch.cr         # Streaming chat interface
│   │   └── system_prompt.txt # Embedded system prompt
├── spec/                     # Tests
└── shard.yml                 # Crystal dependencies
```

Key Modules

System Module - Hardware detection:

Method Returns
```text
System.total_ram_mb Total RAM in megabytes
System.available_ram_mb Available RAM in megabytes
System.process_ram_mb Current process memory usage
System.cpu_cores Number of CPU cores
System.cpu_has_avx2 Boolean for AVX2 support
System.free_disk_space_mb(path) Free disk space at path
```
Install Module - Model management:

- Resumable downloads with partial file recovery
- Real-time progress bar with speed and ETA
- Automatic retry with exponential backoff
- Integrity verification (size check)

Disk Cache Module - KV cache persistence:

- Saves conversation state to SSD, not RAM
- SHA1 token-ID-based cache keys (ds4-compatible)
- LRU cache cleanup (maximum 50 files)
- Loads previous sessions without reprocessing

RAM Tiers and Optimization

Available RAM mmap Context Size KV Cache Type
```c
< 3 GB Enabled 512 q4_0
3-6 GB Enabled 1024 q4_0
6-12 GB Enabled 2048 q8_0
> 12 GB Disabled 4096 q8_0
```
---

Development

Building for Development

```bash
crystal build src/speak.cr -o speak
```

Running Tests

```bash
crystal spec
```

Model Downloads

Models are downloaded from HuggingFace. The downloader supports:

- Resumable downloads – Interrupted downloads continue from where they stopped
- Progress tracking – Real-time percentage, speed (MB/s), and ETA
- Streaming – 32KB buffer for efficient memory usage
- Retry logic – Exponential backoff on network errors

---

License

This project is licensed under the MIT License. See LICENSE file for details.

---

Contributors

-  zendrx – Creator and maintainer

---

<div align="center">Made with Crystal
