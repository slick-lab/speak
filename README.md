# Speak

A lightweight local LLM (Large Language Model) inference engine written in Crystal. Run powerful language models directly on your machine with system awareness and efficient resource management.

## Features

- Run LLM models locally without external API dependencies
- Automatic model installation with resumable downloads (partial download support)
- Real-time progress tracking during model downloads
- System resource monitoring (RAM, CPU, disk space)
- CPU feature detection (AVX2 support)
- Flexible model quantization support
- Configurable context size and KV cache settings
- Persistent configuration management

## Requirements

- Crystal language (0.35+)
- GGUF format model files
- Linux/macOS (uses `/proc/meminfo` and similar interfaces)
- Sufficient disk space for model storage (typically 4-40GB depending on model)

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/zendrx/speak.git
cd speak
```

### 2. Install dependencies

```bash
shards install
```

### 3. Build the project

```bash
crystal build src/speak.cr --release -o speak
```

### 4. Create models directory

```bash
mkdir -p ./speak/models
```

## Usage

### Running Speak

```bash
./speak
```

On first run, Speak will:
1. Load or create a configuration file
2. Check for the configured model file
3. Download the model if needed (with resume support)
4. Initialize the LLM context
5. Launch the interactive interface

### Configuration

Configuration is stored in a config file with the following options:

- `model_file`: GGUF model filename
- `model_quant`: Model quantization level (e.g., Q4_K_M, Q5_K_M)
- `context_size`: Context window size (default: 2048)
- `kv_cache_type`: KV cache type configuration
- `temperature`: Model sampling temperature
- `max_tokens`: Maximum tokens to generate

### Model Downloads

Models are downloaded from HuggingFace. The downloader supports:

- Resumable downloads: If interrupted, subsequent runs will continue from where it stopped
- Progress tracking: Real-time progress with speed and ETA display
- Streaming: Efficient memory usage via streaming downloads in 8KB chunks

## Development

### Project Structure

```
.
├── src/
│   ├── speak.cr          # Main entry point
│   ├── speak/
│   │   ├── install.cr    # Model installation and downloading
│   │   └── system.cr     # System resource monitoring
│   ├── config.cr         # Configuration management
│   └── launch.cr         # Interactive interface
├── spec/                 # Tests
└── shard.yml             # Crystal dependencies
```

### Building for Development

```bash
crystal build src/speak.cr -o speak
```

### Running Tests

```bash
crystal spec
```

### Key Modules

**System Module** - Monitor system resources:
- `System.total_ram_mb` - Total RAM in megabytes
- `System.available_ram_mb` - Available RAM in megabytes
- `System.process_ram_mb` - Current process memory usage
- `System.cpu_cores` - Number of CPU cores
- `System.cpu_has_avx2` - Check for AVX2 support
- `System.free_disk_space_mb(path)` - Free disk space at path

**Install Module** - Handle model management:
- `Install.install_model(quant)` - Download and install model with resume support
- Automatic partial download recovery
- Progress tracking with speed and ETA

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -am 'Add feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Submit a pull request

## License

This project is licensed under the MIT License. See LICENSE file for details.

## Contributors

- [zendrx](https://github.com/your-github-user) - creator and maintainer
