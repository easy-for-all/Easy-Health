class AddSignupSourceToUsers < ActiveRecord::Migration[8.1]
  # signup_source = the platform OBSERVED at the moment the account was created
  # (the X-Platform header on the sign_up request, or omniauth.params on the
  # Google web flow). Creation-time and write-once by construction: no code path
  # after the create ever writes this column.
  #
  # It is NOT activation_platform, which is the platform of the FIRST product
  # analytics event — later than the signup and null on most accounts. And it is
  # NOT consent_source, which is hardcoded "web" in two of the three creation
  # sites and therefore answers a different (wrong) question.
  #
  # Accounts created before this migration stay "unknown". There is deliberately
  # no backfill: no existing signal can tell where an old account was created
  # from, and a heuristic one would produce a number that looks trustworthy and
  # is not.
  def change
    add_column :users, :signup_source, :string, default: "unknown", null: false

    # created_at FIRST. Every query in the admin cohort view restricts created_at
    # (a range) and at most filters signup_source (equality over 4 values — poor
    # selectivity as a leading column). With this order the per-source summary is
    # a range scan, and the listing gets its ORDER BY users.created_at DESC for
    # free: users has no index on created_at today, even though every admin page
    # load sorts by it.
    add_index :users, [ :created_at, :signup_source ]
  end
end
