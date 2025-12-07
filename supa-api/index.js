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

const upload = multer({ dest: 'tmp/' });

async function uploadFileToStorage(multerFile, destPath) {
  const fileStream = fs.createReadStream(multerFile.path);
  const { data, error } = await supa.storage.from(BUCKET).upload(destPath, fileStream, { upsert: false });
  if (error) throw error;
  return data?.path || destPath;
}

async function createSignedUrlForPath(storagePath) {
  const { data, error } = await supa.storage.from(BUCKET).createSignedUrl(storagePath, SIGNED_URL_EXPIRES);
  if (error) {
    console.warn('createSignedUrl error', error);
    return null;
  }
  return data?.signedURL ?? null;
}

//pagupload ning files for resumption
app.post('/resumption', upload.any(), async (req, res) => {
  try {
    const {
      type: uploadType,
      contractorName,
      projectName,
      notes,
      supporting_files_metadata
    } = req.body;

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

    const uploadedFilesInfo = [];

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

    let supportMeta = [];
    if (supporting_files_metadata) {
      try {
        supportMeta = JSON.parse(supporting_files_metadata);
      } catch (err) {
        console.warn('Invalid supporting_files_metadata JSON:', err);
      }
    }

    for (const supType of supportMeta) {
      const type = supType.type;
      const title = supType.title || null;
      const items = supType.items || [];

      for (const it of items) {
        const mf = files.find(f => f.originalname === it.filename);
        if (!mf) {
          console.warn('No uploaded file found for filename', it.filename);
          continue;
        }

        const dest = `uploads/${uploadId}/${type}/${path.basename(mf.originalname)}`;
        const storagePath = await uploadFileToStorage(mf, dest);
        const signedUrl = await createSignedUrlForPath(storagePath);

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

    for (const f of files) {
      try { fs.unlinkSync(f.path); } catch (e) {}
    }

    return res.json({ ok: true, uploadId, files: uploadedFilesInfo });
  } catch (err) {
    console.error('Upload error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

// Get list of all uploads
app.get('/resumption/list', async (req, res) => {
  try {
    const { page = 1, limit = 20, type = 'resumption' } = req.query;
    const offset = (page - 1) * limit;

    let query = supa
      .from('uploads')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false });

    if (type) {
      query = query.ilike('upload_type', `%${type}%`);
    }

    query = query.range(offset, offset + parseInt(limit) - 1);

    const { data, error, count } = await query;

    if (error) throw error;

    return res.json({ 
      ok: true, 
      uploads: data, 
      total: count,
      page: parseInt(page),
      limit: parseInt(limit)
    });
  } catch (err) {
    console.error('List error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

// Get single upload with all files
app.get('/resumption/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Get upload details
    const { data: uploadData, error: uploadError } = await supa
      .from('uploads')
      .select('*')
      .eq('id', id)
      .single();

    if (uploadError) throw uploadError;

    // Get all supporting files for this upload
    const { data: filesData, error: filesError } = await supa
      .from('supporting_files')
      .select('*')
      .eq('upload_id', id)
      .order('doc_type', { ascending: true });

    if (filesError) throw filesError;

    // Generate signed URLs for all files
    const filesWithUrls = await Promise.all(
      filesData.map(async (file) => {
        const signedUrl = await createSignedUrlForPath(file.storage_path);
        return { ...file, signedUrl };
      })
    );

    return res.json({ 
      ok: true, 
      upload: uploadData, 
      files: filesWithUrls 
    });
  } catch (err) {
    console.error('Detail error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

// Add these endpoints to your existing index.js

// Get list of all uploads (add this after your existing POST endpoint)
app.get('/resumption/list', async (req, res) => {
  try {
    const { page = 1, limit = 20, type = 'resumption' } = req.query;
    const offset = (page - 1) * limit;

    let query = supa
      .from('uploads')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false });

    if (type) {
      query = query.ilike('upload_type', `%${type}%`);
    }

    query = query.range(offset, offset + parseInt(limit) - 1);

    const { data, error, count } = await query;

    if (error) throw error;

    return res.json({ 
      ok: true, 
      uploads: data, 
      total: count,
      page: parseInt(page),
      limit: parseInt(limit)
    });
  } catch (err) {
    console.error('List error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

// Get single upload with all files (add this)
app.get('/resumption/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Get upload details
    const { data: uploadData, error: uploadError } = await supa
      .from('uploads')
      .select('*')
      .eq('id', id)
      .single();

    if (uploadError) throw uploadError;

    // Get all supporting files for this upload
    const { data: filesData, error: filesError } = await supa
      .from('supporting_files')
      .select('*')
      .eq('upload_id', id)
      .order('doc_type', { ascending: true });

    if (filesError) throw filesError;

    // Generate signed URLs for all files
    const filesWithUrls = await Promise.all(
      filesData.map(async (file) => {
        const signedUrl = await createSignedUrlForPath(file.storage_path);
        return { ...file, signedUrl };
      })
    );

    return res.json({ 
      ok: true, 
      upload: uploadData, 
      files: filesWithUrls 
    });
  } catch (err) {
    console.error('Detail error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

// Delete an upload (optional - add this if you want delete functionality)
app.delete('/resumption/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // First get all files to delete from storage
    const { data: files, error: fetchError } = await supa
      .from('supporting_files')
      .select('storage_path')
      .eq('upload_id', id);

    if (fetchError) throw fetchError;

    // Delete files from storage
    const storagePaths = files.map(f => f.storage_path);
    if (storagePaths.length > 0) {
      const { error: storageError } = await supa.storage
        .from(BUCKET)
        .remove(storagePaths);
      
      if (storageError) throw storageError;
    }

    // Delete supporting files records
    const { error: filesError } = await supa
      .from('supporting_files')
      .delete()
      .eq('upload_id', id);

    if (filesError) throw filesError;

    // Delete the upload record
    const { error: uploadError } = await supa
      .from('uploads')
      .delete()
      .eq('id', id);

    if (uploadError) throw uploadError;

    return res.json({ ok: true, message: 'Upload deleted successfully' });
  } catch (err) {
    console.error('Delete error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

// POST /pert  -- handle PERT/CPM/PDM uploads
app.post('/pert', upload.any(), async (req, res) => {
  try {
    // fields sent from Flutter
    const {
      type = 'PERT/CPM/PDM',
      contractorName = null,
      projectName = null,
      certifierName = null,
      certifierDesignation = null,
      certificationDate = null,
      pert_metadata = null // JSON string
    } = req.body;

    // Insert upload row into 'uploads' table (add certifier fields as extra columns if present)
    const { data: uploadRow, error: uploadError } = await supa
      .from('uploads')
      .insert({
        upload_type: type,
        contractor_name: contractorName,
        project_name: projectName,
        notes: null,
        certifier_name: certifierName,
        certifier_designation: certifierDesignation,
        certification_date: certificationDate ? certificationDate : null
      })
      .select('id')
      .single();

    if (uploadError) throw uploadError;
    const uploadId = uploadRow.id;

    const files = req.files || [];
    const uploadedFilesInfo = [];

    // parse metadata if provided (expected structure from Flutter: { mode: 'original'|'revised', items: [{ label, filename }, ... ] })
    let meta = null;
    try {
      if (pert_metadata) meta = JSON.parse(pert_metadata);
    } catch (e) {
      console.warn('Invalid pert_metadata JSON:', e);
      meta = null;
    }

    // helper to find metadata item by filename
    const findMetaByFilename = (filename) => {
      if (!meta || !Array.isArray(meta.items)) return null;
      return meta.items.find(it => it.filename === filename || it.filename === encodeURIComponent(filename));
    };

    // process each uploaded file
    for (const mf of files) {
      // determine doc_type and label:
      // prefer metadata match by originalname; else derive from fieldname prefix after 'pert_original_' or 'pert_revised_'
      const originalName = mf.originalname;
      const fieldName = mf.fieldname || '';
      const metaItem = findMetaByFilename(originalName);

      // doc_type: either 'PERT-ORIGINAL' or 'PERT-REVISED' derived from fieldName or meta.mode
      let docType = 'PERT';
      if (fieldName.startsWith('pert_original') || (meta && meta.mode === 'original')) docType = 'PERT_ORIGINAL';
      if (fieldName.startsWith('pert_revised') || (meta && meta.mode === 'revised')) docType = 'PERT_REVISED';

      // label/title: prefer metadata label, else derive a friendly label from fieldName, else use original filename
      let label = metaItem?.label ?? null;
      if (!label) {
        // fieldName like 'pert_original_notice_of_award' -> 'Notice of award'
        if (fieldName.startsWith('pert_')) {
          const parts = fieldName.replace(/^pert_(original|revised)_?/, '').split('_').filter(Boolean);
          if (parts.length > 0) {
            label = parts.join(' ').replace(/\b\w/g, c => c.toUpperCase());
          }
        }
      }
      if (!label) label = originalName;

      // upload to storage
      const dest = `uploads/${uploadId}/pert/${path.basename(originalName)}`;
      const storagePath = await uploadFileToStorage(mf, dest);
      const signedUrl = await createSignedUrlForPath(storagePath);

      // insert DB record for supporting_files
      const { error: sfError } = await supa.from('supporting_files').insert({
        upload_id: uploadId,
        doc_type: docType,
        doc_title: label,
        label: label,
        filename: originalName,
        storage_path: storagePath,
        station: null,
        caption: null,
        latitude: null,
        longitude: null
      });

      if (sfError) throw sfError;

      uploadedFilesInfo.push({
        filename: originalName,
        fieldName,
        storage_path: storagePath,
        signedUrl,
        doc_type: docType,
        label
      });
    }

    // return success
    return res.json({ ok: true, uploadId, files: uploadedFilesInfo });
  } catch (err) {
    console.error('PERT upload error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});


const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server listening on ${PORT}`);
});
