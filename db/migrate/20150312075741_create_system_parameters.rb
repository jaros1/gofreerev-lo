class CreateSystemParameters < ActiveRecord::Migration
  def change
    create_table :system_parameters do |t|
      t.string :name
      t.text :value
      t.timestamps
    end
    add_index "system_parameters", ["name"], name: "index_system_parameters_name", unique: true, using: :btree

  end
end
