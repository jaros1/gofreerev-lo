# https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
# this extension to use different encryption for each attribute and each row
ActiveRecord::Base.send :include, ActiveRecordExtensions