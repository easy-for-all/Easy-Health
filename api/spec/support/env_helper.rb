module EnvHelper
  def with_env(vars)
    previous = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end

RSpec.configure do |config|
  config.include EnvHelper
end
