class CreateMessages < ActiveRecord::Migration
  def change
    create_table :messages do |t|
      t.string :from_did, :null => false, :limit => 20
      t.string :from_sha256, :null => false, :limit => 45
      t.string :to_did, :null => false, :limit => 20
      t.string :to_sha256, :null => false, :limit => 45
      t.text :message, :null => false, :limit => 64.kilobytes + 1
      t.timestamps
    end
  end
end
