class VerifyGiftsRenameMidAndMore < ActiveRecord::Migration
  def up
    rename_column :verify_gifts, :mid, :request_mid
    add_column :verify_gifts, :response_mid, :integer
  end
  def down
    remove_column :verify_gifts, :response_mid
    rename_column :verify_gifts, :request_mid, :mid
  end
end
