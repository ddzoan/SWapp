class AddColumnsCheckindata < ActiveRecord::Migration
  def change
    add_column :products, :part_number, :string
    add_column :checkindata, :departing_airport, :string
    add_column :checkindata, :depart_time, :datetime
    add_column :checkindata, :arriving_airport, :string
    add_column :checkindata, :arrive_time, :datetime
    add_column :checkindata, :flight_number, :string
    add_column :checkindata, :conf_date, :date
  end
end