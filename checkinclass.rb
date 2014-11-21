require 'time'
require 'rest_client'
require 'nokogiri'
require 'active_record'

class Checkindata < ActiveRecord::Base
  def timeToCheckin()
    time - Time.now
  end

  def tryToCheckin?()
    if checkedin
      return false
    elsif attempts > 10
      return false
    else
      return timeToCheckin < 3
    end
  end

  def flight_checkin()
    self.increment!(:attempts)
    $logger.info("Starting attempt #{attempts} for db id #{id}")
    form = { :'previously-selected-bar-panel' => "check-in-panel",
      :confirmationNumber => confnum,
      :firstName => firstname,
      :lastName => lastname,
      :submitButton => "Check In" }

    checkin_doc = "http://www.southwest.com/flight/retrieveCheckinDoc.html"

    $logger.info("About to POST to SW")
    response = RestClient.post(checkin_doc,form) { |response, request, result, &block| response }

    cookie = response.cookies
    $logger.info("POSTed and got cookies")

    if response.code == 200
      $logger.info("Got 200 response, parsing page")
      page = Nokogiri::HTML(response.body)
      if page.css("div#error_wrapper").length == 1
        $logger.info("GOT ERROR DIV, WRITING ERROR TO FILE")
        puts "GOT ERROR DIV, WRITING ERROR TO FILE"
        File.open("errors/#{Time.now.to_s.split[0..1].join}_" + confnum + '_errordiv.html', 'w') { |file| file.write(page.css("div#error_wrapper").text) }
        $logger.info(page.css("div#error_wrapper").text)
      else
        $logger.info("got 200, should have gotten 302, writing page to file")
        puts "got 200, should have gotten 302, writing page to file"
        File.open(Time.now.to_s.split[0..1].join + '_bad200.html', 'w') { |file| file.write(page) }
        $logger.info("wrote to file")
      end

      return false
    elsif response.code == 302
      # puts "forwarded to: #{response.headers[:location]}"

      #follow forward
      $logger.info("got 302, not following forwards")
      #$logger.info("got 302, following response forward")
      #response = RestClient.get(response.headers[:location],:cookies => cookie) { |response, request, result, &block| response }
      #page = Nokogiri::HTML(response.body)
      #$logger.info("followed 302 forward and noko-parsed new page")
      #not sure why I follow the forward when I don't use any of this data for the actual checkin, maybe waste of time?
      
      #if page.css("input.swa_buttons_submitButton")[0]['title'] == "Check In"
        real_checkin = "http://www.southwest.com/flight/selectPrintDocument.html"
        checkin_form = { :'checkinPassengers[0].selected' => true, :printDocuments => "Check In" }
 
        $logger.info("about to do final POST to actually check in")
        final_response = RestClient.post(real_checkin,checkin_form,:cookies => cookie) { |response, request, result, &block| response }
        $logger.info("POSTed to final page to actually check in")
        if final_response.code == 302
          redir = final_response.headers[:location]
          $logger.info("following redirect after actually checked in")
          redirpage = RestClient.get(redir,:cookies => cookie) { |response, request, result, &block| response }
          $logger.info("should be SUCCESS at #{Time.now}")
          puts "Should be SUCCESS at #{Time.now}"
          page = Nokogiri::HTML(redirpage.body)
          $logger.info(page.css('.passenger_name').text.strip.split.join(' '))
          $logger.info(page.css('td.boarding_group').text + page.css('td.boarding_position').text)
          puts page.css('.passenger_name').text.strip.split.join(' ')
          puts page.css('td.boarding_group').text + page.css('td.boarding_position').text
          
          self.response_code = redirpage.code
          self.response_name = page.css('.passenger_name').text.strip.split.join(' ')
          self.response_boarding = page.css('td.boarding_group').text + page.css('td.boarding_position').text
          self.checkin_time = Time.now.iso8601(3)
          $logger.info("stored response_code, response_name, response_boarding, and checkin_time")
          
          self.resp_page_file = checkin_time.to_s.split[0..1].join('_') + '_' + confnum + '.html'
          $logger.info("about to write checkinpage to checkinpages/#{self.resp_page_file}")
          File.open("checkinpages/#{self.resp_page_file}", 'w') { |file| file.write(redirpage.body) }
          $logger.info("wrote checkinpage to file")
          
          self.checkedin = true

          self.save
          if self.email_sender #if email was blank, don't send mobile boarding pass
            select_email_boarding_pass(self.email_sender, confnum, final_response.cookies)
          end
          return true
        end
      #end
    else
      $logger.info("UNKNOWN RESPONSE, CODE: #{response.code}")
      filename = "errors/#{Time.now.to_s.split[0..1].join}_" + confnum + "_code#{response.code}.html"
      $logger.info("about to write response page to #{filename}")
      
      File.open(filename, 'w') { |file| file.write(response.headers + "\n" + response.body) }
      sleep 1
    end
  end
end

def select_email_boarding_pass(email_address, confnum, cookies)
  emailform = { _optionPrint: 'on',
    optionEmail: 'true',
    _optionEmail: 'on',
    emailAddress: email_address,
    _optionText: 'on',
    book_now: 'Continue' }
  email_post = "http://www.southwest.com/flight/selectCheckinDocDelivery.html"
  $logger.info("doing POST to tell southwest to email boarding pass")
  get_boarding = RestClient.post(email_post,emailform,:cookies => cookies) { |response, request, result, &block| response }
  $logger.info("did POST for email boarding pass and about to write to file")
  #filename = Time.now.to_s.split[0..1].join('_') + '_' + confnum + '_emailselect.html'
  #File.open(filename, 'w') { |file| file.write(get_boarding.body) }
  #$logger.info("wrote response to file")
end
