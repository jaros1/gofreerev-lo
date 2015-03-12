class CreateServers < ActiveRecord::Migration
  def change
    create_table :servers do |t|
      t.string :url
      t.timestamps
    end
    add_index "servers", ["url"], name: "index_servers_url", unique: true, using: :btree
  end
end
