require 'test_helper'

class UserMailerTest < ActionMailer::TestCase

  test "friends_suggestions" do
    mail = UserMailer.friends_suggestions
    assert_equal "Friends suggestions", mail.subject
    assert_equal ["to@example.org"], mail.to
    assert_equal ["from@example.com"], mail.from
    assert_match "Hi", mail.body.encoded
  end

end
