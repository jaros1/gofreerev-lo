class VerifyGiftsAddColumnMid < ActiveRecord::Migration
  def change
    add_column :verify_gifts, :mid, :integer
  end
end
