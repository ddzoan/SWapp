const puppeteer = require('puppeteer');

async function checkin() {
  const {page, browser} = await initialize();
  const confirmationNumber = '';
  const firstName = '';
  const lastName = '';
  const email = '';

  // DELAYED CHECKIN
  // const checkinMinute = 55;
  // const now = new Date;
  // const timeUntil = ((checkinMinute - now.getMinutes() - 1) * 60 + (60 - now.getSeconds())) * 1000 - 500;
  // console.log(`${now} waiting for ${timeUntil} milliseconds before starting`);
  // await page.waitFor(timeUntil);

  let attempts = 0;
  while(attempts < 10) {
    try {
      console.log(new Date().toISOString(), 'Attempt #', ++attempts);
      await mainPageCheckin(page, {confirmationNumber, firstName, lastName})
        .then(page => checkInVerify(page))
        .then(page => emailPass(page, email));
      attempts = 10;
    } catch (e) {
      console.log(`Error on page: ${e}`);
      // console.log('waiting one second');
      // await page.waitFor(1000);
    }
  }

  console.log('success!');

  await page.waitFor(1000);
  browser.close();
}

async function initialize() {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  return {page, browser};
}

async function mainPageCheckin(page, {confirmationNumber, firstName, lastName}) {
  console.log('checking in: ', confirmationNumber, firstName, lastName);
  await page.goto('https://www.southwest.com/air/check-in/index.html');
  await page.type('#confirmationNumber', confirmationNumber);
  await page.type('#passengerFirstName', firstName);
  await page.type('#passengerLastName', lastName);
  await page.click('#form-mixin--submit-button');
  // await page.waitFor(100);
  if (await page.$('.page-error_results') !== null) {
    throw new Error('error on checkin page, maybe too early');
  }
  await page.screenshot({path: 'screenshots/hitsubmit.png'});
  return page;
}

async function checkInVerify(page) {
  try {
    console.log('checkInVerify');
    await page.waitFor('button.submit-button.air-check-in-review-results--check-in-button', {timeout: 500});
    await page.click('button.submit-button.air-check-in-review-results--check-in-button');
    await page.screenshot({path: 'screenshots/afterVerify.png'});
  } catch (error) {
    throw new Error('checkInVerify')
  }
  return page;
}

async function emailPass(page, email) {
  try {
    console.log('emailPass');
    await page.click('.boarding-pass-options--button-email');
    await page.type('#emailBoardingPass', email);
    await page.click('#form-mixin--submit-button');

    await page.waitFor(100);
    await page.screenshot({path: 'screenshots/sentEmail.png'});

  } catch (error) {
    throw new Error('emailPass')
  }
  return page;
}

checkin();

module.exports = {
  checkin,
  initialize,
  mainPageCheckin,
  checkInVerify,
  emailPass
};
