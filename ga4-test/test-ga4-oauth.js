const fs = require('fs');
const path = require('path');
const http = require('http');
const { google } = require('googleapis');

const keyfilePath =
  '/home/marcus/.secrets/easyhealth-ga4-oauth.json';

const keys = JSON.parse(fs.readFileSync(keyfilePath));

const oauthConfig = keys.installed || keys.web;

const oauth2Client = new google.auth.OAuth2(
  oauthConfig.client_id,
  oauthConfig.client_secret,
  'http://localhost:3010/oauth2callback'
);


const scopes = ['https://www.googleapis.com/auth/analytics.readonly'];

async function start() {
  const authUrl = oauth2Client.generateAuthUrl({
    access_type: 'offline',
    scope: scopes,
  });

  console.log('\nAbrindo navegador para login Google...\n');

 console.log('Abra este link no navegador:');
console.log(authUrl);

  const server = http
    .createServer(async (req, res) => {
      if (req.url.indexOf('/oauth2callback') > -1) {
        const qs = new URL(req.url, 'http://localhost:3010')
          .searchParams;

        const code = qs.get('code');

        res.end('Autenticado com sucesso. Pode fechar.');

        server.close();

        const { tokens } = await oauth2Client.getToken(code);

        oauth2Client.setCredentials(tokens);

        console.log('\nTOKEN GERADO:\n');
        console.log(tokens);

        const analyticsData = google.analyticsdata({
          version: 'v1beta',
          auth: oauth2Client,
        });

        const response = await analyticsData.properties.runReport({
          property: 'properties/538436680',
          requestBody: {
            dateRanges: [
              {
                startDate: '7daysAgo',
                endDate: 'today',
              },
            ],
            metrics: [
              {
                name: 'activeUsers',
              },
            ],
          },
        });

        console.log('\nRESULTADO GA4:\n');
        console.log(JSON.stringify(response.data, null, 2));
      }
    })
    .listen(3010, () => {
      console.log('Servidor OAuth iniciado na porta 3010');
    });
}

start();
