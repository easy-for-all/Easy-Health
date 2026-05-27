# frozen_string_literal: true

# Only mounted in non-production environments (see routes.rb)
module Api
  module V1
    class DebugController < ActionController::API
      def sentry_test
        raise "Sentry test error — triggered manually at #{Time.current.iso8601}"
      end
    end
  end
end
