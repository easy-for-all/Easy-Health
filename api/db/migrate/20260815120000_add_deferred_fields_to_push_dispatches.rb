class AddDeferredFieldsToPushDispatches < ActiveRecord::Migration[8.1]
  def change
    add_column :push_dispatches, :next_allowed_at, :datetime

    add_index :push_dispatches, [ :status, :next_allowed_at ],
              name: "index_push_dispatches_deferred_due",
              where: "status = 'deferred'"
  end
end
