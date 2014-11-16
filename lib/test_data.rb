# load manual test data - for multi login friend finder test

require File.join(File.dirname(__FILE__), '../config/environment')
testdata = YAML::load_file(Rails.root.join('lib', 'friends_test_data.yml'))

def find_create_user (user_id, user_name)
  user = User.find_by_user_id(user_id)
  if !user
    # create missing from user
    puts "    ... creating missing #{provider} user #{user_id} #{user_name}"
    user = User.new
    user.user_id = user_id_with_provider
    user.user_name = user_name
    user.currency = BASE_CURRENCY
    user.balance = { BALANCE_KEY => 0.0 }
    user.post_on_wall_yn = 'N'
    user.save!
    friend = Friend.new
    friend.user_id_giver = user_id
    friend.user_id_receiver = user_id
    friend.api_friend = 'Y'
    friend.app_friend = nil
    friend.save!
  end
end # find_create_user

testdata.each do |provider, from_users|
  puts "Provider = #{provider}"
  next unless from_users
  from_users.each do |from_user_id, from_user_hash|
    next unless from_user_hash
    next unless from_user_hash['name']
    next unless from_user_hash['friends']
    from_user_id_with_provider = "#{from_user_id}/#{provider}"
    puts "  from user #{from_user_id_with_provider} #{from_user_hash['name']}"
    find_create_user(from_user_id_with_provider, from_user_hash['name'])
    friends_hash = {}
    # loop for from users friends
    from_user_hash['friends'].each do |to_user_id, to_user_hash|
      next unless to_user_hash['name']
      to_user_id_with_provider = "#{to_user_id}/#{provider}"
      puts "    to user #{to_user_id_with_provider} #{to_user_hash['name']}"
      friends_hash[to_user_id_with_provider] = { :name => to_user_hash['name'] }
    end
    new_user, key, options = Friend.update_api_friends_from_hash :login_user_id => from_user_id_with_provider,
                                                                 :friends_hash => friends_hash
    puts "    key = #{key}, options = #{options}" if key
  end
end

# find friends test

# find user combinations for login users
login_user = User.find(984) # alk
# login_user = User.find(920) # jr

share_accounts = [ login_user.user_combination ]

user_ids = [ '1705481075/facebook','117657151428689087350/google_oauth2' ]
users = User.where('user_id in (?)', user_ids)
friends = Friend.where(:user_id_giver => user_ids)
friends_friends = Friend.where(:user_id_giver => Friend.select('user_id_receiver').where(:user_id_giver => user_ids)).includes(:friend)
friends_friends2 = Friend.where(:user_id_giver => Friend.select('user_id_receiver').where(:user_id_giver => user_ids)).includes(:friend).collect { |f| f.friend }.uniq







