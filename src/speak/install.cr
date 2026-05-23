require "http/client"

module Speak
  class Install
    def initialize
      @download_dir = "./speak/models"
      Dir.mkdir_p(@download_dir) unless Dir.exists?(@download_dir)
    end

    def install_model(quant : String)
      model_file = "model-#{quant}.gguf"
      model_path = File.join(@download_dir, model_file)
      
      # Check if already downloaded
      return if File.exists?(model_path)
      
      url = "https://huggingface.co/path/to/model/resolve/main/#{model_file}"
      download_with_resume(url, model_path)
    end

    private def download_with_resume(url : String, dest_path : String)
      file_size = get_remote_file_size(url)
      existing_size = File.exists?(dest_path) ? File.size(dest_path) : 0_u64
      
      puts "Downloading: #{File.basename(dest_path)}"
      puts "File size: #{format_bytes(file_size)}"
      
      if existing_size > 0
        puts "Resuming from #{format_bytes(existing_size)}"
      end
      
      HTTP::Client.new(URI.parse(url)) do |client|
        headers = HTTP::Headers.new
        headers["Range"] = "bytes=#{existing_size}-" if existing_size > 0
        
        client.get(url, headers) do |response|
          stream_to_file(response.body_io, dest_path, file_size, existing_size)
        end
      end
    end

    private def get_remote_file_size(url : String) : UInt64
      HTTP::Client.head(url) do |response|
        if content_length = response.headers["Content-Length"]?
          return content_length.to_u64
        end
      end
      0_u64
    end

    private def stream_to_file(io : IO, dest_path : String, total_size : UInt64, start_offset : UInt64)
      File.open(dest_path, "ab") do |file|
        buffer = Bytes.new(8192)
        downloaded = start_offset
        start_time = Time.now
        
        loop do
          bytes_read = io.read(buffer)
          break if bytes_read == 0
          
          file.write(buffer[0, bytes_read])
          downloaded += bytes_read
          
          progress = (downloaded.to_f / total_size.to_f * 100).to_i
          speed = calculate_speed(downloaded - start_offset, start_time)
          eta = calculate_eta(downloaded, total_size, start_time)
          
          print "\r[#{progress}%] #{format_bytes(downloaded)}/#{format_bytes(total_size)} (#{speed}/s) ETA: #{eta}s"
        end
        puts
      end
    end

    private def calculate_speed(bytes : UInt64, start_time : Time) : String
      elapsed = (Time.now - start_time).total_seconds
      return "0 B" if elapsed == 0
      speed_bps = bytes.to_f / elapsed
      format_bytes(speed_bps.to_u64)
    end

    private def calculate_eta(downloaded : UInt64, total : UInt64, start_time : Time) : Int32
      elapsed = (Time.now - start_time).total_seconds
      return 0 if elapsed == 0 || downloaded == 0
      rate = downloaded.to_f / elapsed
      remaining = (total - downloaded).to_f / rate
      remaining.to_i
    end

    private def format_bytes(bytes : UInt64 | Float) : String
      units = ["B", "KB", "MB", "GB"]
      size = bytes.to_f
      
      units.each_with_index do |unit, i|
        return "#{size.round(2)} #{unit}" if size < 1024 || i == units.size - 1
        size /= 1024
      end
      
      "#{size} GB"
    end
  end
end