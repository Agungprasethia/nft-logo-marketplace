require('dotenv').config();
const express = require('express');
const cors = require('cors');
const cronService = require('./src/cron/cronService');

const { admin } = require('./src/config/firebase');

const app = express();
app.use(cors());
app.use(express.json());

// Routes
const apiRoutes = require('./src/routes/api');
app.use('/api', apiRoutes);

app.get('/', (req, res) => {
  res.send('LEO NFT Marketplace Backend API');
});

// Start Cron Jobs
cronService.startCronJobs();

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
