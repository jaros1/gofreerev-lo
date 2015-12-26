class SystemparametersDestroyPrivateKeyPasSsword < ActiveRecord::Migration
  # fixed invalid system parameter name in constraints.rb (first deploy)
  def up
    s = SystemParameter.find_by_name('private_key_pasSsword')
    s.destroy! if s
  end
  def down
    nil
  end
end
