class VerifyGiftsAddColumnError < ActiveRecord::Migration
  def change
    add_column :verify_gifts, :error, :string
  end
end
