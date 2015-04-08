class ServersAddColumnLastChangedUserSha256At < ActiveRecord::Migration
  def change
    add_column :servers, :last_changed_user_sha256_at, :datetime
  end
end
