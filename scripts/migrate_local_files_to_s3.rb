#!/usr/bin/env ruby
# Migrates ActiveStorage blobs from local disk to S3.
#
# Prerequisites:
#   1. S3 env vars must be set (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_BUCKET)
#   2. production.rb must temporarily point to a Mirror service (local + s3) OR
#      run this with RAILS_ENV=production after configuring a temporary Mirror service.
#
# Usage (from repo root, on the production server):
#   RAILS_ENV=production ruby scripts/migrate_local_files_to_s3.rb
#
# The script reads files from the local disk service and uploads them to S3.
# Local files are NOT deleted automatically. Verify S3 objects before cleaning up.

require_relative "../api/config/environment"

local_service = ActiveStorage::Blob.services.fetch(:local)
s3_service    = ActiveStorage::Blob.services.fetch(:easyhealth_s3)

storage_path = Rails.root.join("storage")

unless Dir.exist?(storage_path)
  puts "Local storage directory not found: #{storage_path}"
  puts "Nothing to migrate."
  exit 0
end

local_files = Dir[storage_path.join("**", "*")].reject { |f| File.directory?(f) }

if local_files.empty?
  puts "No local files found in #{storage_path}. Nothing to migrate."
  exit 0
end

puts "Found #{local_files.size} local file(s). Starting migration to S3..."
puts "Bucket: #{ENV['AWS_BUCKET']} | Region: #{ENV['AWS_REGION']}"
puts "-" * 60

counts = { success: 0, error: 0, skipped: 0 }

ActiveStorage::Blob.find_each do |blob|
  local_path = begin
    local_service.path_for(blob.key)
  rescue StandardError
    nil
  end

  unless local_path && File.exist?(local_path)
    counts[:skipped] += 1
    next
  end

  begin
    File.open(local_path, "rb") do |io|
      unless s3_service.exist?(blob.key)
        s3_service.upload(blob.key, io, checksum: blob.checksum,
                                        content_type: blob.content_type,
                                        disposition: "inline",
                                        filename: blob.filename)
      end
    end
    counts[:success] += 1
    puts "OK  #{blob.key} (#{blob.filename})"
  rescue StandardError => e
    counts[:error] += 1
    puts "ERR #{blob.key} — #{e.message}"
  end
end

puts "-" * 60
puts "Migration complete:"
puts "  Uploaded : #{counts[:success]}"
puts "  Errors   : #{counts[:error]}"
puts "  Skipped  : #{counts[:skipped]} (no local file found)"
puts ""
puts "LOCAL FILES WERE NOT DELETED. Verify S3 objects before removing local volume."

exit(counts[:error] > 0 ? 1 : 0)
