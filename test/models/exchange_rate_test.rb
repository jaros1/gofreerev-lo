require 'test_helper'

class ExchangeRateTest < ActiveSupport::TestCase

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

  def assert_exchange_rate (options)
    from_amount = 1.0
    from_currency = options[:from_currency]
    to_currency = options[:to_currency]
    expected_exchange_rate = options[:exchange_rate]
    days_ago = options[:days_ago] || 0
    date = days_ago.days.ago.to_yyyymmdd
    found_exchange_rate = ExchangeRate.exchange(from_amount, from_currency, to_currency, date)
    msg_prefix = "#{days_ago} days ago - #{date} - #{from_currency} => #{to_currency}: "
    if !expected_exchange_rate
      assert false, "#{msg_prefix}Expected nil exchange rate. Found #{found_exchange_rate.round(6)}" if found_exchange_rate
      return
    end
    assert found_exchange_rate != nil, "#{msg_prefix}Could not find exchange rate"
    assert expected_exchange_rate.round(6) == found_exchange_rate.round(6), "#{msg_prefix}Expected #{expected_exchange_rate.round(6)}. Found #{found_exchange_rate.round(6)}"
  end # assert_exchange_rate

  test "dkk_usd_today" do
    assert_exchange_rate :from_currency => 'DKK',
                         :to_currency => 'USD',
                         :days_ago => 0,
                         :exchange_rate => 0.177063 # 1.0 / 5.6477073132162
  end # dkk_usd_today

  test "sek_dkk_today" do
    assert_exchange_rate :from_currency => 'SEK',
                         :to_currency => 'DKK',
                         :days_ago => 0,
                         :exchange_rate => 0.8673495465769783 # 1.0 / 6.51145473644974 * 5.6477073132162
  end

  test "usd_eur_today" do
    assert_exchange_rate :from_currency => 'USD',
                         :to_currency => 'EUR',
                         :days_ago => 0, # No EUR exchange rates
                         :exchange_rate => nil
  end


  test "usd_to_usd_999_days_ago" do
    assert_exchange_rate :from_currency => 'USD',
                         :to_currency => 'USD',
                         :days_ago => 999,
                         :exchange_rate => 1.000000
  end

  test "sek_dkk_1_20_days_ago" do
    1.upto(20) do |days_ago|
      assert_exchange_rate :from_currency => 'SEK',
                           :to_currency => 'DKK',
                           :days_ago => days_ago, # 20 days ago
                           :exchange_rate => 0.9586494988482395 # 1.0 / 6.185881999627252 * 5.930092678877011
    end
  end

  test "sek_dkk_21_50_days_ago" do
    21.upto(50) do |days_ago|
      assert_exchange_rate :from_currency => 'SEK',
                           :to_currency => 'DKK',
                           :days_ago => days_ago, # 50 days ago
                           :exchange_rate => 1.0595599724112121 # 1.0 / 5.876587899645889 * 6.226597312820862
    end
  end

  test "sek_dkk_51_100_days_ago" do
    51.upto(100) do |days_ago|
      assert_exchange_rate :from_currency => 'SEK',
                           :to_currency => 'DKK',
                           :days_ago => days_ago, # 100 days ago
                           :exchange_rate => 1.1710926010860767 # 1.0 / 5.582758504663595 * 6.537927178461905
    end
  end

end
