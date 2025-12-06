// test-connection.js
require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const SUPA_URL = process.env.SUPABASE_URL;
const SUPA_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPA_URL || !SUPA_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
  process.exit(1);
}

const supa = createClient(SUPA_URL, SUPA_KEY, { auth: { persistSession: false } });

async function run() {
  try {
    const { data, error } = await supa.from('uploads').select('id, upload_type, contractor_name').limit(5);
    if (error) {
      console.error('Supabase query error:', error);
      process.exit(1);
    }
    console.log('Connected to Supabase. Sample rows (may be empty):');
    console.table(data);
    process.exit(0);
  } catch (err) {
    console.error('Unexpected error:', err);
    process.exit(1);
  }
}

run();
