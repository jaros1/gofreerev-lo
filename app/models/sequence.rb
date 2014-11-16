LAST_MONEY_BANK_REQUEST = 'last_money_bank_request'
LAST_EXCHANGE_RATE_DATE = 'last_exchange_rate_date'

class Sequence < ActiveRecord::Base

  private
  def self.get_status_update_at
    name = 'status_update_at_seq'
    s = Sequence.find_by_name(name)
    if !s
      s = Sequence.new
      s.name = name
      s.value = 0
      s.save!
    end
    s
  end # self.get_status_update_at

  public
  def self.status_update_at
    Sequence.get_status_update_at.value
  end # self.status_update_at

  public
  def self.next_status_update_at
    transaction do
      s = Sequence.get_status_update_at
      s.value = s.value + 1
      s.save!
      return s.value
    end # do
  end # self.status_update_at

  # get/set last_money_bank_request
  # used in ExchangeRate.fetch_exchange_rates
  # about 166
  def self.get_last_money_bank_request
    s = Sequence.find_by_name(LAST_MONEY_BANK_REQUEST)
    s.value if s
  end # self.get_last_money_bank_request
  def self.set_last_money_bank_request (hour)
    hour = 0 unless hour
    s = Sequence.find_by_name(LAST_MONEY_BANK_REQUEST)
    if !s
      s = Sequence.new
      s.name = LAST_MONEY_BANK_REQUEST
    end
    s.value = hour.to_s
    s.save!
  end # self.set_last_money_bank_request

  # get/set date for last set of currency exchange rates from default money bank
  # used in ExchangeRate
  def self.get_last_exchange_rate_date
    s = Sequence.find_by_name(LAST_EXCHANGE_RATE_DATE)
    return nil unless s
    s.value.to_s
  end # self.get_last_exchange_rate_date
  def self.set_last_exchange_rate_date (today)
    raise "invalid argument" unless today.to_s.yyyymmdd?
    s = Sequence.find_by_name(LAST_EXCHANGE_RATE_DATE)
    if !s
      s = Sequence.new
      s.name = LAST_EXCHANGE_RATE_DATE
    end
    s.value = today.to_s.to_i
    s.save!
  end # self.set_last_exchange_rate_date


end
