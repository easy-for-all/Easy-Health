class MakePendingDeliveryRetry
  def self.call(scope:, batch: true)
    new(scope:, batch:).call
  end

  def initialize(scope:, batch:)
    @scope = scope
    @batch = batch
  end

  def call
    stats = { considered: 0, delivered: 0, failed: 0 }

    each_event do |event|
      stats[:considered] += 1
      result = MakeWebhookClient.new.deliver(event)
      result.success? ? stats[:delivered] += 1 : stats[:failed] += 1
    rescue StandardError
      stats[:failed] += 1
    end

    stats
  end

  private

  attr_reader :scope, :batch

  def each_event(&block)
    batch ? scope.find_each(&block) : scope.each(&block)
  end
end
