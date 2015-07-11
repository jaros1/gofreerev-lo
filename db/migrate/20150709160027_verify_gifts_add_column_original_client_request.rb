class VerifyGiftsAddColumnOriginalClientRequest < ActiveRecord::Migration
  def change
    add_column :verify_gifts, :original_client_request, :string
  end
end
