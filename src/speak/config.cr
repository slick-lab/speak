require "json"
require "./system"

module Speak
  struct DetectedRam
    include JSON::Serializable

    property total_ram_mb : UInt64
    property available_ram_mb : UInt64
    property os_reserved_ram_mb : UInt64

    def initialize(@total_ram_mb, @available_ram_mb, @os_reserved_ram_mb)
    end
  end

  struct ActiveSettings
    include JSON::Serializable

    property cpu_cores : Int32
    property free_disk_space_mb : UInt64
    property context_size : Int32
    property kv_cache_type : String
    property model_quant : String
    property model_file : String
    property temperature : Float32
    property max_tokens : Int32

    def initialize(@cpu_cores, @free_disk_space_mb, @context_size, @kv_cache_type, @model_quant, @model_file, @temperature, @max_tokens)
    end
  end

  struct UserOverrides
    include JSON::Serializable

    property os_reserved_ram_mb : UInt64?
    property context_size : Int32?
    property kv_cache_type : String?
    property model_quant : String?
    property max_tokens : Int32?
    property temperature : Float32?
    property model_file : String?

    def initialize(@os_reserved_ram_mb, @context_size, @kv_cache_type, @model_quant, @max_tokens, @temperature)
    end
  end

  class Config
    include JSON::Serializable

    property detected : DetectedRam
    property active : ActiveSettings
    property user_overrides : UserOverrides

    def initialize(@detected, @active, @user_overrides)
    end

    def self.load_or_create(path : String = "./speak/config.json") : Config
      if File.exists?(path)
        json = File.read(path)
        config = Config.from_json(json)
        config.refresh_detected
        config.save(path)
        return config
      else
        config = Config.detect_and_create
        dir = File.dirname(path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)
        config.save(path)
        return config
      end
    end

    def self.detect_and_create : Config
      detected = DetectedRam.new(
        System.total_ram_mb,
        System.available_ram_mb,
        System.os_reserved_ram_mb
      )

      active = ActiveSettings.new(
        System.cpu_cores,
        System.free_disk_space_mb("/"),
        System.recommended_context_size,
        System.kv_cache_type,
        System.recommended_quant,
        System.model_file,
        0.7,
        512
      )

      user_overrides = UserOverrides.new(
        os_reserved_ram_mb = nil,
        context_size = nil,
        kv_cache_type = nil,
        model_quant = nil,
        max_tokens = nil,
        temperature = nil
      )

      return Config.new(detected, active, user_overrides)
    end

    def refresh_detected
      @detected.total_ram_mb = System.total_ram_mb
      @detected.available_ram_mb = System.available_ram_mb
      @detected.os_reserved_ram_mb = System.os_reserved_ram_mb
    end

    def apply_overrides : ActiveSettings
      result = ActiveSettings.new(
        @active.cpu_cores,
        @active.free_disk_space_mb,
        @user_overrides.context_size || @active.context_size,
        @user_overrides.kv_cache_type || @active.kv_cache_type,
        @user_overrides.model_quant || @active.model_quant,
        @user_overrides.model_file || @active.model_file,
        @user_overrides.temperature || @active.temperature,
        @user_overrides.max_tokens || @active.max_tokens
      )
      return result
    end

    def save(path : String = "./speak/config.json")
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      json_string = self.to_pretty_json
      File.write(path, json_string)
    end
  end
end
