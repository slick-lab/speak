
# speak Documentation

speak is a local AI assistant that runs entirely on your computer. No internet required. No subscription. Your data stays with you.

## Quick Start

```bash
# Clone and build
git clone https://github.com/zendrx/speak.git
cd speak
shards install
crystal build src/speak.cr --release -o speak

# Run
./speak
```

On first run, speak will:

- Detect your RAM and CPU
- Create a config file
- Download the AI model (~2.5GB)
- Start the chat

Requirements

Component Minimum
- RAM 4 GB
- Storage 3 GB free
- OS Linux (macOS experimental)
- CPU Any 64-bit

Commands

Inside the chat, type these commands:

Command What it does

exit or quit Save and exit

clear Clear screen

history Show conversation history

save Save conversation manually

memory Show what speak remembers about you

clearmemory Clear all memories


What speak Can Do

Remember You Across Sessions

Tell speak something about yourself:

```
> I'm a Python developer who hates Java
speak: I've remembered that.
```

Next time you run speak, it still knows:

```
> What do you know about me?
speak: You are a Python developer who hates Java.
```

Read Your Files

```
> Read my config.json
speak: [shows the content of config.json]
```

Search the Web

```
> Search for Crystal language 2026 features
speak: [shows search results from DuckDuckGo]
```

Have Long Conversations

speak saves conversation state to your SSD, not RAM. 

You can chat for hours without memory usage growing.

Configuration

All settings are in ./speak/config.json. You can edit this file.

Common Settings to Change

- Setting What it does Default
- context_size How many tokens the AI remembers 2048
- temperature Creativity (0.0 = strict, 1.5 = creative) 0.7
- max_tokens Maximum response length 512
- model_quant Quality vs speed (Q2_K, Q4_K_M, Q6_K) Q4_K_M

Example: Make AI More Creative

Edit ./speak/config.json:

```json
"user_overrides": {
  "temperature": 1.2
}
```

Example: Reduce RAM Usage

```json
"user_overrides": {
  "context_size": 1024,
  "model_quant": "Q2_K"
}
```

How speak Saves RAM

speak uses two techniques to keep memory low:

1. mmap - The model stays on disk, only parts needed are loaded into RAM
2. Disk KV Cache - Conversation memory is saved to SSD, not RAM

On a 4GB machine, speak uses ~500MB - 1GB of RAM.

Model Download

First run downloads the Nanbeige 3B model (~2.5GB). The downloader supports:

- Resuming if interrupted
- Multi-threaded download (fast)
- Progress bar with speed and ETA

If download fails, run ./speak again - it resumes from where it stopped.

Troubleshooting

"Unable to create dir ./speak"

Your binary is named speak and conflicts with the data directory. Rename the binary:

```bash
mv speak speak_app
./speak_app
```

"401 Unauthorized" during download

The model repository requires authentication. Run:

```bash
./hfd.sh Edge-Quant/Nanbeige4.1-3B-Q4_K_M-GGUF --include *.gguf --local-dir ./speak/models
```

Then run ./speak again.

Model loads slowly on HDD

Use the smaller Q2_K model. Edit config.json:

```json
"user_overrides": {
  "model_quant": "Q2_K"
}
```

Then delete the old model file in ./speak/models/ and restart speak.

Readline not working

Install the system library:

```bash
# Ubuntu/Debian
sudo apt install libreadline-dev

# macOS
brew install readline
```

Uninstall

```bash
rm -rf ./speak          # Remove data and models
rm speak                # Remove binary
```

License

MIT License

Credits

- Built with Crystal
- Inference by llama.cpp
- Bindings by llama.cr
- Model by Nanbeige
- Disk cache inspired by antirez/ds4
