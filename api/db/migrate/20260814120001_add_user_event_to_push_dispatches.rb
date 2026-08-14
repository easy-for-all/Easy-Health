# Materializes the correlation UserEvent -> PushDispatch.
#
# The intent already existed: Make echoes back the payload's event_id, and
# EventDeliveryCallbacksController already reads it as a UserEvent id. But it
# lived in a plain string column with no FK and no index, so the pipeline
# (event -> Make delivery -> dispatch -> provider result) could not be joined.
#
# campaign_key is deliberately NOT used for this. It belongs to the campaign and
# copy, which Make owns and may version freely ("first-workout-completed-v1"),
# so it is a reporting dimension, never a relational key.
#
# Nullable because a dispatch can legitimately arrive without a resolvable
# event; those show as "not correlated" in the admin instead of being dropped.
class AddUserEventToPushDispatches < ActiveRecord::Migration[8.1]
  def change
    add_reference :push_dispatches, :user_event, type: :bigint, null: true,
                  foreign_key: { on_delete: :nullify }, index: true
  end
end
