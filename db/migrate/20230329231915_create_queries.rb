class CreateQueries < ActiveRecord::Migration[7.0]
  def change
    create_table :queries do |t|
      t.references :message, null: false, foreign_key: true
      t.string :text, null: false
      t.jsonb :body, null: false

      t.timestamps
    end
  end
end
