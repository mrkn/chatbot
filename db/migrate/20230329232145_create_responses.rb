class CreateResponses < ActiveRecord::Migration[7.0]
  def change
    create_table :responses do |t|
      t.references :query, null: false, foreign_key: true
      t.string :text
      t.integer :n_query_tokens
      t.integer :n_response_tokens
      t.jsonb :body
      t.boolean :good

      t.timestamps
    end
  end
end
