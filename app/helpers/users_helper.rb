module UsersHelper

  # document user balance calculation in users/show page (mouse over for balance)
  def gift_balance_calculation_doc(gift, current_user)
    api_gift = gift.api_gifts.find { |ag| [ag.user_id_giver, ag.user_id_receiver].index(current_user.user_id)}
    return nil if !api_gift.user_id_giver or !api_gift.user_id_receiver
    return nil if !gift.price or gift.price <= 0
    # format documentation for balance.
    # one format without currency and exchange rate if exchange rate == 1
    # one format with currency and exchange rate if exchange rate != 1
    # format: new balance yyy user currency = old balance xxx +- (price - negative interest) * exchange rate
    balance_doc = gift.balance_doc(current_user)
    return nil unless balance_doc
    users_currency = @users.first.currency
    exchange_rate1 = ExchangeRate.exchange(1.0, gift.currency, users_currency, gift.received_at)
    exchange_rate2 = ExchangeRate.exchange(1.0, 'USD', users_currency, gift.received_at)
    exchange_rate3 = ExchangeRate.exchange(1.0, 'USD', users_currency, balance_doc[:previous_date])
    return nil unless exchange_rate1 and exchange_rate2 and exchange_rate3
    old_balance_hash = balance_doc[:previous_balance]
    old_balance = (old_balance_hash[BALANCE_KEY] * exchange_rate3).round(2)
    sign_negative_interest = old_balance >= 0 ? '-' : '+'
    # calculate exchange rate gains/losses
    # that is previous_balance + negative_interest in old (date=previous_date) and new (date=received_at) exchange rates
    # calculation is done in current users actual currency
    # note that gains/losses changes if current user selects to see balance in an other currency
    previous_date = balance_doc[:previous_date]
    if previous_date != gift.received_at.to_yyyymmdd
      old_exchange_rates = balance_doc[:previous_exchange_rates]
      new_exchange_rates = balance_doc[:exchange_rates]
      previous_date = balance_doc[:previous_date]
      previous_balance_hash = balance_doc[:previous_balance]
      negative_interest_hash = balance_doc[:negative_interest]
      old_sum = 0.0
      new_sum = 0.0
      previous_balance_hash.keys.each do |currency|
        next if currency == BALANCE_KEY
        logger.debug2  "gift id = #{gift.id}, currency = #{currency}"
        amount = previous_balance_hash[currency] + negative_interest_hash[currency]
        old_sum += ExchangeRate.exchange(amount / old_exchange_rates[currency], 'USD', current_user.currency, previous_date)
        new_sum += ExchangeRate.exchange(amount / new_exchange_rates[currency], 'USD', current_user.currency, gift.received_at)
      end
      gain_loss = new_sum - old_sum
      logger.debug2  "exchange rate gains/losses. gift id #{gift.id}, gain/loss #{gain_loss}"
    else
      gain_loss = 0.0
    end
    # 4 translation key elements: balance_title [, exchange_rate ] [, negative_interest] [, gain/loss] - [, xxx] are optional elements
    # 12 translation keys: balance_title, balance_title_gain, balance_title_loss, balance_title_exchange_rate, balance_title_exchange_rate_gain,
    #                      balance_title_exchange_rate_loss, balance_title_negative_interest, balance_title_negative_interest_gain,
    #                      balance_title_negative_interest_loss, balance_title_exchange_rate_negative_interest,
    #                      balance_title_exchange_rate_negative_interest_gain and balance_title_exchange_rate_negative_interest_loss
    translate_key = ['.balance_title']
    translate_key << 'exchange_rate' if exchange_rate1.round(3) != 1.000
    negative_interest = gift.balance_doc(current_user)[:negative_interest][BALANCE_KEY] || 0.00
    negative_interest = negative_interest * exchange_rate3
    translate_key << 'negative_interest' if negative_interest.round(2) != 0.00
    if gain_loss.round(2) != 0.00
      if gain_loss > 0.00
        translate_key << 'gain'
        sign_gain_loss = '+'
      else
        translate_key << 'loss'
        sign_gain_loss = '-'
        gain_loss = -gain_loss
      end
    end
    translate_key = translate_key.join('_')
    # todo: add more documentation for gain/loss calculation?
    number_of_days = (gift.received_at.to_date - Date.parse(previous_date)).to_i
    t translate_key, # calculation: new_balance = old_balance + price * exchange_rate + negative_interest + currency_gain_loss
                        :new_balance => format_price(gift.balance(current_user, @users.first)),
                        :old_balance => format_price(old_balance),
                        :sign_price => balance_doc[:sign],
                        :price => format_price(gift.price),
                        :exchange_rate => exchange_rate1.round(6),
                        :sign_negative_interest => sign_negative_interest,
                        :negative_interest => format_price(negative_interest),
                        :sign_currency_gain_loss => sign_gain_loss,
                        :currency_gain_loss => format_price(gain_loss),
                        :new_currency => users_currency,
                        :old_currency => gift.currency,
                        :number_of_days => number_of_days
  end # gift_balance_calculation_doc

  # helpers for friends filter and invite friends link
  # shown in one or 2 lines depending on screen width
  def friends_filter_text
    t '.friends_filter_prompt', :appname => APP_NAME, :appname_camelized => APP_NAME.camelize
  end # app_friends_tex

  def app_friends_yes_link (page_values)
    if %w(yes).index(page_values[:friends])
      t('.friends_yes_link_text')
    else
      link_to t('.friends_yes_link_text'), users_path(page_values.merge(:friends => 'yes'))
    end
  end # show_app_friends_link

  def app_friends_no_link (page_values)
    if page_values[:friends] == 'no'
      t('.friends_no_link_text')
    else
      link_to t('.friends_no_link_text'), users_path(page_values.merge(:friends => 'no'))
    end
  end # not_app_friends_link

  def app_friends_all_link (page_values)
    if page_values[:friends] == 'all'
      t('.friends_all_link_text')
    else
      link_to t('.friends_all_link_text'), users_path(page_values.merge(:friends => 'all'))
    end
  end # all_friends_friends_link

  def app_friends_find_link (page_values)
    if page_values[:friends] == 'find'
      t('.friends_find_link_text')
    else
      link_to t('.friends_find_link_text'), users_path(page_values.merge(:friends => 'find'))
    end
  end # all_friends_friends_link

  def app_friends_me_link (page_values)
    if page_values[:friends] == 'me'
      t('.friends_me_link_text')
    else
      link_to t('.friends_me_link_text'), users_path(:friends => 'me')
    end
  end # all_friends_friends_link

  def app_user_filter_text
    t '.app_user_filter_prompt', :appname => APP_NAME, :appname_camelized => APP_NAME.camelize
  end

  def app_user_yes_link (page_values)
    if %w(yes).index(page_values[:appuser])
      t('.app_user_yes_link_text')
    else
      link_to t('.app_user_yes_link_text'), users_path(page_values.merge(:appuser => 'yes'))
    end
  end

  def app_user_no_link (page_values)
    if %w(no).index(page_values[:appuser])
      t('.app_user_no_link_text')
    else
      link_to t('.app_user_no_link_text'), users_path(page_values.merge(:appuser => 'no'))
    end
  end

  def app_user_all_link (page_values)
    if %w(all).index(page_values[:appuser])
      t('.app_user_all_link_text')
    else
      link_to t('.app_user_all_link_text'), users_path(page_values.merge(:appuser => 'all'))
    end
  end

  def api_user_link (provider, page_values)
    if provider == 'all'
      if page_values[:apiname] == 'all'
        t '.api_user_all_link_text'
      else
        link_to t('.api_user_all_link_text'), users_path(page_values.merge(:apiname => 'all'))
      end
    else
      if provider == page_values[:apiname]
        provider_camelize(provider)
      else
        link_to provider_camelize(provider), users_path(page_values.merge(:apiname => provider))
      end
    end
  end



  # user_nav_link is used in users/show nav links - up to 9 links in up to 3 sections
  # nav links is displayed in 1, 2 or 3 lines in users/show page depending on screen width
  # prefix must match prefix for entries in users/user_nav_links in locals
  def user_nav_link (options)
    logger.debug2  "users_helper.user_nav_link: input options = #{options}"
    prefix = options.delete(:prefix)
    symbol = case prefix
               when 'tabs' then :tab
               when 'deal_status' then :status
               when 'deal_direction' then :direction
               else
                 logger.debug2  "error in users/_user_nav_links. user_nav_link must be called with prefix tabs, deal_status or deal_direction"
             end
    page_values = options.delete(:page_values)
    page_value = page_values[symbol]
    array_value = options.delete(:array_value)
    # options.delete(:array_values) # only :array_value is in options hash
    raise "found :array_values" if options.has_key?(:array_values) # todo: remove
    if array_value == page_value
      # inactive link - current tab or current filter value
      t ".#{prefix}_#{page_value}"
    else
      # active link - link to new tab or new filter value
      options = page_values.clone
      options[:id] = @user2.id
      options[symbol] = array_value
      key = ".#{prefix}_#{array_value}"
      logger.debug2  "link key = #{key}, link options = #{options}"
      link_to (t key), user_path(options)
    end
  end # user_nav_link

  # check if Gofreerev is using facebook friend list (FACEBOOK_FRIEND_LIST)
  # and if user has authorized user friend list to Gofreerev ({"permission"=>"user_friends", "status"=>"granted"})
  # must return true or false. used in users.index.fb_friend_list_<boolean> translation
  # display reason why facebook friend list is (almost) empty
  def facebook_friend_list
    return false unless FACEBOOK_USER_FRIENDS
    login_user = @users.find { |u| u.provider == 'facebook' }
    permission = login_user.permissions.find { |h| h['permission'] == 'user_friends' }
    return false unless permission
    (permission['status'] == 'granted')
  end # facebook_friend_list

end
