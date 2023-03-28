class CreateConversations < ActiveRecord::Migration[7.0]
  def change
    create_table :conversations do |t|
      t.string :slack_id
      t.string :name

      t.timestamps
    end
    add_index :conversations, :slack_id, unique: true
  end
end
