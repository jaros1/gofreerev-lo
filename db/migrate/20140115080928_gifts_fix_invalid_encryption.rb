class GiftsFixInvalidEncryption < ActiveRecord::Migration

  # fix "TypeError: no implicit conversion of nil into String" error for some encrypted fields
  # could be a old problem after refactoring old gifts into new gifts and api_gifts tables
  def change
    fields = %w(description currency price received_at balance_giver balance_receiver
                balance_doc_giver balance_doc_receiver app_picture_rel_path)
    Gift.all.select('id').each do |g1|
      fields.each do |field|
        begin
          g2 = Gift.where("id = ?", g1.id).select("gift_id,#{field}").first
          x = g2[field]
        rescue TypeError => e
          if e.message == 'no implicit conversion of nil into String'
            puts "Invalid encryption gift id #{g1.id} and field #{field}"
            Gift.update_all "#{field} = null", "id = #{g1.id}"
          else
            raise
          end
        rescue OpenSSL::Cipher::CipherError => e
          if e.message == 'iv length too short'
            puts "Invalid encryption gift id #{g1.id} and field #{field}"
            Gift.update_all "#{field} = null", "id = #{g1.id}"
          else
            raise
          end
        end
      end # each field
    end # each g1
  end

end
