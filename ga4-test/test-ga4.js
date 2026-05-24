const { BetaAnalyticsDataClient } = require('@google-analytics/data');

process.env.GOOGLE_APPLICATION_CREDENTIALS =
  '/home/marcus/.secrets/easyhealth-ga4_v1.json';

const analyticsDataClient = new BetaAnalyticsDataClient();

async function runReport() {
  try {
    const [response] = await analyticsDataClient.runReport({
      property: 'properties/538436680',
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
    });

    console.log('SUCESSO');
    console.log(JSON.stringify(response, null, 2));
  } catch (err) {
    console.error('ERRO:');
    console.error(err);
  }
}

runReport();
