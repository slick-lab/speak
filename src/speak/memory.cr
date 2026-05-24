require "json"
require "digest/sha1"

module Speak
  class AgentMemory
    MEMORY_DIR = "./speak/agent_memory"
    EPISODIC_DIR = "#{MEMORY_DIR}/episodic"
    SEMANTIC_DIR = "#{MEMORY_DIR}/semantic"
    WORKING_MEMORY_FILE = "#{MEMORY_DIR}/working.json"
    @session_id : String
    @working : WorkingMemory
    @episodic_cache : Array(EpisodicMemory)?

    struct WorkingMemory
      include JSON::Serializable
      property current_goal : String
      property current_step : Int32
      property steps : Array(String)
      property tool_history : Array(ToolCallRecord)
      property observations : Array(String)

      def initialize
        @current_goal = ""
        @current_step = 0
        @steps = [] of String
        @tool_history = [] of ToolCallRecord
        @observations = [] of String
      end
    end

    struct ToolCallRecord
      include JSON::Serializable
      property tool_name : String
      property arguments : String
      property result : String
      property timestamp : Int64
      property step_number : Int32

      def initialize(@tool_name, @arguments, @result, @timestamp, @step_number)
      end
    end

    struct EpisodicMemory
      include JSON::Serializable
      property id : String
      property session_id : String
      property timestamp : Int64
      property user_input : String
      property assistant_response : String
      property tool_calls : Array(ToolCallRecord)
      property outcome : String  # "success", "failure", "partial"

      def initialize(@id, @session_id, @timestamp, @user_input, @assistant_response, @tool_calls, @outcome)
      end
    end

    struct SemanticMemory
      include JSON::Serializable
      property fact : String
      property source : String  # "user", "observation", "inference"
      property confidence : Float64
      property timestamp : Int64

      def initialize(@fact, @source, @confidence = 1.0, @timestamp = Time.utc.to_unix)
      end
    end

    def initialize
      Dir.mkdir_p(EPISODIC_DIR) unless Dir.exists?(EPISODIC_DIR)
      Dir.mkdir_p(SEMANTIC_DIR) unless Dir.exists?(SEMANTIC_DIR)
      @session_id = generate_session_id
      @working = load_working_memory
    end

    def generate_session_id : String
      Digest::SHA1.hexdigest(Time.utc.to_unix.to_s)[0, 8]
    end

    def load_working_memory : WorkingMemory
      if File.exists?(WORKING_MEMORY_FILE)
        data = File.read(WORKING_MEMORY_FILE)
        WorkingMemory.from_json(data)
      else
        WorkingMemory.new
      end
    end

    def save_working_memory
      File.write(WORKING_MEMORY_FILE, @working.to_json)
    end

    def reset_working_memory
      @working = WorkingMemory.new
      save_working_memory
    end

    def set_goal(goal : String, steps : Array(String))
      @working.current_goal = goal
      @working.steps = steps
      @working.current_step = 0
      save_working_memory
    end

    def advance_step
      @working.current_step += 1
      save_working_memory
    end

    def get_current_step : String?
      return nil if @working.current_step >= @working.steps.size
      @working.steps[@working.current_step]
    end

    def is_goal_complete? : Bool
      @working.current_step >= @working.steps.size && @working.steps.size > 0
    end

    def record_tool_call(tool_name : String, arguments : String, result : String)
      record = ToolCallRecord.new(
        tool_name,
        arguments,
        result,
        Time.utc.to_unix,
        @working.current_step
      )
      @working.tool_history << record
      save_working_memory
      record
    end

    def add_observation(observation : String)
      @working.observations << observation
      save_working_memory
    end

    def get_tool_history_for_current_step : Array(ToolCallRecord)
      @working.tool_history.select { |t| t.step_number == @working.current_step }
    end

    def get_all_tool_history : Array(ToolCallRecord)
      @working.tool_history
    end

    def get_tool_results_for_step(step_number : Int32) : Array(String)
      @working.tool_history.select { |t| t.step_number == step_number }.map(&.result)
    end

    def save_episodic_memory(user_input : String, assistant_response : String, outcome : String)
      id = Digest::SHA1.hexdigest("#{@session_id}#{Time.utc.to_unix}")[0, 16]
      memory = EpisodicMemory.new(
        id,
        @session_id,
        Time.utc.to_unix,
        user_input,
        assistant_response,
        @working.tool_history.dup,
        outcome
      )
      File.write("#{EPISODIC_DIR}/#{id}.json", memory.to_json)
    end

    def load_recent_episodes(limit : Int32 = 10) : Array(EpisodicMemory)
      episodes = [] of EpisodicMemory
      Dir.glob("#{EPISODIC_DIR}/*.json").sort.reverse.each do |file|
        break if episodes.size >= limit
        data = File.read(file)
        episodes << EpisodicMemory.from_json(data)
      end
      episodes
    end

    def save_semantic_fact(fact : String, source : String = "observation", confidence : Float64 = 1.0)
      memory = SemanticMemory.new(fact, source, confidence)
      id = Digest::SHA1.hexdigest(fact)[0, 16]
      File.write("#{SEMANTIC_DIR}/#{id}.json", memory.to_json)
    end

    def recall_semantic_facts(query : String, limit : Int32 = 5) : Array(SemanticMemory)
      facts = [] of SemanticMemory
      Dir.glob("#{SEMANTIC_DIR}/*.json").each do |file|
        data = File.read(file)
        fact = SemanticMemory.from_json(data)
        if fact.fact.includes?(query) || query.includes?(fact.fact.split.first(3).join(" "))
          facts << fact
        end
      end
      facts.sort_by! { |f| -f.confidence }.first(limit)
    end

    def get_working_summary : String
      summary = String::Builder.new
      summary << "Current Goal: #{@working.current_goal}\n"
      summary << "Progress: Step #{@working.current_step + 1} of #{@working.steps.size}\n"
      summary << "Steps:\n"
      @working.steps.each_with_index do |step, i|
        marker = i == @working.current_step ? "→" : " "
        summary << "#{marker} #{i + 1}. #{step}\n"
      end
      summary << "\nObservations:\n"
      @working.observations.last(5).each do |obs|
        summary << "- #{obs}\n"
      end
      summary.to_s
    end

    def build_memory_prompt : String
      prompt = String::Builder.new
      prompt << "## Working Memory\n"
      prompt << get_working_summary
      prompt << "\n## Recent Tool Calls\n"
      @working.tool_history.last(5).each do |tool|
        prompt << "- #{tool.tool_name}: #{tool.result[0..100]}...\n"
      end
      prompt << "\n## Known Facts\n"
      recall_semantic_facts("", 5).each do |fact|
        prompt << "- #{fact.fact}\n"
      end
      prompt.to_s
    end

    def clear_session
      @working = WorkingMemory.new
      save_working_memory
    end
  end
end
