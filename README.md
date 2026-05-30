# 🔒 ShieldNumber — Backend

Smart masked number for India. Unknown callers blocked. Phonebook contacts allowed through.

---

## Setup in 30 minutes

### Step 1 — Install Node.js
Download from nodejs.org — install LTS version

### Step 2 — Clone & install
```bash
cd shieldnumber
npm install
```

### Step 3 — Set up database (Supabase — free)
1. Go to supabase.com → New project
2. Copy the "Connection string" from Settings → Database
3. Paste into .env as DATABASE_URL

### Step 4 — Fill in your .env file
```bash
cp .env.example .env
# Now open .env and fill in:
# EXOTEL_API_KEY    → from Exotel dashboard → Settings → API
# EXOTEL_API_TOKEN  → same page
# EXOTEL_VIRTUAL_NUMBER → the number you buy in Exotel
# DATABASE_URL      → from Supabase
```

### Step 5 — Run locally to test
```bash
npm run dev
# Server starts on http://localhost:3000
# Check: http://localhost:3000/health
```

### Step 6 — Deploy to Railway (free tier)
1. Go to railway.app → New Project → Deploy from GitHub
2. Add all .env variables in Railway dashboard
3. Railway gives you a URL like https://shieldnumber-xxx.railway.app
4. That's your APP_URL

### Step 7 — Configure Exotel webhooks
In Exotel dashboard → Your App → Settings:
```
Incoming Call webhook : POST https://your-url.railway.app/webhook/call
Incoming SMS webhook  : POST https://your-url.railway.app/webhook/sms
```

### Step 8 — Buy a virtual number in Exotel
Dashboard → Numbers → Buy Number → Indian Mobile Number
Set that number to use your app's webhooks

### Step 9 — Register your first user (yourself)
```bash
curl -X POST https://your-url.railway.app/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "realNumber": "+91YOUR_REAL_NUMBER",
    "maskedNumber": "+91YOUR_EXOTEL_NUMBER"
  }'
```

### Step 10 — Test it!
1. From a different phone → call your Exotel number
2. Should be BLOCKED (number not in phonebook)
3. Add your test number to phonebook:
```bash
curl -X POST https://your-url.railway.app/api/phonebook/add \
  -H "Content-Type: application/json" \
  -d '{
    "realNumber": "+91YOUR_REAL_NUMBER",
    "contactNumber": "+91TEST_NUMBER",
    "contactName": "Test Friend"
  }'
```
4. Call again → should CONNECT to your real number

---

## API Reference

### Register user
`POST /api/register`
```json
{ "realNumber": "+919876543210", "maskedNumber": "+919111111111" }
```

### Add temp whitelist (e.g. delivery rider for 2 hours)
`POST /api/whitelist/temp`
```json
{
  "realNumber": "+919876543210",
  "callerNumber": "+919000000000",
  "label": "Zomato rider",
  "hoursValid": 2
}
```

### Bulk sync phonebook from app
`POST /api/phonebook/bulk`
```json
{
  "realNumber": "+919876543210",
  "contacts": [
    { "number": "+919111111111", "name": "Mom" },
    { "number": "+919222222222", "name": "Office" }
  ]
}
```

### Get call + SMS logs
`GET /api/logs?realNumber=+919876543210`

---

## Exotel Account Details
- Account SID : anujvvermahuf1
- Region      : Singapore
- Subdomain   : api.exotel.com

⚠️  Never commit your .env file to GitHub. Add it to .gitignore.
