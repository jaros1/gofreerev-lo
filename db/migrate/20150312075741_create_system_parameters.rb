class CreateSystemParameters < ActiveRecord::Migration
  def change
    create_table :system_parameters do |t|
      t.string :name
      t.text :value
      t.timestamps
    end
  end
end
