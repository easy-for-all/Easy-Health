class AddTimeZoneToUsers < ActiveRecord::Migration[8.1]
  def change
    # IANA time zone name (e.g. "America/Sao_Paulo"). Source of truth for
    # scheduling activation push at the user's local preferred workout time.
    add_column :users, :time_zone, :string
  end
end
