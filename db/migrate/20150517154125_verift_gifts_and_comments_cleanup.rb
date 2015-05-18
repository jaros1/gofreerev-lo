class VeriftGiftsAndCommentsCleanup < ActiveRecord::Migration
  def change
    VerifyGift.delete_all
    VerifyComment.delete_all
    s = Sequence.find_by_name('verify_gift_seq')
    s.destroy if s
  end
end
