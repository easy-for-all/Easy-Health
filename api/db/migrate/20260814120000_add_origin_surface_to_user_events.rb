# The surface/process that produced a UserEvent — android, web,
# backend_scheduler, admin. A column rather than a metadata key because the
# admin groups by it: GROUP BY metadata->>'origin_surface' cannot use a plain
# b-tree index and would need an expression index to stay fast.
#
# Nullable with no default and no backfill: historical rows genuinely do not
# know their origin, and inferring one (e.g. from a device token, which only
# proves the user CAN receive push) would invent data. NULL reads as "unknown".
class AddOriginSurfaceToUserEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :user_events, :origin_surface, :string
    add_index :user_events, [ :origin_surface, :created_at ]
  end
end
