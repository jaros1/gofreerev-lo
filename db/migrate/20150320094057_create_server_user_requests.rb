class CreateServerUserRequests < ActiveRecord::Migration
  def change
    create_table :server_user_requests do |t|
      t.integer :user_id, :null => false
      t.string :sha256, :limit => 45, :null => false
      t.timestamps
    end
  end
end
