class VerifyGiftsAddColumnDirection < ActiveRecord::Migration
  def up
    add_column :verify_gifts, :direction, :string, :limit => 10
  end
  def down
    remove_column :verify_gifts, :direction
  end
end
