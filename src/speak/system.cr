require "c/sys/statvfs"
module Speak
    module System
        def self.total_ram_mb : UInt64
            meminfo = File.read("/proc/meminfo")
            if match = meminfo.match(/MemTotal:\s+(\d+)/)
                return match[1].to_u64 / 1024
            end
            return 8192_u64
        end
        
        def self.available_ram_mb : UInt64
            meminfo = File.read("/proc/meminfo")
            if match = meminfo.match(/MemAvailable:\s+(\d+)/)
                return match[1].to_u64 / 1024
            end
            if match = meminfo.match(/MemFree:\s+(\d+)/)
                return match[1].to_u64 / 1024
            end
            return 4096_u64
        end

        def self.process_ram_mb : UInt64
            statm = File.read("/proc/self/statm")
            parts = statm.split
            if parts.size >= 2
                page_size = 4096_u64
                resident_pages = parts[1].to_u64
                return (resident_pages * page_size) / (1024 * 1024)
            end
            return 100_u64
        end

        def self.cpu_cores : Int32
            cpuinfo = File.read("/proc/cpuinfo") do |cpu|
                count += 1 if cpu.start_with?("processor")
            end
            return count if count > 0
            return 4
        end

        def self.cpu_has_avx2 : Bool
            cpuinfo = File.read("/proc/cpuinfo") do |avx|
                if avx.start_with?("flags")
                    return true if avx.include?("avx2")
                end
            end
            return false
        end

       def self.free_disk_space_mb(path : String) : UInt64
         stat = uninitialized LibC::StatVfs
          if LibC.statvfs(path, pointerof(stat)) == 0
           free_blocks = stat.f_bavail
           block_size = stat.f_bsize
           return (free_blocks * block_size) / (1024_u64 * 1024_u64)
         end
         return 0_u64
         end
        
        def self.ram_tier : Symbol
            total_ram = total_ram_mb
            case total_ram
            when 0..4096
                return :ultra_low
            when 4096...6144
                return :low
            when 6144...8192
                return :medium
            else
                return :high
            end
        end

        def self.os_reserved_ram_mb : UInt64
            total = total_ram_mb
            case total
            when 0..4096
                return 256_u64
            when 4096...6144
                return 512_u64
            when 6144...8192
                return 1024_u64
            else
                return 2048_u64
            end
        end

        def self.recommended_quant : String
            avail = available_ram_mb
            case avail
            when 0...3000
                return "Q2_K"
            when 3000...6000
                return "Q4_K_M"
            else
                return "Q6_K"
            end
        end

        def self.recommended_context_size : Int32
            avail = available_ram_mb
           case avail
            when 0...3000
                return 512
            when 3000...6000
                return 1024
            else
                return 8192
            end
        end

        def self.model_file : String
            quant = recommended_quant
            case quant
            when "Q2_K"
                return "nanbiege-3b-q2_k.gguf"
            when "Q4_K_M"
                return "nanbiege-3b-q4_k_m.gguf"
            else
                return "nanbiege-3b-q6_k.gguf"
            end
        end

        def self.kv_cache_type : String
            avail = available_ram_mb
            if avail < 6000
                return "memory"
            else
                return "disk"
            end
        end
    end
end