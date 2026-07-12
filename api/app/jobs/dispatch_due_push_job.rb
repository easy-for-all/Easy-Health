# Sends all NotificationDeliveries whose scheduled_for has arrived. Synchronous
# send inside the cron sweep (see lib/tasks/push_activation.rake) — avoids relying
# on a durable background queue.
class DispatchDuePushJob < ApplicationJob
  queue_as :default

  def perform(limit: 500)
    stats = PushDispatchService.dispatch_due(limit: limit)
    Rails.logger.info("[DispatchDuePushJob] #{stats.inspect}")
    stats
  end
end
