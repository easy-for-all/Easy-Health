module Api
  module V1
    module Personal
      class BaseController < Api::V1::BaseController
        before_action :require_personal_trainer!
      end
    end
  end
end
