if Rails.env.production?
  %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET].each do |var|
    if ENV[var].blank?
      Rails.logger.warn "Missing environment variable: #{var}. Active Storage S3 will not work without it."
    end
  end
end
