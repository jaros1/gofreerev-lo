class PingsAddColumnUid < ActiveRecord::Migration
  def change
    add_column :pings, :uid, :string
  end
end
