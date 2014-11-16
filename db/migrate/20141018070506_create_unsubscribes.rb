class CreateUnsubscribes < ActiveRecord::Migration
  def change
    create_table :unsubscribes do |t|
      t.string :email, :null => false
      t.string :user_id, :limit => 40
      t.timestamps
    end
  end
end
