class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :slack_id, null: false
      t.string :name
      t.string :real_name
      t.string :email
      t.integer :tz_offset

      t.timestamps
    end
    add_index :users, :slack_id, unique: true
    add_index :users, :email, unique: true
  end
end
