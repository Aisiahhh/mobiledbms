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

// single helper to upload to storage (returns storage path)
async function uploadFileToStorage(multerFile, destPath) {
  try {
    const fileStream = fs.createReadStream(multerFile.path);
    const { data, error } = await supa.storage.from(BUCKET).upload(destPath, fileStream, { upsert: false });
    if (error) {
      // throw error object so caller can inspect
      const err = new Error('Supabase storage upload error');
      err.details = error;
      throw err;
    }
    return data?.path || destPath;
  } catch (err) {
    const e = new Error(`uploadFileToStorage failed for ${multerFile.originalname}: ${err.message || err}`);
    e.inner = err;
    throw e;
  }
}

async function createSignedUrlForPath(storagePath) {
  const { data, error } = await supa.storage.from(BUCKET).createSignedUrl(storagePath, SIGNED_URL_EXPIRES);
  if (error) {
    console.warn('createSignedUrl error', error);
    return null;
  }
  return data?.signedURL ?? null;
}

/**
 * Resumption POST (existing)
 * (unchanged except minor cleanups)
 */
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

/**
 * GET list endpoint (unchanged)
 */
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

/**
 * GET detail endpoint (unchanged)
 */
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

/**
 * Delete endpoint (unchanged)
 */
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

/**
 * PERT upload endpoint (fixed)
 * Accepts pert_metadata as either:
 *  - an array of groups: [{ type: 'A', title:'..', items:[{filename:..., label:...}, ...] }, ...]
 *  - OR a single object { mode: 'original', items: [{filename:..., label:...}, ...] }
 */
app.post('/pert', upload.any(), async (req, res) => {
  try {
    console.log('[PERT] route hit');
    console.log('[PERT] body:', req.body);
    console.log('[PERT] files count:', (req.files || []).length);

    const {
      type: uploadType = '',
      contractorName = '',
      projectName = '',
      certifierName = '',
      certifierDesignation = '',
      certificationDate = '',
      pert_metadata = null
    } = req.body;

    // Basic validation
    if (!contractorName || !projectName) {
      return res.status(400).json({ ok: false, error: 'contractorName and projectName are required' });
    }

    // Insert upload row - do not include certification_date unless you really have that column
    const insertPayload = {
      upload_type: uploadType || 'PERT',
      contractor_name: contractorName || null,
      project_name: projectName || null,
      notes: null,
      certifier_name: certifierName || null,
      certifier_designation: certifierDesignation || null
    };

    // Only add certification_date if it exists and is non-empty; safe if column missing, remove this line if you get PGRST errors
    // If you still get PGRST204 (missing column), remove/comment the following conditional.
    if (certificationDate && certificationDate.trim() !== '') {
      insertPayload.certification_date = certificationDate;
    }

    const { data: uploadRow, error: uploadError } = await supa
      .from('uploads')
      .insert(insertPayload)
      .select('id')
      .single();

    if (uploadError) {
      console.error('[PERT] supa insert upload error', uploadError);
      throw uploadError;
    }

    const uploadId = uploadRow.id;
    const files = req.files || [];
    const uploadedFilesInfo = [];

    // Parse pert_metadata defensively:
    let parsedMeta = null;
    try {
      parsedMeta = pert_metadata ? JSON.parse(pert_metadata) : null;
    } catch (parseErr) {
      console.warn('[PERT] pert_metadata parse error', parseErr);
      parsedMeta = null;
    }

    // Normalize into array of groups (metaGroups)
    let metaGroups = [];
    if (Array.isArray(parsedMeta)) {
      metaGroups = parsedMeta;
    } else if (parsedMeta && Array.isArray(parsedMeta.items)) {
      // client sent single object with items array (your case)
      metaGroups = [{ type: parsedMeta.mode || 'original', title: parsedMeta.title || null, items: parsedMeta.items }];
    } else {
      metaGroups = [];
    }

    // Build map filename -> metadata (for quick lookup). If multiple items share same filename,
    // latest will win (you can adjust logic if you want to allow duplicates)
    const metaByFilename = {};
    for (const g of metaGroups) {
      const gtype = g.type || null;
      const gtitle = g.title || null;
      if (!Array.isArray(g.items)) continue;
      for (const it of g.items) {
        if (!it || !it.filename) continue;
        metaByFilename[it.filename] = {
          type: gtype,
          title: gtitle,
          label: it.label || null,
          station: it.station || null,
          caption: it.caption || null,
          lat: it.lat ?? null,
          lon: it.lon ?? null
        };
      }
    }

    // Upload files
    for (const f of files) {
      try {
        const safeName = path.basename(f.originalname);
        const dest = `pert/${uploadId}/${f.fieldname || 'files'}/${Date.now()}_${safeName}`;

        const storagePath = await uploadFileToStorage(f, dest);
        const signedUrl = await createSignedUrlForPath(storagePath);

        const metaItem = metaByFilename[f.originalname] || null;

        const insertPayload = {
          upload_id: uploadId,
          doc_type: metaItem?.type || f.fieldname || null,
          doc_title: metaItem?.title || null,
          label: metaItem?.label || null,
          filename: f.originalname,
          storage_path: storagePath,
          station: metaItem?.station || null,
          caption: metaItem?.caption || null,
          latitude: metaItem?.lat ?? null,
          longitude: metaItem?.lon ?? null
        };

        const { error: sfError } = await supa.from('supporting_files').insert(insertPayload);
        if (sfError) {
          console.error('[PERT] insert supporting_files error', sfError);
          throw sfError;
        }

        uploadedFilesInfo.push({
          filename: f.originalname,
          fieldname: f.fieldname,
          storage_path: storagePath,
          signedUrl,
          meta: metaItem
        });
      } catch (fileErr) {
        console.error('[PERT] error uploading single file', f.originalname, fileErr);
        uploadedFilesInfo.push({ filename: f.originalname, error: String(fileErr) });
      }
    }

    // cleanup tmp
    for (const f of files) {
      try {
        fs.unlinkSync(f.path);
      } catch (e) { /* ignore */ }
    }

    return res.json({ ok: true, uploadId, files: uploadedFilesInfo });
  } catch (err) {
    console.error('[PERT] unexpected error:', err);
    const message = err && err.message ? err.message : String(err);
    const details = err && err.details ? err.details : null;
    return res.status(500).json({ ok: false, error: message, details });
  }
});

app.get('/pert/list', async (req, res) => {
  try {
    const { page = 1, limit = 20, search = '' } = req.query;
    const offset = (page - 1) * limit;

    // Start building the query
    let query = supa
      .from('uploads')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false });

    // Filter for PERT submissions - check for any upload_type containing PERT
    query = query.or('upload_type.ilike.%PERT%,upload_type.ilike.%CPM%,upload_type.ilike.%PDM%');

    // Optional search
    if (search) {
      query = query.or(`contractor_name.ilike.%${search}%,project_name.ilike.%${search}%`);
    }

    query = query.range(offset, offset + parseInt(limit) - 1);

    const { data, error, count } = await query;

    if (error) throw error;

    // Also get file counts for each upload
    const uploadsWithFileCounts = await Promise.all(
      data.map(async (upload) => {
        const { count: fileCount } = await supa
          .from('supporting_files')
          .select('*', { count: 'exact', head: true })
          .eq('upload_id', upload.id);

        return {
          ...upload,
          file_count: fileCount || 0
        };
      })
    );

    return res.json({ 
      ok: true, 
      uploads: uploadsWithFileCounts, 
      total: count,
      page: parseInt(page),
      limit: parseInt(limit)
    });
  } catch (err) {
    console.error('[PERT List] error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

/**
 * GET single PERT submission with details
 */
app.get('/pert/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Get upload details
    const { data: uploadData, error: uploadError } = await supa
      .from('uploads')
      .select('*')
      .eq('id', id)
      .single();

    if (uploadError) throw uploadError;

    // Get all supporting files for this upload, specifically for PERT
    const { data: filesData, error: filesError } = await supa
      .from('supporting_files')
      .select('*')
      .eq('upload_id', id)
      .order('created_at', { ascending: true });

    if (filesError) throw filesError;

    // Generate signed URLs for all files
    const filesWithUrls = await Promise.all(
      filesData.map(async (file) => {
        const signedUrl = await createSignedUrlForPath(file.storage_path);
        return { ...file, signedUrl };
      })
    );

    // Determine if this is original or revised based on upload_type or metadata
    const isRevised = uploadData.upload_type && uploadData.upload_type.toLowerCase().includes('revised');
    const mode = isRevised ? 'revised' : 'original';

    // Group files by type or fieldname
    const groupedFiles = {};
    filesWithUrls.forEach(file => {
      const type = file.doc_type || file.fieldname || 'other';
      if (!groupedFiles[type]) {
        groupedFiles[type] = [];
      }
      groupedFiles[type].push(file);
    });

    return res.json({ 
      ok: true, 
      upload: uploadData, 
      files: filesWithUrls,
      groupedFiles,
      mode,
      fileCount: filesWithUrls.length
    });
  } catch (err) {
    console.error('[PERT Detail] error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

/**
 * DELETE PERT submission
 */
app.delete('/pert/:id', async (req, res) => {
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
      
      if (storageError) {
        console.warn('Failed to delete some files from storage:', storageError);
        // Continue anyway
      }
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

    return res.json({ ok: true, message: 'PERT submission deleted successfully' });
  } catch (err) {
    console.error('[PERT Delete] error:', err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server listening on ${PORT}`);
});
