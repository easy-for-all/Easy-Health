class Rack::Attack
  # General throttle: 300 requests per 5 minutes per IP
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Brute-force protection on login: 10 attempts per minute per IP
  throttle("login/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/rails/users/sign_in" && req.post?
  end

  # Registration spam protection: 5 attempts per minute per IP
  throttle("signup/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/rails/users" && req.post?
  end

  self.throttled_responder = lambda do |_req|
    [
      429,
      { "Content-Type" => "application/json" },
      [ '{"error":"Too Many Requests"}' ]
    ]
  end
end
