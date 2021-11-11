class CreateSoccerStats < ActiveRecord::Migration[5.2]
  def change
    drop_table :soccer_stats

    create_table :soccer_stats do |t|
      t.integer :correct_guesses
      t.integer :total_guesses

      t.timestamps
    end
  end
end
