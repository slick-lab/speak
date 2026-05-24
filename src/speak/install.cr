require "http/client"
require "digest/md5"

module Speak
  class Install
    CACHE_DIR           = "./speak/models"
    PARTIAL_EXT         = ".partial"
    MAX_RETRIES         =    3
    INITIAL_RETRY_DELAY =  1.0
    CHUNK_SIZE          = 8192

    MODEL_URLS = {
      "Q2_K" => {
        url:     "https://huggingface.co/TheBloke/Nanbeige4.1-3B-GGUF/resolve/main/Nanbeige4.1-3B-Q2_K.gguf",
        size_mb: 1700,
      },
      "Q4_K_M" => {
        url:     "https://huggingface.co/TheBloke/Nanbeige4.1-3B-GGUF/resolve/main/Nanbeige4.1-3B-Q4_K_M.gguf",
        size_mb: 2500,
      },
      "Q6_K" => {
        url:     "https://huggingface.co/TheBloke/Nanbeige4.1-3B-GGUF/resolve/main/Nanbeige4.1-3B-Q6_K.gguf",
        size_mb: 3300,
      },
    }

    struct DownloadProgress
      property downloaded : UInt64
      property total : UInt64
      property start_time : Time::Span
      property speed_samples : Array(Float64)

      def initialize(@total : UInt64)
        @downloaded = 0_u64
        @start_time = Time.monotonic
        @speed_samples = [] of Float64
      end

      def percentage : Int32
        return 0 if total == 0
        ((downloaded * 100) / total).to_i
      end

      def speed_mbps : Float64
        elapsed = (Time.monotonic - start_time).total_seconds
        return 0.0 if elapsed == 0
        (downloaded.to_f / (1024 * 1024)) / elapsed
      end

      def eta_seconds : Int32
        return 0 if speed_mbps == 0
        remaining_mb = (total - downloaded).to_f / (1024 * 1024)
        (remaining_mb / speed_mbps).to_i
      end

      def update_sample
        speed_samples << speed_mbps
        if speed_samples.size > 10
          speed_sample = speed_samples.last(10)
        end
      end

      def average_speed : Float64
        return 0.0 if speed_samples.empty?
        speed_samples.sum / speed_samples.size
      end
    end

    def initialize
      Dir.mkdir_p(CACHE_DIR) unless Dir.exists?(CACHE_DIR)
    end

    def install_model(quant : String) : Bool
      unless MODEL_URLS.has_key?(quant)
        puts "Error: Unknown model quant '#{quant}'"
        puts "Available: #{MODEL_URLS.keys.join(", ")}"
        return false
      end

      model_info = MODEL_URLS[quant]
      filename = File.basename(model_info[:url])
      dest_path = File.join(CACHE_DIR, filename)
      partial_path = dest_path + PARTIAL_EXT

      if File.exists?(dest_path)
        expected_size = model_info[:size_mb].to_u64 * 1024 * 1024
        actual_size = File.size(dest_path)

        if actual_size == expected_size
          puts "Model already installed: #{filename}"
          return true
        else
          puts "Existing file corrupted, re-downloading..."
          File.delete(dest_path) if File.exists?(dest_path)
        end
      end

      puts "Downloading #{quant} model..."
      puts "File: #{filename}"
      puts "Size: #{format_bytes(model_info[:size_mb].to_u64 * 1024 * 1024)}"
      puts "From: #{model_info[:url]}"
      puts ""

      success = download_with_resume(model_info[:url], dest_path, partial_path, model_info[:size_mb].to_u64)

      if success
        puts "\nInstallation complete: #{filename}"
        true
      else
        puts "\nInstallation failed"
        false
      end
    end

    private def download_with_resume(url : String, dest_path : String, partial_path : String, expected_size_mb : UInt64) : Bool
      retries = 0
      expected_size = expected_size_mb * 1024 * 1024

      while retries < MAX_RETRIES
        existing_size = 0_u64
        current_path = dest_path

        if File.exists?(partial_path)
          existing_size = File.size(partial_path)
          current_path = partial_path
          puts "Resuming from #{format_bytes(existing_size.to_u64)}" if existing_size > 0
        elsif File.exists?(dest_path)
          existing_size = File.size(dest_path)
          puts "Resuming from #{format_bytes(existing_size.to_u64)}" if existing_size > 0
        end

        if existing_size >= expected_size
          File.rename(current_path, dest_path) if current_path != dest_path
          return verify_integrity(dest_path, expected_size)
        end

        begin
          downloaded = perform_download(url, current_path, existing_size.to_u64, expected_size)

          if downloaded >= expected_size
            File.rename(current_path, dest_path) if current_path != dest_path
            return verify_integrity(dest_path, expected_size)
          end

          retries += 1
          if retries < MAX_RETRIES
            delay = INITIAL_RETRY_DELAY * (2 ** retries)
            puts "\nConnection issue, retrying in #{delay.to_i} seconds... (attempt #{retries + 1}/#{MAX_RETRIES})"
            sleep(delay)
          end
        rescue ex : IO::TimeoutError | IO::Error | Socket::Error
          retries += 1
          if retries < MAX_RETRIES
            delay = INITIAL_RETRY_DELAY * (2 ** retries)
            puts "\nNetwork error: #{ex.message}. Retrying in #{delay.to_i}s..."
            sleep(delay)
          else
            puts "\nNetwork error after #{MAX_RETRIES} attempts: #{ex.message}"
            return false
          end
        rescue ex
          puts "\nUnexpected error: #{ex.message}"
          return false
        end
      end

      false
    end

    private def perform_download(url : String, file_path : String, start_offset : UInt64, expected_size : UInt64) : UInt64
      downloaded = start_offset

      headers = HTTP::Headers.new
      headers["User-Agent"] = "speak-installer/1.0"
      headers["Range"] = "bytes=#{start_offset}-" if start_offset > 0

      File.open(file_path, "ab") do |file|
        HTTP::Client.get(url, headers) do |response|
          unless response.status_code == 200 || response.status_code == 206
            raise "HTTP #{response.status_code}: #{response.status_message}"
          end

          total_size = expected_size
          if content_range = response.headers["Content-Range"]?
            if match = content_range.match(%r{bytes \d+-(\d+)/})
              total_size = match[1].to_u64
            end
          elsif content_length = response.headers["Content-Length"]?
            total_size = content_length.to_u64 + start_offset
          end

          progress = DownloadProgress.new(total_size)
          progress.downloaded = start_offset

          buffer = Bytes.new(CHUNK_SIZE * 4)

          while bytes_read = response.body_io.read(buffer)
            break if bytes_read == 0

            file.write(buffer[0, bytes_read])
            downloaded += bytes_read
            progress.downloaded = downloaded

            progress.update_sample
            display_progress(progress)
          end
        end
      end

      downloaded
    end

    private def display_progress(progress : DownloadProgress)
      percent = progress.percentage
      downloaded_mb = progress.downloaded / (1024 * 1024)
      total_mb = progress.total / (1024 * 1024)
      speed = progress.average_speed
      eta = progress.eta_seconds

      bar_width = 40
      filled = (bar_width * percent / 100).to_i
      bar = "█" * filled + "░" * (bar_width - filled)

      eta_str = if eta > 3600
                  "#{eta / 3600}h #{(eta % 3600) / 60}m"
                elsif eta > 60
                  "#{eta / 60}m #{eta % 60}s"
                else
                  "#{eta}s"
                end

      print "\r[%s] %3d%% | %6.1f MB / %6.1f MB | %5.1f MB/s | ETA: %s" % [
        bar, percent, downloaded_mb, total_mb, speed, eta_str,
      ]
      STDOUT.flush
    end

    private def verify_integrity(file_path : String, expected_size : UInt64) : Bool
      return false unless File.exists?(file_path)

      actual_size = File.size(file_path)

      if actual_size != expected_size
        puts "\nSize mismatch: expected #{format_bytes(expected_size)}, got #{format_bytes(actual_size.to_u64)}"
        return false
      end

      true
    end

    private def format_bytes(bytes : UInt64) : String
      units = ["B", "KB", "MB", "GB"]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.size - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(1)} #{units[unit_index]}"
    end
  end
end
