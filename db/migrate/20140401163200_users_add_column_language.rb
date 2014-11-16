class UsersAddColumnLanguage < ActiveRecord::Migration
  def change
    add_column :users, :language, :string, :limit => 2
  end
end
