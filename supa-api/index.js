// index.js
require('dotenv').config();
const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');

const SUPA_URL = process.env.SUPABASE_URL;
const SUPA_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET = process.env.STORAGE_BUCKET || 'resumption-uploads';
const SIGNED_URL_EXPIRES = parseInt(process.env.SIGNED_URL_EXPIRES_SEC || String(60 * 60), 10); // seconds

if (!SUPA_URL || !SUPA_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in environment.');
  process.exit(1);
}

const supa = createClient(SUPA_URL, SUPA_KEY, { auth: { persistSession: false }});

const app = express();
app.use(cors());
app.use(express.json());

// multer tmp storage (disk). Ensure tmp/ exists or multer will create temp files.
const upload = multer({ dest: 'tmp/' });

// Helper: upload a local file (multer) to supabase storage. Returns storage path.
async function uploadFileToStorage(multerFile, destPath) {
  const fileStream = fs.createReadStream(multerFile.path);
  // upload accepts Buffer or ReadableStream
  const { data, error } = await supa.storage.from(BUCKET).upload(destPath, fileStream, { upsert: false });
  if (error) throw error;
  return data?.path || destPath;
}

// Helper: create signed URL for a storage path
async function createSignedUrlForPath(storagePath) {
  const { data, error } = await supa.storage.from(BUCKET).createSignedUrl(storagePath, SIGNED_URL_EXPIRES);
  if (error) {
    console.warn('createSignedUrl error', error);
    return null;
  }
  return data?.signedURL ?? null;
}

// POST /upload
app.post('/upload', upload.any(), async (req, res) => {
  try {
    const {
      type: uploadType,
      contractorName,
      projectName,
      notes,
      supporting_files_metadata
    } = req.body;

    // Insert upload row
    const { data: uploadRow, error: uploadError } = await supa
      .from('uploads')
      .insert({
        upload_type: uploadType,
        contractor_name: contractorName,
        project_name: projectName,
        notes: notes
      })
      .select('id')
      .single();

    if (uploadError) throw uploadError;
    const uploadId = uploadRow.id;

    const files = req.files || [];

    // Collect response info
    const uploadedFilesInfo = []; // { filename, storage_path, signedUrl, doc_type, label, upload_row_id }

    // Handle known required fields
    const requiredFields = [
      { field: 'required_letter_request', doc_type: 'required', label: 'Letter Request of the Contractor for Contract Time Resumption' },
      { field: 'required_approved_suspension', doc_type: 'required', label: 'Approved Suspension Order' },
      { field: 'required_certified_contract', doc_type: 'required', label: 'Certified True Copy of Original Contract' },
    ];

    for (const rf of requiredFields) {
      const mf = files.find(f => f.fieldname === rf.field);
      if (mf) {
        const dest = `uploads/${uploadId}/${rf.field}/${path.basename(mf.originalname)}`;
        const storagePath = await uploadFileToStorage(mf, dest);
        const signedUrl = await createSignedUrlForPath(storagePath);

        // insert meta row
        await supa.from('supporting_files').insert({
          upload_id: uploadId,
          doc_type: rf.doc_type,
          doc_title: rf.label,
          label: rf.label,
          filename: mf.originalname,
          storage_path: storagePath
        });

        uploadedFilesInfo.push({
          filename: mf.originalname,
          storage_path: storagePath,
          signedUrl,
          doc_type: rf.doc_type,
          label: rf.label
        });
      }
    }

    // Parse supporting_files_metadata JSON (client should send mapping)
    let supportMeta = [];
    if (supporting_files_metadata) {
      try {
        supportMeta = JSON.parse(supporting_files_metadata);
      } catch (err) {
        console.warn('Invalid supporting_files_metadata JSON:', err);
        // don't throw — continue but warn
      }
    }

    // supportMeta expected format:
    // [ { type: 'A', title: '...', items: [ { label, filename, station, caption, lat, lon }, ... ] }, ... ]

    for (const supType of supportMeta) {
      const type = supType.type;
      const title = supType.title || null;
      const items = supType.items || [];

      for (const it of items) {
        // find multer file whose originalname matches it.filename
        const mf = files.find(f => f.originalname === it.filename);
        if (!mf) {
          console.warn('No uploaded file found for filename', it.filename);
          continue;
        }

        const dest = `uploads/${uploadId}/${type}/${path.basename(mf.originalname)}`;
        const storagePath = await uploadFileToStorage(mf, dest);
        const signedUrl = await createSignedUrlForPath(storagePath);

        // insert DB row
        await supa.from('supporting_files').insert({
          upload_id: uploadId,
          doc_type: type,
          doc_title: title,
          label: it.label || null,
          filename: mf.originalname,
          storage_path: storagePath,
          station: it.station || null,
          caption: it.caption || null,
          latitude: typeof it.lat === 'number' ? it.lat : (it.lat ? Number(it.lat) : null),
          longitude: typeof it.lon === 'number' ? it.lon : (it.lon ? Number(it.lon) : null)
        });

        uploadedFilesInfo.push({
          filename: mf.originalname,
          storage_path: storagePath,
          signedUrl,
          doc_type: type,
          label: it.label || null,
          station: it.station || null,
          caption: it.caption || null,
          lat: it.lat ?? null,
          lon: it.lon ?? null
        });
      }
    }

    // cleanup tmp files
    for (const f of files) {
      try { fs.unlinkSync(f.path); } catch (e) {}
    }

    return res.json({ ok: true, uploadId, files: uploadedFilesInfo });
  } catch (err) {
    console.error('Upload error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server listening on ${PORT}`);
});
