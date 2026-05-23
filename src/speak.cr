require "llama"
require "./system"
require "./config"

def main
config = Speak::Config.load_or_create

setting = config.apply_overrides

model_path = "./speak/models/#{setting.model_file}"
if File.exists?(model_path)
    puts "Loading model: #{model_path}"
    llama = Llama::Model.new(model_path, setting.model_quant)
else
    puts "Model file not found: #{model_path}, installing"
    install = Speak::Install.new
    install.install_model(setting.model_quant)
     if File.exists?(model_path)
        puts "Model installed successfully: #{model_path}"
        model = Llama::Model.new(model_path)
     else
        puts "Failed to install model: #{model_path}"
         exit(1)
     end
end
context = Llama::Context.new(
   model: model,
   n_ctx: setting.context_size,
   kv_cache_type: setting.kv_cache_type
)
launch = Speak::Launch.new(context, setting)
launch.run
end

main