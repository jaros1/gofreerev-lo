class GiftsAddIndexOnStatusUpdateAt < ActiveRecord::Migration
  def change
    add_index "gifts", ["status_update_at"], name: "index_gifts_on_status_updateat", unique: true
  end
end
