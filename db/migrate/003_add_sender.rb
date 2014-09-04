class AddSenderToCheckindata < ActiveRecord::Migration
  def change
    add_column :checkindata, :email_sender, :string
  end
end