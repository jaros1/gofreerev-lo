require 'test_helper'
include ActionView::Helpers

class NilClass
  def round (options)
    nil
  end
end

class UserTest < ActiveSupport::TestCase

  # use this interrupt if you want to stop after failed test ==>
  @@interrupt = false
  def after_teardown
    @@interrupt = true if !passed? # signal that test must interrupt after this failed test has finished
    super
  end
  def before_setup
    super
    raise Interrupt if @@interrupt # previous test has failed. Interrupt test
  end
  # use this interrupt if you want to stop after failed test <==

  def debug_user_balance
    true
  end # debug_notifications

  def assert_hash (text, expected, found)
    found.keys.each do |name|
      # logger.debug2  "#{text}: #{name}. Expected #{expected[name]}. Found #{found[name]}"
      assert (expected[name].round(8) == found[name].round(8)), "#{text}: #{name} is invalid. Expected #{expected[name]}. Found #{found[name]}" if expected.has_key?(name)
    end
  end # assert_hash

  def assert_gift (gift, expected)
    logger.debug2  "balance_doc_giver = #{gift.balance_doc_giver}"
    logger.debug2  "balance_doc_receiver = #{gift.balance_doc_receiver}"
    found = { :negative_interest_giver => gift.balance_doc_giver[:negative_interest][BALANCE_KEY],
              :negative_interest_receiver => gift.balance_doc_receiver[:negative_interest][BALANCE_KEY],
              :balance_giver => gift.balance_giver,
              :balance_receiver => gift.balance_receiver,
              :previous_balance_giver => gift.balance_doc_giver[:previous_balance][BALANCE_KEY],
              :previous_balance_receiver => gift.balance_doc_receiver[:previous_balance][BALANCE_KEY]
            }
    assert_hash 'gift', expected, found
  end # assert_user_balance

  def assert_balance (user, expected)
    found = { :balance => user.balance[BALANCE_KEY],
              :usd => user.balance['USD'],
              :dkk => user.balance['DKK'],
              :sek => user.balance['SEK'] }
    assert_hash user.short_user_name, expected, found
  end # assert_balance

  # alias for fixtures
  def charlie # default currency DKK
    users(:charlie)
  end
  def u1_sandra # default currency USD
    users(:sandra)
  end
  def u2_karen # default currency USD
    users(:karen)
  end
  def u3_david # default currency DKK
    users(:david)
  end
  def u4_dick # default currency DKK
    users(:dick)
  end

  def dkk_usd
    exchange_rates(:dkk_usd).exchange_rate
  end
  def dkk_sek
    exchange_rates(:dkk_sek).exchange_rate
  end
  def sek_dkk
    exchange_rates(:sek_dkk).exchange_rate
  end
  def sek_usd
    exchange_rates(:sek_usd).exchange_rate
  end
  def usd_dkk
    exchange_rates(:usd_dkk).exchange_rate
  end
  def usd_sek
    exchange_rates(:usd_sek).exchange_rate
  end


  def create_deal(giver, receiver, price, days_ago)
    g = Gift.new
    g.description = "From #{giver.short_user_name} to #{receiver.short_user_name}"
    g.currency = giver.currency
    g.price = price.to_f
    g.user_id_giver = giver.user_id
    g.picture = 'N'
    assert g.save
    g.update_attributes! :user_id_receiver => receiver.user_id, :received_at => days_ago.days.ago(Time.now)
    g.reload
    assert (g.received_at.to_date == days_ago.days.ago(Date.today)), "create_deal: received_at is invalid. Expected #{days_ago.days.ago(Date.today)}. Found #{g.received_at.to_date}"
    g
  end # create_deal


  test "create_gift_today" do
    # simple: create gift today - 0 negative interest and 0 social dividend
    g1 = create_deal(charlie, u2_karen, 10.0, 0) # charlie 10.00 dkk today
    charlie.recalculate_balance
    u2_karen.recalculate_balance
    g1.reload
    assert_gift g1,
                :negative_interest_giver => 0.0, # no negative interest before first deal
                :negative_interest_receiver => 0.0, # no negative interest before first deal
                :previous_balance_giver => 0.0,
                :previous_balance_receiver => 0.0,
                :balance_giver => 1.77063, # charlie usd = 10 / 5.6477073132162
                :balance_receiver => -1.77063 # karen usd = -10 / 5.6477073132162
    assert_balance charlie,
                   :balance => 1.77063, # usd = 10.0 dkk / 5.6477073132162 = 1.77063 usd
                   :dkk => 10.0
    assert_balance u2_karen,
                   :balance => -1.77063, # usd = -10.0 dkk / 5.6477073132162 = -1.77063
                   :dkk => -10.0
  end # create_gift_today


  test "create_gift_100_days_ago" do
    g1 = create_deal(charlie, u2_karen, 10.0, 100) # charlie 10.00 dkk 100 days ago
    charlie.recalculate_balance
    u2_karen.recalculate_balance
    g1.reload
    # gift balance 100 days ago
    #   - charlie - 10.00 dkk = 10.00 / 6.537927178461905 = 1.5295367670877873
    #   - sandra - -10.00 dkk = -10.00 / 6.537927178461905 = -1.5295367670877873
    assert_gift g1,
                :negative_interest_giver => 0.0, # no negative interest before first deal
                :negative_interest_receiver => 0.0, # no negative interest before first deal
                :balance_giver => 1.5295367670877873, # usd
                :balance_receiver => -1.5295367670877873 # usd
    # negative interest charlie - positive balance
    #   = 10.00 - 10.00 * FACTOR_POS_BALANCE_PER_DAY ** 100
    #   = 0.13954675483425838 dkk
    #   = 0.02134418922467836 usd
    # negative interest sandra - negative balance
    #   = 10.00 - 10.00 * FACTOR_NEG_BALANCE_PER_DAY ** 100
    #   = 0.28453254702274045 dkk
    #   = 0.04352029921044162 usd
    # balance charlie:
    #   = 10.00 - 0.13954675483425838 = 9.860453245165742 dkk = 9.860453245165742 / 5.6477073132162 usd = 1.7459214329487815 usd
    # balance sandra:
    #   = -10.00 + 0.28453254702274045 = -9.71546745297726 dkk = -9.71546745297726 / 5.6477073132162 usd = -1.7202498136265125
    assert_balance charlie,
                   :balance => 1.7459214329487815, # usd
                   :dkk => 9.860453245165742
    assert_balance u2_karen,
                   :balance => -1.7202498136265125, # usd
                   :dkk => -9.71546745297726
  end # create_gift_100_days_ago

  test "create_gift_100_and_0_days_ago" do
    g1 = create_deal(charlie, u2_karen, 10.0, 100) # charlie 10.00 dkk 100 days ago
    g2 = create_deal(charlie, u2_karen, 10.0, 0) # charlie 10.00 dkk today
    charlie.recalculate_balance
    u2_karen.recalculate_balance
    g1.reload
    g2.reload

    # g1: 100 days ago. Same check as in create_gift_100_days_ago
    # gift balance 100 days ago
    #   - charlie - 10.00 dkk = 10.00 / 6.537927178461905 = 1.5295367670877873
    #   - sandra - -10.00 dkk = -10.00 / 6.537927178461905 = -1.5295367670877873
    assert_gift g1,
                :negative_interest_giver => 0.0, # no following deals yet
                :negative_interest_receiver => 0.0, # no following deals yet
                :balance_giver => 1.5295367670877873, # usd
                :balance_receiver => -1.5295367670877873 # usd

    # g2: today.
    # negative interest 100 days:
    # negative interest charlie - positive balance
    #   = 10.00 - 10.00 * FACTOR_POS_BALANCE_PER_DAY ** 100
    #   = 0.13954675483425838 dkk
    #   = 0.02134418922467836 usd
    # negative interest karen - negative balance
    #   = 10.00 - 10.00 * FACTOR_NEG_BALANCE_PER_DAY ** 100
    #   = 0.28453254702274045 dkk
    #   = 0.04352029921044162 usd
    # balance charlie
    #   = 10.00 - 0.13954675483425838 + 10.00 = 19.860453245165743 dkk = 19.860453245165743 / 5.6477073132162 = 3.516551432948782 usd
    # balance karen
    #   = -10.00 + 0.28453254702274045 -10.00 = -19.715467452977258 dkk = -19.715467452977258 / 5.6477073132162 = -3.490879813626512 usd
    assert_gift g2,
                :negative_interest_giver => 0.02134418922467836,
                :negative_interest_receiver => 0.04352029921044162,
                :balance_giver => 3.516551432948782, # charlie usd
                :balance_receiver => -3.490879813626512 # karen usd
    # check user balance
    assert_balance charlie,
                   :balance => 3.516551432948782, # dkk
                   :dkk => 19.860453245165743
    assert_balance u2_karen,
                   :balance => -3.490879813626512, # usd
                   :dkk => -19.715467452977258
  end # create_gift_100_and_0_days_ago

  test "create_gift_100_and_20_days_ago" do
    g1 = create_deal(charlie, u2_karen, 10.0, 100) # charlie 10.00 dkk 100 days ago
    g2 = create_deal(charlie, u2_karen, 10.0, 20) # charlie 10.00 dkk 20 days ago
    charlie.recalculate_balance
    u2_karen.recalculate_balance
    g1.reload
    g2.reload

    # g1 gift balance 100 days ago
    #   - charlie - 10.00 dkk = 10.00 / 6.537927178461905 = 1.5295367670877873
    #   - sandra - -10.00 dkk = -10.00 / 6.537927178461905 = -1.5295367670877873
    assert_gift g1,
                :negative_interest_giver => 0.0, # no negative interest before first deal
                :negative_interest_receiver => 0.0, # no negative interest before first deal
                :balance_giver => 1.5295367670877873, # usd
                :balance_receiver => -1.5295367670877873 # usd

    # g2 gift 20 days ago
    # charlie negative interest 80 days (100 => 20 days ago)
    #  = 10.00 - 10.00 * FACTOR_POS_BALANCE_PER_DAY ** 80 = 0.11179406655528012 dkk = 0.11179406655528012 / 6.537927178461905 = 0.017099313513856008 usd
    # karen negative interest 80 days (100 => 20 days ago)
    #  = 10.00 - 10.00 * FACTOR_NEG_BALANCE_PER_DAY ** 80 = 0.2282811966098155 dkk = 0.2282811966098155 / 6.537927178461905 = 0.03491644834495087 usd
    # charlie balance 20 days ago:
    #  = 10.00 - 0.11179406655528012 + 10.00 = 19.88820593344472 dkk = 19.88820593344472 / 5.930092678877011 = 3.3537765782795446 usd
    # karen balance 20 days ago:
    #  = -10.00 + 0.2282811966098155 - 10.00 = -19.771718803390186 dkk = -19.771718803390186 / 5.930092678877011 = -3.3341331871282627 usd
    assert_gift g2,
                :negative_interest_giver => 0.017099313513856008,
                :negative_interest_receiver => 0.03491644834495087,
                :balance_giver => 3.3537765782795446, # charlie usd
                :balance_receiver => -3.3341331871282627 # karen usd

    # balance today
    # charlie negative interest day 20 => day 0
    #   = 19.88820593344472 - 19.88820593344472 * FACTOR_POS_BALANCE_PER_DAY ** 20 = 0.055819142867171934 dkk
    # karen negative interest day 20 => day 0
    #   = 19.771718803390186 - 19.771718803390186 * FACTOR_NEG_BALANCE_PER_DAY ** 20 = 0.11381681207296523 dkk
    # charlie balance today
    #   = 19.88820593344472 - 0.055819142867171934 = 19.832386790577548 dkk = 19.832386790577548 / 5.6477073132162 = 3.511581902300032 usd
    # karen balance today
    #   = -19.771718803390186 + 0.11381681207296523 = -19.65790199131722 dkk = -19.65790199131722 / 5.6477073132162 = -3.480687100288601 usd
    # check user balance
    assert_balance charlie,
                   :balance => 3.511581902300032, # usd
                   :dkk => 19.832386790577548
    assert_balance u2_karen,
                   :balance => -3.480687100288601, # usd
                   :dkk => -19.65790199131722
  end # create_gift_100_and_20_days_ago

  test "create_gift_100_50_and_20_days_ago" do
    # charlie => sandra 10.00 dkk 100 days ago
    g1 = create_deal(charlie, u1_sandra, 10.00, 100) # 10.00 dkk - charlie balance 10.00 - sandra balance -10.00
    g2 = create_deal(charlie, u2_karen, 10.00, 50)
    g3 = create_deal(u1_sandra, u2_karen, 10.00, 20)
    charlie.recalculate_balance
    u1_sandra.recalculate_balance
    u2_karen.recalculate_balance
    g1.reload
    g2.reload
    g3.reload

    # g1: 100 days ago charlie => sandra. Same check as in create_gift_100_days_ago
    # gift balance 100 days ago
    #   - charlie - 10.00 dkk = 10.00 / 6.537927178461905 = 1.5295367670877873
    #   - sandra - -10.00 dkk = -10.00 / 6.537927178461905 = -1.5295367670877873
    assert_gift g1,
                :negative_interest_giver => 0.0, # no negative interest before first deal
                :negative_interest_receiver => 0.0, # no negative interest before first deal
                :balance_giver => 1.5295367670877873, # usd
                :balance_receiver => -1.5295367670877873 # usd

    # g2: 50 days ago (charlie => karen)
    # negative interest old user charlie for period 100 days ago to 50 days ago
    # = 10.00 - 10.00 * FACTOR_POS_BALANCE_PER_DAY ** 50 = 0.07001850698313561 dkk = 0.07001850698313561 / 6.537927178461905 = 0.010709588080729889 usd
    # no negative interest for new user karen
    # balance charlie 50 days ago
    # = 10.00 - 0.07001850698313561 + 10.00 = 19.929981493016864 dkk = 19.929981493016864 / 6.226597312820862 = 3.2007821433995867 usd
    # balance karen 50 days ago
    # = -10.00 dkk = -10.00 / 6.226597312820862 = -1.6060136054421765 usd
    assert_gift g2,
                :negative_interest_giver => 0.010709588080729889,
                :negative_interest_receiver => 0.0, # no previous deal for karen - no negative interest
                :balance_giver => 3.2007821433995867, # charlie usd
                :balance_receiver => -1.6060136054421765 # karen usd

    # g3: 20 days ago (sandra => karen)
    # sandra: balance 100 days ago: -10.00 dkk
    # karen: balance 50 days ago: -10.dkk
    # sandra negative interest 80 days
    # = 10.00 - 10.00 * FACTOR_NEG_BALANCE_PER_DAY ** 80 = 0.2282811966098155 dkk = 0.2282811966098155 / 6.537927178461905 = 0.03491644834495087 usd
    # karen negative interest 30 days
    # = 10.00 - 10.00 * FACTOR_NEG_BALANCE_PER_DAY ** 30 == 0.08622380616820635 dkk = 0.08622380616820635 / 6.226597312820862 = 0.013847660581914846 usd
    # sandra balance:
    # = (-10.00 + 0.2282811966098155) / 5.930092678877011 + 10.00 = 8.352181098586023 usd
    # karen balance:
    # = (-10.00 + 0.08622380616820635) / 5.930092678877011 - 10.00 = -11.671774242103275 usd
    assert_gift g3,
                :negative_interest_giver => 0.03491644834495087,
                :negative_interest_receiver => 0.013847660581914846,
                :balance_giver => 8.352181098586023, # sandra usd
                :balance_receiver => -11.671774242103275 # karen usd

  end # create_gift_100_and_20_days_ago

  test "two_gifts_100_days_ago" do
    g1 = create_deal(charlie, u1_sandra, 100.00, 100) # 100.00 dkk - charlie balance 100.00 dkk - sandra balance -100.00 dk
    g2 = create_deal(u1_sandra, charlie, 16.00, 100) # 16.00 usd - charlie balance -16.00 usd - sandra balance +16.00 usd
    # balance 100 days ago:
    # charlie: 100.00 dk - 16.00 usd = 100.00 / 6.537927178461905 - 16.00 = -0.7046323291221288 usd
    # sandra: -100.00 dkk + 16.00 usd = -100.00 / 6.537927178461905 + 16.00 = 0.7046323291221288 usd
    # charlie has negative balance until 50 days ago. Sandra has positive balance until 50 days ago
    # balance today:
    # charlie: 100.00 dk - 16.00 usd = 100.00 / 5.6477073132162 - 16.00 = 1.7062999999999988 usd
    # sandra: -100.00 dk + 16.00 usd = -100.00 / 5.6477073132162 + 16.00 = -1.7062999999999988 usd
    # note that balances change sign 50 days ago

    # balances 100 days ago - charlie starts with a negative balance - sandra starts with a positive balance
    date = 100.days.ago.to_date
    charlie_dkk = 100.00
    charlie_usd = -16.00
    charlie_balance = ExchangeRate.exchange(charlie_dkk, 'DKK', 'USD', date) + charlie_usd # 100.00 dk - 16.00 usd = 100.00 / 5.6477073132162 - 16.00 = 1.7062999999999988 usd
    sandra_dkk = -charlie_dkk
    sandra_usd = -charlie_usd
    sandra_balance = ExchangeRate.exchange(sandra_dkk, 'DKK', 'USD', date) + sandra_usd # -100.00 dk + 16.00 usd = -100.00 / 5.6477073132162 + 16.00 = -1.7062999999999988 usd

    # day 99..50: charlie has negative balance until 50 days ago. Sandra has positive balance until 50 days ago
    # use FACTOR_NEG_BALANCE_PER_DAY for charlie. use FACTOR_POS_BALANCE_PER_DAY for sandra
    charlie_dkk = charlie_dkk * FACTOR_NEG_BALANCE_PER_DAY ** 50
    charlie_usd = charlie_usd * FACTOR_NEG_BALANCE_PER_DAY ** 50
    sandra_dkk = sandra_dkk * FACTOR_POS_BALANCE_PER_DAY ** 50
    sandra_usd = sandra_usd * FACTOR_POS_BALANCE_PER_DAY ** 50
    date = 50.days.since(date)
    charlie_balance = ExchangeRate.exchange(charlie_dkk, 'DKK', 'USD', date) + charlie_usd
    sandra_balance = ExchangeRate.exchange(sandra_dkk, 'DKK', 'USD', date) + sandra_usd

    # day 49..0: charlie has positive balance from 50 days ago and to today. Sandra has negative balance from 50 days ago and to today
    factor = charlie_balance >= 0 ? FACTOR_POS_BALANCE_PER_DAY : FACTOR_NEG_BALANCE_PER_DAY
    charlie_dkk = charlie_dkk * factor **50
    charlie_usd = charlie_usd * factor **50
    factor = sandra_balance >= 0 ? FACTOR_POS_BALANCE_PER_DAY : FACTOR_NEG_BALANCE_PER_DAY
    sandra_dkk = sandra_dkk * factor ** 50
    sandra_usd = sandra_usd * factor ** 50
    date = 50.days.since(date)
    charlie_balance = ExchangeRate.exchange(charlie_dkk, 'DKK', 'USD', date) + charlie_usd
    sandra_balance = ExchangeRate.exchange(sandra_dkk, 'DKK', 'USD', date) + sandra_usd

    logger.debug2  "charlie: dkk = #{charlie_dkk}, usd = #{charlie_usd}, balance = #{charlie_balance}"
    logger.debug2  "sandra: dkk = #{sandra_dkk}, usd = #{sandra_usd}, balance = #{sandra_balance}"
    # charlie: dkk = 97.87691892116952, usd = -15.660307027387113, balance = 1.670073867551924
    # sandra: dkk = -97.87691892116936, usd = 15.660307027387109, balance = -1.6700738675519027
    charlie.recalculate_balance
    u1_sandra.recalculate_balance

    # charlie balance: 97.87691892116952 / 5.6477073132162 - 15.660307027387113 = 1.670073867551924
    assert_balance charlie, :dkk => 97.87691892116952,
                            :usd => -15.660307027387113,
                            :balance => 1.670073867551924
    # sandra balance: -97.87691892116936 / 5.6477073132162 + 15.660307027387109 = -1.6700738675519027
    assert_balance u1_sandra, :dkk => -97.87691892116952,
                              :usd => 15.660307027387113,
                              :balance => -1.6700738675519027

  end # two_gifts_100_days_ago

end
