require "json"
require "./system"


module Speak
    struct DetectedRam
        include JSON::Serializable

        property total_ram_mb : UInt64
        property available_ram_mb : UInt64
        property os_reserved_ram_mb : UInt64
    end

    struct ActiveSettings
        include JSON::Serializable

        property cpu_cores : Int32
        property has_avx2 : Bool
        property free_disk_space_mb : UInt64
        property context_size : Int32
        property kv_cache_type : String
        property model_quant : String
        property model_file : String
        property temperature : Float32
        property max_tokens : Int32
    end

    struct UserOverrides
        include JSON::Serializable

        property os_reserved_ram_mb : UInt64?
        property context_size : Int32?
        property kv_cache_type : String?
        property model_quant : String?
        property max_tokens : Int32?
        property temperature : Float32?
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
               config = config_from_json(Config, json)
                config.refresh_detected
                config.save(path)
                return config
            else
                config = Config.detect_and_create
                dir = File.dirname(path)
                File.mkdir_p(dir) unless File.directory?(dir)
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
                System.cpu_has_avx2,
                System.free_disk_space_mb("/"),
                System.recommended_context_size,
                System.kv_cache_type,
                System.recommended_quant,
                System.recommended_model_file,
                0.7, # default temperature
                512 # default max tokens
            )

            user_overrides = UserOverrides.new(
                nil, nil, nil, nil, nil, nil
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
            @active.has_avx2,
            @active.free_disk_space_mb,
            @user_overrides.context_size? || @active.context_size,
            @user_overrides.kv_cache_type? || @active.kv_cache_type,
            @user_overrides.model_quant? || @active.model_quant,
            @user_overrides.model_file? || @active.model_file,
            @user_overrides.temperature? || @active.temperature,
            @user_overrides.max_tokens? || @active.max_tokens
          )
          return result
        end

        def save(path : String = "./speak/config.json")
            dir = File.dirname(path)
            File.mkdir_p(dir) unless File.directory?(dir)
            json_string = self.to_pretty_json
            File.write(path, json_string)
        end

        private def self.config_from_json(type, json_string)
            JSON.parse(json_string, type: type)
        end
    end
end
