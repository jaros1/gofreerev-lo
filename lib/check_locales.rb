# use this script to find missing translate keys in locales

require File.join(File.dirname(__FILE__), '../config/environment')

def flatten_keys(hash, prefix="")
  keys = []
  hash.keys.each do |key|
    if hash[key].is_a? Hash
      current_prefix = prefix + "#{key}."
      keys << flatten_keys(hash[key], current_prefix)
    else
      keys << "#{prefix}#{key}"
    end
  end
  prefix == "" ? keys.flatten : keys
end

# list of locales
available_locales = Rails.application.config.i18n.available_locales.collect { |locale| locale.to_s }

# load locale.yml files
locales = {}
locales['xx'] = []
available_locales.each do |locale|
  locales[locale] = flatten_keys(YAML::load_file(Rails.root.join('config', 'locales', "#{locale}.yml"))).
      collect { |key| key.from(3) }
  locales['xx'] += locales[locale]
end

# list missing translations
available_locales.each do |locale|
  missing_keys = locales['xx'] - locales[locale]
  puts "#{locale}: missing keys: #{missing_keys.join(', ')}" if missing_keys.size > 0
end