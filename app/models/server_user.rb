class ServerUser < ActiveRecord::Base

  belongs_to :server
  belongs_to :user

end
