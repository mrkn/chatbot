class AddSlackTsToResponse < ActiveRecord::Migration[7.0]
  def change
    add_column :responses, :slack_ts, :string, null: false
    add_index :responses, :slack_ts, unique: true
    add_column :responses, :slack_thread_ts, :string, null: false
    add_index :responses, :slack_thread_ts
  end
end
