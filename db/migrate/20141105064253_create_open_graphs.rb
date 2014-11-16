class CreateOpenGraphs < ActiveRecord::Migration
  def change
    create_table :open_graphs do |t|
      t.text :url
      t.string :title
      t.string :description
      t.text :image
      t.timestamps
      t.datetime :last_usage_at
    end
  end
end
