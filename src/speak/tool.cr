require "json"
require "http/client"
require "uri"

module Speak
  class Tool
    MEMORY_DIR = "./speak/memory"
    MEMORY_FILE = "./speak/memory/user.md"
    SEARCH_TIMEOUT = 30.seconds
    MAX_SEARCH_RESULTS = 10

    @memory_cache : String?

    def initialize
      Dir.mkdir_p(MEMORY_DIR) unless Dir.exists?(MEMORY_DIR)
      ensure_memory_file_exists
    end

    def process_tool_calls(response : String) : String
      result = response.dup

      if match = result.match(/<read>(.*?)<\/read>/m)
        file_path = match[1].strip
        file_content = read_file(file_path)
        result = result.gsub(/<read>.*?<\/read>/m, file_content)
      end

      if match = result.match(/<memory>(.*?)<\/memory>/m)
        memory_content = match[1].strip
        write_to_memory(memory_content, append: false)
        result = result.gsub(/<memory>.*?<\/memory>/m, "I've remembered that.")
      end

      if match = result.match(/<memory append>(.*?)<\/memory append>/m)
        memory_content = match[1].strip
        write_to_memory(memory_content, append: true)
        result = result.gsub(/<memory append>.*?<\/memory append>/m, "I've updated my memory.")
      end

      if match = result.match(/<search>(.*?)<\/search>/m)
        query = match[1].strip
        search_results = web_search(query)
        result = result.gsub(/<search>.*?<\/search>/m, search_results)
      end

      result
    end

    def read_file(path : String) : String
      if path.includes?("..")
        return "Error: Cannot read files outside the current directory."
      end

      full_path = File.expand_path(path)

      cwd = File.expand_path(".")
      unless full_path.starts_with?(cwd)
        return "Error: Cannot read files outside the current directory."
      end

      unless File.exists?(full_path)
        return "Error: File not found: #{path}"
      end

      unless File.file?(full_path)
        return "Error: Path is a directory, not a file: #{path}"
      end

      file_size = File.size(full_path)
      if file_size > 13 * 1024 * 1024
        return "Error: File too large (#{file_size / (1024 * 1024)}MB). Maximum 13MB."
      end

      begin
        content = File.read(full_path)
        return content
      rescue ex
        return "Error: Could not read file: #{ex.message}"
      end
    end

    def web_search(query : String) : String
      encoded_query = URI.encode_www_form(query)
      url = "https://html.duckduckgo.com/html/?q=#{encoded_query}"

      begin
        client = HTTP::Client.new("html.duckduckgo.com", tls: true)
        client.read_timeout = SEARCH_TIMEOUT
        client.connect_timeout = SEARCH_TIMEOUT

        response = client.get("/html/?q=#{encoded_query}", headers: HTTP::Headers{
          "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
          "Accept" => "text/html,application/xhtml+xml",
          "Accept-Language" => "en-US,en;q=0.9",
        })

        client.close

        if response.status_code == 200
          results = parse_search_results(response.body)
          if results.empty?
            return "No results found for: #{query}"
          end
          return format_search_results(results, query)
        else
          return "Search failed with HTTP status: #{response.status_code}"
        end
      rescue ex : IO::Timeout
        return "Search timed out after #{SEARCH_TIMEOUT.total_seconds} seconds. Please try a more specific query."
      rescue ex
        return "Search error: #{ex.message}"
      end
    end

    private def parse_search_results(html : String) : Array({title: String, url: String, snippet: String})
      results = [] of {title: String, url: String, snippet: String}

      title_pattern = /<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/
      snippet_pattern = /<a[^>]*class="result__snippet"[^>]*>([^<]+)<\/a>/

      titles = [] of {url: String, title: String}
      html.scan(title_pattern) do |match|
        url = match[1].to_s
        title = match[2].to_s.gsub(/<\/?[^>]*>/, "").strip
        if !url.empty? && !title.empty? && !url.includes?("duckduckgo.com")
          titles << {url: url, title: title}
        end
      end

      snippets = [] of String
      html.scan(snippet_pattern) do |match|
        snippet = match[1].to_s.gsub(/<\/?[^>]*>/, "").strip
        snippets << snippet if !snippet.empty?
      end

      titles.each_with_index do |item, i|
        snippet = i < snippets.size ? snippets[i] : ""
        results << {title: item[:title], url: item[:url], snippet: snippet}
        break if results.size >= MAX_SEARCH_RESULTS
      end

      results
    end

    private def format_search_results(results : Array({title: String, url: String, snippet: String}), query : String) : String
      output = String::Builder.new
      output << "Search results for: #{query}\n\n"

      results.each_with_index do |result, i|
        output << "#{i + 1}. #{result[:title]}\n"
        output << "   URL: #{result[:url]}\n"
        output << "   #{result[:snippet]}\n\n"
      end

      output << "---\n"
      output << "Found #{results.size} result(s). Use these to answer the user's question.\n"

      output.to_s
    end

    def load_user_memory : String
      if File.exists?(MEMORY_FILE)
        content = File.read(MEMORY_FILE)
        @memory_cache = content
        return content
      end
      ""
    end

    def write_to_memory(content : String, append : Bool = false)
      if append && File.exists?(MEMORY_FILE)
        File.open(MEMORY_FILE, "a") do |file|
          file.puts "\n#{content}"
        end
      else
        File.write(MEMORY_FILE, content)
      end
      @memory_cache = nil
    end

    def append_fact(fact : String)
      timestamp = Time.now.to_s("%Y-%m-%d %H:%M:%S")
      File.open(MEMORY_FILE, "a") do |file|
        file.puts "\n[#{timestamp}] #{fact}"
      end
      @memory_cache = nil
    end

    def memory_for_prompt : String
      memory = load_user_memory
      return "" if memory.empty?

      <<-MEMORY
## Information I know about the user:
#{memory}

Note: This information was provided by the user in previous conversations.
To update this information, output <memory>new fact</memory> or <memory append>additional fact</memory append>.

      MEMORY
    end

    def clear_memory
      File.delete(MEMORY_FILE) if File.exists?(MEMORY_FILE)
      @memory_cache = nil
    end

    private def ensure_memory_file_exists
      return if File.exists?(MEMORY_FILE)

      header = <<-HEADER
# User Memory File for speak
# 
# This file contains information the AI has learned about you.
# You can edit this file directly to add, remove, or correct facts.
# The AI will read this file at the start of every conversation.
#
# Format: Use plain text. Each line is a separate fact.
# Example:
# Name: Sarah
# Role: Software Engineer
# Preference: Prefers concise answers
#
HEADER
      File.write(MEMORY_FILE, header)
    end
  end
end
