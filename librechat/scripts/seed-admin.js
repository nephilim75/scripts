#!/usr/bin/env node
/**
 * scripts/seed-admin.js
 *
 * Legt den ersten Admin-User in LibreChat's MongoDB an.
 * Wird vom Installer als einmaliger docker-run Container ausgeführt.
 *
 * Erwartete ENV-Variablen:
 *   MONGO_URI         - z. B. mongodb://mongodb:27017/librechat
 *   ADMIN_EMAIL       - z. B. admin@example.com
 *   ADMIN_USERNAME    - z. B. Max Mustermann
 *   ADMIN_PASSWORD    - Klartext (min. 12 Zeichen)
 */

const { MongoClient } = require('mongodb');
const bcrypt = require('bcrypt');
const crypto = require('crypto');

const BCRYPT_COST = 12;

async function main() {
  const {
    MONGO_URI,
    ADMIN_EMAIL,
    ADMIN_USERNAME,
    ADMIN_PASSWORD,
  } = process.env;

  if (!MONGO_URI || !ADMIN_EMAIL || !ADMIN_USERNAME || !ADMIN_PASSWORD) {
    console.error('[seed-admin] Fehler: MONGO_URI, ADMIN_EMAIL, ADMIN_USERNAME, ADMIN_PASSWORD sind erforderlich.');
    process.exit(1);
  }

  if (ADMIN_PASSWORD.length < 12) {
    console.error('[seed-admin] Fehler: ADMIN_PASSWORD muss mindestens 12 Zeichen lang sein.');
    process.exit(1);
  }

  console.log('[seed-admin] Verbinde zu MongoDB...');
  const client = new MongoClient(MONGO_URI, {
    serverSelectionTimeoutMS: 5000,
  });

  try {
    await client.connect();
    const db = client.db();
    const users = db.collection('users');

    // Existiert User schon?
    const existing = await users.findOne({ email: ADMIN_EMAIL.toLowerCase() });
    if (existing) {
      console.log(`[seed-admin] User ${ADMIN_EMAIL} existiert bereits. Ueberspringe.`);
      console.log(`[seed-admin] Bestehende Rolle: ${existing.role || '<keine>'}`);
      // Rolle auf ADMIN setzen (idempotent)
      if (existing.role !== 'ADMIN') {
        await users.updateOne(
          { _id: existing._id },
          { $set: { role: 'ADMIN' } }
        );
        console.log('[seed-admin] Rolle auf ADMIN aktualisiert.');
      }
      return;
    }

    // Neu anlegen
    console.log('[seed-admin] Hashe Passwort (bcrypt cost ' + BCRYPT_COST + ')...');
    const passwordHash = await bcrypt.hash(ADMIN_PASSWORD, BCRYPT_COST);

    const now = new Date();
    const newUser = {
      email: ADMIN_EMAIL.toLowerCase(),
      username: ADMIN_USERNAME,
      password: passwordHash,
      role: 'ADMIN',
      emailVerified: true,
      provider: 'local',
      createdAt: now,
      updatedAt: now,
    };

    const result = await users.insertOne(newUser);
    console.log(`[seed-admin] Admin-User angelegt: ${ADMIN_EMAIL} (ID: ${result.insertedId})`);
  } catch (err) {
    console.error('[seed-admin] Fehler:', err.message);
    process.exit(1);
  } finally {
    await client.close();
  }
}

main();
