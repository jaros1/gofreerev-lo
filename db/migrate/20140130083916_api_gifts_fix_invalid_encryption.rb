class ApiGiftsFixInvalidEncryption < ActiveRecord::Migration

  #create_table "api_gifts", force: true do |t|
  #  t.string   "gift_id",                     limit: 20
  #  t.string   "provider",                    limit: 20
  #  t.string   "user_id_giver",               limit: 40
  #  t.string   "user_id_receiver",            limit: 40
  #  t.string   "picture",                     limit: 1
  #  t.text     "api_gift_id"
  #  t.text     "api_picture_url"
  #  t.text     "api_picture_url_updated_at"
  #  t.text     "api_picture_url_on_error_at"
  #  t.string   "deleted_at_api",              limit: 1
  #  t.datetime "created_at"
  #  t.datetime "updated_at"
  #  t.string   "deep_link_id",                limit: 20
  #  t.text     "deep_link_pw"
  #  t.integer  "deep_link_errors"
  #  t.text     "api_gift_url"
  #end

  def change
    fields = %w(api_gift_id api_picture_url api_picture_url_updated_at api_picture_url_on_error_at deep_link_pw api_gift_url)
    ApiGift.all.select('id').each do |ag1|
      fields.each do |field|
        begin
          ag2 = ApiGift.where("id = ?", ag1.id).select("gift_id,#{field}").first
          x = ag2[field]
        rescue TypeError => e
          if e.message == 'no implicit conversion of nil into String'
            puts "Invalid encryption api gift id #{ag1.id} and field #{field}"
            ApiGift.update_all "#{field} = null", "id = #{ag1.id}"
          else
            raise
          end
        rescue OpenSSL::Cipher::CipherError => e
          if e.message == 'iv length too short'
            puts "Invalid encryption api gift id #{ag1.id} and field #{field}"
            ApiGift.update_all "#{field} = null", "id = #{ag1.id}"
          else
            raise
          end
        end
      end # each field
    end # each g1
  end
end
