class SessionsAddColumnSha256 < ActiveRecord::Migration
  def up
    add_column :sessions, :sha256, :string, :limit => 45
  end
  def down
    remove_column :sessions, :sha256
  end
end
