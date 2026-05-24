# launch.cr - Terminal chat interface for speak
# Handles user input, streaming output, tool processing, and memory management

require "llama"
require "./config"
require "./disk"
require "./tool"

module Speak
  class Launch
    @disk_cache : DiskCache
    @tool : Tool
    @settings : ActiveSettings
    @history : Array({role: String, content: String})
    @running : Bool
    @system_prompt : String

    def initialize(context : Llama::Context, model : Llama::Model, @settings : ActiveSettings)
      @disk_cache = DiskCache.new(context, @settings, model.vocab)
      @tool = Tool.new
      @history = [] of {role: String, content: String}
      @running = true
      @system_prompt = load_system_prompt
      load_conversation_history
    end

    def run
      show_header
      input_loop
      save_conversation_history
      puts "\nGoodbye."
    end

    private def input_loop
      while @running
        print "\n> "
        input = gets || ""
        input = input.strip

        case input.downcase
        when "exit", "quit"
          @running = false
        when "clear"
          clear_screen
          show_header
        when "history"
          show_history
        when "save"
          save_conversation_history
          puts "Conversation saved."
        when "memory"
          show_memory
        when "clearmemory"
          @tool.clear_memory
          puts "Memory cleared."
        else
          next if input.empty?
          process_user_input(input)
        end
      end
    end

    private def process_user_input(input : String)
      @history << {role: "user", content: input}

      prompt = build_prompt(input)

      print "\nspeak: "
      response = String::Builder.new

      @disk_cache.generate(prompt) do |token|
        print token
        response << token
        STDOUT.flush
      end

      full_response = response.to_s.strip

      full_response = @tool.process_tool_calls(full_response)

      puts "\n" unless full_response.empty?

      @history << {role: "assistant", content: full_response}
      save_conversation_history
    end

    private def build_prompt(user_input : String) : String
      prompt = String::Builder.new
      prompt << @system_prompt << "\n\n"

      user_memory = @tool.memory_for_prompt
      prompt << user_memory << "\n" unless user_memory.empty?

      prompt << "## Available tools:\n"
      prompt << "- <read>file_path</read> - Read a file and return its contents\n"
      prompt << "- <search>query</search> - Search the web for current information (max 10 results, 30 second timeout)\n"
      prompt << "- <memory>fact</memory> - Remember a fact about the user\n"
      prompt << "- <memory append>fact</memory append> - Add to an existing memory\n\n"

      prompt << "## Conversation history:\n"

      max_history = 20
      recent = @history.last(max_history)

      recent.each do |msg|
        role = msg[:role] == "user" ? "User" : "Assistant"
        prompt << "#{role}: #{msg[:content]}\n"
      end

      prompt << "\nUser: #{user_input}\nAssistant:"

      prompt.to_s
    end

    private def load_system_prompt : String
      {{ read_file("#{__DIR__}/system_prompt.txt") }}
    end

    private def save_conversation_history
      return if @history.empty?

      Dir.mkdir_p("./speak/history") unless Dir.exists?("./speak/history")

      timestamp = Time.utc.to_s("%Y%m%d_%H%M%S")
      history_file = "./speak/history/chat_#{timestamp}.json"

      history_json = @history.map do |msg|
        {role: msg[:role], content: msg[:content]}
      end.to_json

      File.write(history_file, history_json)
      File.write("./speak/history/latest.json", history_json)
    end

    private def load_conversation_history
      latest_file = "./speak/history/latest.json"
      return unless File.exists?(latest_file)

      begin
        data = File.read(latest_file)
        loaded = Array({role: String, content: String}).from_json(data)
        @history = loaded
        puts "\n[Loaded previous conversation with #{@history.size} messages]"
      rescue
      end
    end

    private def show_header
      clear_screen
      puts "=" * 70
      puts "speak - Local AI Assistant".center(70)
      puts "=" * 70
      puts "Model: #{@settings.model_file}"
      puts "Context: #{@settings.context_size} tokens"
      puts "KV Cache: #{@settings.kv_cache_type}"

      memory_content = @tool.load_user_memory
      memory_size = memory_content.bytesize
      puts "Memory: #{memory_size} bytes (#{memory_content.lines.size} lines)"

      puts "=" * 70
      puts "Commands: exit, clear, history, save, memory, clearmemory"
      puts "Tools: <read>file</read> | <search>query</search> | <memory>fact</memory>"
      puts "=" * 70
    end

    private def show_history
      return puts("\nNo conversation history.") if @history.empty?

      puts "\n" + "=" * 70
      puts "Conversation History".center(70)
      puts "=" * 70

      @history.each_with_index do |msg, i|
        role = msg[:role].capitalize
        content = msg[:content]

        if content.size > 80
          content = content[0, 77] + "..."
        end

        puts "[#{i + 1}] #{role}: #{content}"
      end

      puts "=" * 70
      puts "Total: #{@history.size} messages"
    end

    private def show_memory
      memory = @tool.load_user_memory

      if memory.empty?
        puts "\nNo memory stored yet."
        puts "The AI will remember facts when you say things like:"
        puts "  'I'm a software engineer'"
        puts "  'My name is Sarah'"
        puts "  'I prefer short answers'"
      else
        puts "\n" + "=" * 70
        puts "User Memory".center(70)
        puts "=" * 70
        puts memory
        puts "=" * 70
        puts "\nYou can edit this file directly: #{Tool::MEMORY_FILE}"
      end
    end

    private def clear_screen
      print "\e[2J\e[H"
    end
  end
end
