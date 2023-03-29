class CreateMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :text
      t.string :slack_ts
      t.string :slack_thread_ts

      t.timestamps
    end
    add_index :messages, :slack_ts, unique: true
    add_index :messages, :slack_thread_ts
  end
end
