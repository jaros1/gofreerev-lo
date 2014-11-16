#
# This script can be used to generate encryption keys.
# Save your secret keys in a save location on the server and keep backups.
# Keys must be constant and can not be changed if they are used in the database.
# Run this script once at project start and never again (unless your keys has been exposed).
# You must empty the database for data and starting from scratch if the keys are lost
# Do not store the keys in clear text in rails source.
#

# comment the next line if you wish to run this script


# number of keys and key length
APPNAME = 'GOFREEREV'
RAILS_ENVS = %w(DEV TEST PROD)
NO_KEYS = 60
KEY_LNG = 140

# change if you wish other character set og other random generator.
def generate_random_string (lng)
  chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
  newpass = ''
  1.upto(lng) { newpass << chars[rand(chars.size-1)] }
  newpass
end # generate_random_string

# generate keys - save in ruby array
keys = {}
RAILS_ENVS.each do |rails_env|
  keys[rails_env] = []
  1.upto(NO_KEYS) { |i| keys[rails_env][i] = generate_random_string(KEY_LNG) }
end

# output bash script
puts  ''
puts  '# you could store your secret keys in linux/bash:'
RAILS_ENVS.each do |rails_env|
  1.upto(NO_KEYS) do |i|
    keyname = "#{APPNAME}_#{rails_env}_KEY_#{i}"
    puts  "#{keyname}=#{keys[rails_env][i]}"
    puts  "export #{keyname}"
  end
end

# todo: output keys in other formats, linux shell, windows dos etc

# output rails constraint to be inserted in /config/initializers/constraints.rb
puts  ""
puts  "insert this ruby constant in /config/initializers/constraints.rb"
puts ""
puts "railsenv = case Rails.env when 'development' then 'DEV' when 'test' then 'TEST' when 'production' then 'PROD' end"
puts "encrypt_keys = []"
puts "1.upto(#{NO_KEYS}).each do |keyno|"
puts '  encrypt_keys << ENV["GOFREEREV_#{railsenv}_KEY_#{keyno}"]'
puts "end"
puts "ENCRYPT_KEYS = encrypt_keys"
puts ""

