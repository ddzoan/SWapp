require 'net/imap'
require 'mail'
require 'net/smtp'

def send_email(type, recipient, subject, messagedata)
  case type
  when :confirmation
    message = "From: ICheckYouIn <#{$options[:login]}>\nTo: <#{recipient}>\n" +
      "Subject: #{subject}\n" +
      "Your checkin has been logged.\n" +
      "First Name: #{messagedata[:firstname]}\n" +
      "Last Name: #{messagedata[:lastname]}\n" +
      "Confirmation Number: #{messagedata[:confirmation]}\n" +
      "Checkin Time in Pacific Time: #{messagedata[:checkintime].localtime}"
  when :delete
    message = "From: ICheckYouIn <#{$options[:login]}>\nTo: <#{recipient}>\n" +
      "Subject: #{subject}\n" +
      "The following checkin is being DELETED due to duplicate confirmation number. You will receive a confirmation email for the replacement flight\n" +
      "First Name: #{messagedata[:firstname]}\n" +
      "Last Name: #{messagedata[:lastname]}\n" +
      "Confirmation Number: #{messagedata[:confirmation]}\n" +
      "Checkin Time in Pacific Time: #{messagedata[:checkintime].localtime}"
  when :error
    message = "From: ICheckYouIn <#{$options[:login]}>\nTo: <#{recipient}>\n" +
      "Subject: #{subject}\n" +
      "Error message is below \n\n#{messagedata[:message]}"
  when :notifydan
    message = "From: ICheckYouIn <#{$options[:login]}>\nTo: <#{recipient}>\n" +
      "Subject: #{subject}\n" +
      "Error message is below\n\n#{messagedata[:message]}"
  end

  smtp = Net::SMTP.new 'smtp.gmail.com', 587
  smtp.enable_starttls
  smtp.start('gmail.com', $options[:login], $options[:password], :login)
  smtp.send_message(message, $options[:login], recipient)
  smtp.finish
end

def log_data()
  mailIds = $imap.search(['ALL'])
  mailIds.each do |id|
    envelope = $imap.fetch(id, "ENVELOPE")[0].attr["ENVELOPE"]

    # using net/imap
    msg = $imap.fetch(id,'RFC822')[0].attr['RFC822']
    # using Mail object
    email = Mail.new(msg)
    subject = email.subject
    sender = email.from.first

    # catch exceptions if necessary checkin data is not found
    begin

    raise EmailScrape::EmailFromSouthwest if sender.downcase.include?('southwest')

    received_date = email.date
    if email.multipart?
      body = email.html_part.body.decoded
    else
      body = email.body.decoded
    end

    confnum, checkin_hashes = email_parser(body, sender)

    # Delete any old entries with the same confirmation num. Assumption: only updated itineraries will be sent in and old entries deleted
    # Someone who knows other confirmation numbers could potentially delete entries
    ActiveRecord::Base.connection_pool.with_connection do
      Checkindata.where(confnum: confnum).each do |ci|
        send_email(:delete, ci.email_sender, "DELETING checkin for #{ci.firstname} #{ci.lastname}", {firstname: ci.firstname,lastname: ci.lastname,confirmation: ci.confnum, checkintime: ci.time})
        ci.delete
      end
    end

    checkin_hashes.each do |checkindata|

      ActiveRecord::Base.connection_pool.with_connection do
        Checkindata.create(checkindata)
      end

      send_email(:confirmation, sender, "re: #{subject}", {firstname: checkindata[:firstname], lastname: checkindata[:lastname], confirmation: checkindata[:confnum], checkintime: checkindata[:time]})
    end

    # move email to logged folder
    $imap.copy(id, "logged")
    $imap.store(id, "+FLAGS", [:Deleted])

    puts "copied #{id} #{subject} to logged and flagged for deletion" if $debug

    rescue EmailScrape::Error => e
      puts "#{e.message}. Moving it to errors folder!"
      $logger.error("#{e.message}. Moving it to errors folder!")
      # File.open('errors/emailscrape/log.txt', 'a') { |file| file.write(Time.now.to_s + ' ' + e.message + ' "' + subject + "\"\n") }

      send_email(:notifydan,$options[:notify], "Bad southwest email received", {message: "A message was moved to the errors folder \n\n#{e.message}\n\n#{e.backtrace}"})
      if !sender.downcase.include?("southwest")
        send_email(:error,sender, "re: #{subject}", {message: "An error has occurred while trying to log your data. \n\n#{e.message}"})
      end

      $imap.copy(id, "errors")
      $imap.store(id, "+FLAGS", [:Deleted])

      puts "copied #{id} to errors and flagged for deletion" if $debug
    end
  end

  $imap.expunge
end

def log_in(login = $options[:login], password = $options[:password])
  $imap = Net::IMAP.new('imap.gmail.com', ssl: true)
  $imap.login(login, password)
  $imap.select('INBOX')
end
