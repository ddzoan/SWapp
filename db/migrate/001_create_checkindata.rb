class CreateCheckindata < ActiveRecord::Migration
  def self.up
    unless ActiveRecord::Base.connection.tables.include? 'checkindata'
      create_table :checkindata do |table|
        table.string :firstname
        table.string :lastname
        table.string :confnum
        table.datetime :time
        table.boolean :checkedin, default: false
        table.integer :attempts, default: 0
        table.integer :response_code
        table.string :resp_page_file
        table.string :response_name
        table.string :response_boarding
        table.string :checkin_time
      end
    end
  end
 
  def self.down
    drop_table :checkindata
  end
end
