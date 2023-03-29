class CreateResponses < ActiveRecord::Migration[7.0]
  def change
    create_table :responses do |t|
      t.references :query, null: false, foreign_key: true
      t.string :text, null: false
      t.integer :n_query_tokens, null: false
      t.integer :n_response_tokens, null: false
      t.jsonb :body, null: false
      t.boolean :good

      t.timestamps
    end
  end
end
