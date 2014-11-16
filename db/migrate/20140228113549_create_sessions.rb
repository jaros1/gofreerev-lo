class CreateSessions < ActiveRecord::Migration
  def change
    create_table :sessions do |t|
      t.string :session_id, :limit => 32
      t.integer :last_row_id
      t.float :last_row_at
      t.timestamps
    end
    add_index "sessions", ["session_id"], name: "index_session_session_id", unique: true
  end
end
