class VerifyGiftsChangeClientSidAndClientSha256ToNull < ActiveRecord::Migration

  # create_table "verify_gifts", force: true do |t|
  #   t.string   "client_sid",              limit: 20, null: false
  #   t.string   "client_sha256",           limit: 45, null: false

  def up
    change_column :verify_gifts, :client_sid, :string, :limit => 20, :null => true
    change_column :verify_gifts, :client_sha256, :string, :limit => 45, :null => true
  end
  def down
    change_column :verify_gifts, :client_sid, :string, :limit => 20, :null => false
    change_column :verify_gifts, :client_sha256, :string, :limit => 45, :null => false
  end
end
