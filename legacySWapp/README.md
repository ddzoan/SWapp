# swapp
SWapp is a tool I wrote to automatically check me in for Southwest flights. While building this, I learned about HTTP and REST conventions. The admin panel is built on Sinatra. I also learned about IMAP and SMTP and used it to check and send emails. The gmail checker logs in to gmail and retrieves all new messages. These messages are parsed and the relevant data is extracted and stored in a mySQL database. The flight checker inner will query the DB for checkins coming up and will attempt to POST to Southwest's servers to check in for the flight as soon as the checkin window opens to get the user the best possible seat.

Warning: SWapp was written when I was learning to code. The code is gross and I plan to rewrite this at some point.

## How to use
description coming soon...
