
# Development Guide for speak

This guide is for developers who want to modify, extend, or contribute to `speak`. It covers everything from setting up your environment to debugging advanced features like the agent loop and disk‑backed KV cache.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Cloning the Repository](#cloning-the-repository)
- [Manual Installation of `llama.cr`](#manual-installation-of-llamacr)
- [Adding the Readline Shard](#adding-the-readline-shard)
- [System Libraries](#system-libraries)
- [Installing `llama.cpp` (Shared Library)](#installing-llamacpp-shared-library)
- [Building `speak`](#building-speak)
- [First Run and Model Download](#first-run-and-model-download)
- [Project Structure](#project-structure)
- [Development Workflow](#development-workflow)
  - [Adding a New Tool](#adding-a-new-tool)
  - [Modifying the Agent Loop](#modifying-the-agent-loop)
  - [Changing Model Quantization](#changing-model-quantization)
- [Debugging Tips](#debugging-tips)
- [Troubleshooting Common Errors](#troubleshooting-common-errors)
- [Running Tests](#running-tests)
- [Contributing Guidelines](#contributing-guidelines)
- [License](#license)

---

## Prerequisites

- **Crystal** 1.12 or later – [Installation guide](https://crystal-lang.org/install/)
- **Git** – to clone the repository
- **`libllama.so`** – the shared library of `llama.cpp` (see installation below)
- **`aria2c`** (optional) – for faster multi‑threaded model downloads via `hfd.sh`
- **`wget`** and **`bash`** – used by the `hfd.sh` downloader

---

## Cloning the Repository

```bash
git clone https://github.com/zendrx/speak.git
cd speak
```

---

Manual Installation of llama.cr

The Crystal shard llama.cr is tightly coupled to a specific llama.cpp build. Using shards install directly often fails due to version mismatches. The reliable method is to clone the shard manually and check out the exact version required by speak.

1. Create the lib directory (if not present):
   ```bash
   mkdir -p lib
   ```
2. Clone llama.cr into lib/:
   ```bash
   git clone https://github.com/kojix2/llama.cr.git lib/llama.cr
   ```
3. Determine the required version from shard.yml:
   ```bash
   REQUIRED_VERSION=$(grep -A2 "llama:" shard.yml | grep "version:" | awk '{print $2}' | tr -d '"')
   echo $REQUIRED_VERSION
   ```
4. Checkout that version inside the cloned shard:
   ```bash
   cd lib/llama.cr
   git checkout v$REQUIRED_VERSION   # or just $REQUIRED_VERSION if no 'v' prefix
   cd ../..
   ```
5. Run shards install to fetch other dependencies (like json – though it’s part of the standard library, this still ensures the shard lock is updated):
   ```bash
   shards install
   ```

---

Adding the Readline Shard

speak uses Readline for command line editing and history. This functionality has been removed from Crystal’s standard library and is now provided by an external shard.

1. Add the dependency to shard.yml:
   ```yaml
   dependencies:
     readline:
       github: crystal-lang/crystal-readline
   ```
2. Install the shard:
   ```bash
   shards install
   ```

---

System Libraries

The readline shard requires the native Readline library to be installed on your system.

OS Command
>
Ubuntu / Debian sudo apt install libreadline-dev
Fedora / RHEL sudo dnf install readline-devel
Arch Linux sudo pacman -S readline
macOS brew install readline

Note for macOS users: After installing with Homebrew, you may need to set the library path:

```bash
export LIBRARY_PATH=$LIBRARY_PATH:/usr/local/opt/readline/lib
export CPATH=$CPATH:/usr/local/opt/readline/include
```

---

Installing llama.cpp (Shared Library)

speak does not bundle llama.cpp. You must install the shared library (libllama.so on Linux, libllama.dylib on macOS) and its ggml backends. The easiest way is to download the pre‑built binaries for the exact version that llama.cr expects.

1. Find the required build number from your installed llama.cr:
   ```bash
   cat lib/llama.cr/LLAMA_VERSION   # e.g., 8119
   ```
2. Download the archive for your platform:
>
   Platform Archive pattern
   Linux (x86_64) llama-<VERSION>-bin-ubuntu-x64.tar.gz
   macOS (ARM64) llama-<VERSION>-bin-macos-arm64.tar.gz
   macOS (x86_64) llama-<VERSION>-bin-macos-x64.tar.gz
   Example for Linux:
   ```bash
   VERSION=$(cat lib/llama.cr/LLAMA_VERSION)
   curl -L "https://github.com/ggml-org/llama.cpp/releases/download/b${VERSION}/llama-${VERSION}-bin-ubuntu-x64.tar.gz" -o llama.tar.gz
   tar -xzf llama.tar.gz
   ```
3. Copy all shared libraries to a system directory (/usr/local/lib) or keep them local. For a system‑wide install:
   ```bash
   sudo cp llama-${VERSION}/*.so /usr/local/lib/
   sudo ldconfig
   ```
   For a project‑local install (no sudo), place them in ./speak/lib/ and set LD_LIBRARY_PATH:
   ```bash
   mkdir -p ./speak/lib
   cp llama-${VERSION}/*.so ./speak/lib/
   export LD_LIBRARY_PATH="$PWD/speak/lib:$LD_LIBRARY_PATH"
   ```
4. Verify the installation:
   ```bash
   ldconfig -p | grep llama   # Linux
   # or
   ls -l /usr/local/lib/libllama*
   ```

---

Building speak

Once all dependencies are in place, compile the binary:

```bash
crystal build src/speak.cr --release -o speak_app
```

-  --release enables optimisations (important for performance).
-  Using a different name (speak_app) avoids conflicts with the ./speak/ data directory.

---

First Run and Model Download

Run the compiled binary:

```bash
./speak_app
```

On the first run, speak will:

1. Create the ./speak/ data directory.
2. Detect your hardware (RAM, CPU cores, AVX2, free disk space).
3. Generate ./speak/config.json with optimal settings.
4. Automatically download the Nanbeige 4.1‑3B model (Q4_K_M quant, ~2.5 GB) using the hfd.sh script (which uses aria2c for parallel downloads).
   · If aria2c is not installed, the script will attempt to install it via your system’s package manager.
   · Download progress is shown; you can resume interrupted downloads.

Note: The model is large. Ensure you have enough disk space (~3 GB) and a stable internet connection.

---

Project Structure

```
speak/
├── src/
│   ├── speak.cr              # Entry point: loads config, model, launches chat
│   └── speak/
│       ├── system.cr         # Hardware detection (RAM, CPU, disk)
│       ├── config.cr         # JSON configuration management (detected, active, overrides)
│       ├── install.cr        # Model downloader (hfd.sh + aria2c + fallback HTTP)
│       ├── disk.cr           # Disk‑backed KV cache (ds4 style, SHA1 token keys)
│       ├── tool.cr           # Tool system: read_file, search_web, remember, finish
│       ├── memory.cr         # Agent memory: working, episodic, semantic
│       ├── launch.cr         # Chat interface with agent loop, streaming, tool processing
│       └── system_prompt.txt # Embedded system prompt
├── lib/                      # Shards (llama.cr, readline, etc.)
├── shard.yml
├── shard.lock
├── README.md
└── LICENSE
```

---

Development Workflow

Adding a New Tool

To add a new tool (e.g., a calculator or a system command runner), follow these steps:

1. Define the tool schema in tool.cr inside TOOLS_SCHEMA (JSON format compatible with Nanbeige4.1‑3B):
   ```crystal
   {
     type: "function",
     function: {
       name: "calculate",
       description: "Perform arithmetic operations",
       parameters: {
         type: "object",
         properties: {
           expression: { type: "string", description: "Math expression, e.g., '2 + 2'" }
         },
         required: ["expression"]
       }
     }
   }
   ```
2. Implement the handler method in the Tool class:
   ```crystal
   def calculate(expression : String) : String
     # Evaluate expression safely (e.g., using a library or a restricted eval)
     result = evaluate(expression)
     result.to_s
   rescue ex
     "Error: #{ex.message}"
   end
   ```
3. Add a case branch in execute_tool:
   ```crystal
   when "calculate"
     expr = args["expression"].as_s
     calculate(expr)
   ```
4. Update the system prompt (in system_prompt.txt) to document the new tool’s syntax and purpose.
5. Test by asking the AI to use the tool. The agent loop will automatically detect <tool_call> tags and execute the corresponding handler.

Modifying the Agent Loop

The agent loop lives in launch.cr inside the agent_loop method. Key adjustable parameters:

· @max_iterations – Maximum number of tool calls per user request (default 10). Increase for complex multi‑step tasks.
· Memory injection – @memory.build_memory_prompt adds working memory, episodic memories, and semantic facts to the system prompt. You can customise which memory types are included.
· Tool result truncation – If a tool returns a very long result, consider truncating it to prevent exceeding the context window.

To debug the loop, add temporary puts statements inside agent_loop to inspect messages, tool call detection, and exit conditions.

Changing Model Quantization

If you want speak to use a different quantisation (e.g., Q2_K for low‑RAM systems or Q6_K for higher quality), edit MODEL_URLS in install.cr:

```crystal
MODEL_URLS = {
  "Q2_K" => {
    repo_id: "mradermacher/Nanbeige4.1-3B-GGUF",
    filename: "Nanbeige4.1-3B.Q2_K.gguf",
    size_mb: 1700,
  },
  # ... other quants
}
```

After changing the URLs, delete the old model file in ./speak/models/ and run ./speak_app again to trigger a fresh download.

---

Debugging Tips

Enable Verbose Logging

Set the environment variable before starting speak:

```bash
export SPEAK_DEBUG=1
./speak_app
```

Currently, this prints token‑by‑token generation (if implemented). You can add more puts statements in critical sections.

Monitor Memory Usage

```bash
watch -n 1 'ps aux | grep speak_app | grep -v grep'
```

Test Tool Calls Manually

You can bypass the agent loop by piping a tool call directly into speak_app. The program will still process it through the normal generation path.

```bash
echo '<tool_call>{"name": "read_file", "arguments": {"path": "config.json"}}</tool_call>' | ./speak_app
```

Inspect the KV Cache

The disk cache files are stored in ./speak/kv_cache/ as <SHA1>.kv. To see which conversations are cached, use:

```bash
ls -la ./speak/kv_cache/
```

Check the Agent Memory

The memory command inside speak prints both user memory (from user.md) and the current working memory. You can also directly examine the JSON files:

```bash
cat ./speak/agent_memory/working.json          # working memory
cat ./speak/agent_memory/episodic/*.json       # past conversation episodes
cat ./speak/agent_memory/semantic/*.json       # extracted facts
```

---

Troubleshooting Common Errors

undefined method 'tokenize' for Llama::Context

Cause: You are calling context.tokenize instead of @vocab.tokenize.
Fix: In disk.cr, ensure you store @vocab (from model.vocab) and use @vocab.tokenize(prompt).

unable to create dir ./speak file exists

Cause: Your binary is named speak and the data directory also wants to be called speak.
Fix: Compile as speak_app (or any name other than speak). The data directory will be ./speak/ (a directory), and the binary can be ./speak_app.

401 Unauthorized during model download

Cause: Direct curl/wget downloads now require authentication on Hugging Face.
Fix: install.cr uses hfd.sh which internally uses aria2c and respects HF_TOKEN. If you still get 401, log in via huggingface-cli login or set the environment variable HF_TOKEN.

Readline not found

Cause: The readline shard is not installed or the system library is missing.
Fix:

1. Ensure crystal-readline is in shard.yml and you’ve run shards install.
2. Install libreadline-dev (Linux) or readline (macOS) as described above.

undefined constant IO::Timeout (or IO::TimeoutError)

Cause: Crystal renamed IO::Timeout to IO::TimeoutError in version 0.34.0.
Fix: Replace all occurrences of IO::Timeout with IO::TimeoutError in install.cr and disk.cr.

---

Running Tests

Currently, speak has an incomplete test suite. You can run the existing specs with:

```bash
crystal spec
```

If you add new functionality, please write corresponding tests in the spec/ directory.

---

Contributing Guidelines

1. Fork the repository on GitHub.
2. Create a feature branch from master:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Make your changes, keeping the code style consistent with the existing files (2 spaces indentation, no trailing whitespace).
4. Test your changes manually (run ./speak_app and exercise the new feature).
5. Update documentation – modify README.md and development.md as needed.
6. Commit with a clear message:
   ```bash
   git commit -m "Add: description of your change"
   ```
7. Push to your fork and open a Pull Request against the master branch of the original repository.

All contributions are welcome, whether bug fixes, performance improvements, new tools, or documentation updates.

---

License

speak is open‑source under the MIT License. See the LICENSE file for details.

```
```
